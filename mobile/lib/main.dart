import 'dart:convert';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'firebase_options.dart';
import 'core/services/fcm_service.dart';
import 'core/services/local_storage_service.dart';
import 'core/services/notification_service.dart';
import 'core/storage/secure_storage_service.dart';
import 'core/theme/app_theme.dart';
import 'data/models/message_model.dart';
import 'data/repositories/auth_repository.dart';
import 'presentation/auth/bloc/auth_bloc.dart';
import 'presentation/auth/bloc/auth_event.dart';
import 'presentation/auth/bloc/auth_state.dart';
import 'presentation/auth/pages/login_page.dart';
import 'presentation/auth/pages/register_page.dart';
import 'presentation/dashboard/pages/dashboard_page.dart';

final GlobalKey<NavigatorState> rootNavigatorKey = GlobalKey<NavigatorState>();

/// WhatsApp-style fully autonomous background message handler:
/// 1. Intercepts silent data-only FCM push when app is closed / killed / backgrounded.
/// 2. Initializes local storage connection in the standalone Dart isolate.
/// 3. Parses and immediately writes incoming chat message into local cache (messages & contacts).
/// 4. Triggers local notification banner only after local cache write succeeds.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  try {
    WidgetsFlutterBinding.ensureInitialized();

    // 1. Session check: if user is logged out, drop background notification
    final userToken = await SecureStorageService().getToken();
    final userStr = await SecureStorageService().getUser();
    if (userToken == null || userToken.isEmpty || userStr == null || userStr.isEmpty) {
      if (kDebugMode) print('[FCM] Dropping background message: user is logged out');
      return;
    }

    String currentUserId = '';
    try {
      final userData = jsonDecode(userStr);
      currentUserId = userData['id']?.toString() ?? userData['_id']?.toString() ?? '';
    } catch (_) {}
    if (currentUserId.isEmpty) return;

    // 2. Initialize Firebase in background isolate
    try {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
    } catch (_) {
      if (Firebase.apps.isEmpty) {
        await Firebase.initializeApp();
      }
    }

    final data = message.data;
    if (data.isEmpty) return;

    // 3. Parse incoming chat payload
    final senderId = data['senderId']?.toString() ?? '';
    final receiverId = data['receiverId']?.toString() ?? currentUserId;
    final senderName = data['senderName']?.toString() ?? data['title']?.toString() ?? 'User';
    final text = data['text']?.toString() ?? data['body']?.toString() ?? data['preview']?.toString() ?? '';
    final messageId = data['messageId']?.toString() ?? message.messageId ?? 'msg_${DateTime.now().millisecondsSinceEpoch}';
    final createdAt = data['createdAt']?.toString() ?? DateTime.now().toUtc().toIso8601String();
    final mediaUrl = data['mediaUrl']?.toString();
    final mediaType = data['mediaType']?.toString();
    final mediaName = data['mediaName']?.toString();
    final mediaSize = int.tryParse(data['mediaSize']?.toString() ?? '0');

    if (senderId.isEmpty && text.isEmpty && (mediaUrl == null || mediaUrl.isEmpty)) return;

    // 4. WRITE TO LOCAL CACHE IMMEDIATELY (WhatsApp background sync engine)
    final incomingMessage = MessageModel(
      id: messageId,
      senderId: senderId,
      receiverId: receiverId,
      text: text,
      createdAt: createdAt,
      mediaUrl: mediaUrl != null && mediaUrl.isNotEmpty ? mediaUrl : null,
      mediaType: mediaType != null && mediaType.isNotEmpty ? mediaType : null,
      mediaName: mediaName != null && mediaName.isNotEmpty ? mediaName : null,
      mediaSize: mediaSize,
      deliveredAt: createdAt,
    );

    final localStorage = LocalStorageService();
    // A) Append into conversation history cache so offline opening immediately has this message!
    await localStorage.appendSingleMessage(currentUserId, senderId, incomingMessage);

    // B) Update contact's unreadCount and latestMessageAt in dashboard cache
    await localStorage.recordIncomingMessage(
      currentUserId: currentUserId,
      senderId: senderId,
      senderName: senderName,
      messageText: text,
      createdAt: createdAt,
    );

    if (kDebugMode) {
      print('[FCM] Successfully cached incoming background message from $senderName ($messageId)');
    }

    // 5. Parse historical lines for multi-message WhatsApp inbox-style grouping
    List<String>? historicalLines;
    final rawLines = data['unreadLines']?.toString();
    if (rawLines != null && rawLines.isNotEmpty) {
      try {
        final decoded = jsonDecode(rawLines);
        if (decoded is List) {
          historicalLines = decoded.map((e) => e.toString()).toList();
        }
      } catch (_) {}
    }

    // 6. TRIGGER LOCAL BANNER ONLY AFTER LOCAL CACHE WRITE SUCCEEDS
    final notifService = NotificationService();
    await notifService.initialize();
    await notifService.showMessageNotification(
      senderId: senderId.isNotEmpty ? senderId : 'general',
      senderName: senderName,
      messageText: text,
      messageId: messageId,
      mediaType: mediaType,
      historicalLines: historicalLines,
    );
  } catch (e) {
    if (kDebugMode) print('[FCM] background handler error: $e');
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Register top-level background handler with Firebase Messaging
  FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
  // Pre-initialize local notifications for incoming message alerts
  await NotificationService().initialize();
  // Pre-initialize Firebase Cloud Messaging
  await FcmService().initialize();
  runApp(const ChatSpaceApp());
}

class ChatSpaceApp extends StatelessWidget {
  const ChatSpaceApp({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => AuthBloc(repository: AuthRepository())..add(const AuthStarted()),
      child: MaterialApp(
        navigatorKey: rootNavigatorKey,
        debugShowCheckedModeBanner: false,
        title: 'ChatSpace',
        theme: AppTheme.light,
        darkTheme: AppTheme.dark,
        themeMode: ThemeMode.system,
        home: const _AuthGate(),
      ),
    );
  }
}

class _AuthGate extends StatefulWidget {
  const _AuthGate();
  @override State<_AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<_AuthGate> {
  bool showRegister = false;

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<AuthBloc, AuthState>(
      builder: (context, state) {
        switch (state.status) {
          case AuthStatus.initial:
          case AuthStatus.checkingSession:
          case AuthStatus.authenticating:
            return Scaffold(
              body: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 72,
                      height: 72,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [AppTheme.primaryColor, AppTheme.accentColor],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [
                          BoxShadow(
                            color: AppTheme.primaryColor.withValues(alpha: 0.3),
                            blurRadius: 18,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      child: const Icon(Icons.chat_bubble_rounded, color: Colors.white, size: 36),
                    ),
                    const SizedBox(height: 24),
                    const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(strokeWidth: 2.5),
                    ),
                  ],
                ),
              ),
            );
          case AuthStatus.authenticated:
            return const DashboardPage();
          case AuthStatus.unauthenticated:
          case AuthStatus.failure:
            return AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              transitionBuilder: (child, animation) {
                return FadeTransition(
                  opacity: animation,
                  child: SlideTransition(
                    position: Tween<Offset>(
                      begin: const Offset(0.04, 0),
                      end: Offset.zero,
                    ).animate(animation),
                    child: child,
                  ),
                );
              },
              child: showRegister
                  ? RegisterPage(
                      key: const ValueKey('register'),
                      onLogin: () => setState(() => showRegister = false),
                    )
                  : LoginPage(
                      key: const ValueKey('login'),
                      onRegister: () => setState(() => showRegister = true),
                    ),
            );
        }
      },
    );
  }
}
