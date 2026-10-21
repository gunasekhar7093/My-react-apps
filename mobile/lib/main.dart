import 'dart:convert';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';

import 'firebase_options.dart';
import 'core/services/background_sync_service.dart';
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

/// Dedicated top-level background execution dispatcher for WorkManager.
/// Runs inside a headless Dart isolate managed by the OS when network connectivity returns.
@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((taskName, inputData) async {
    if (kDebugMode) {
      print('[WorkManager] OS triggered headless task: $taskName');
    }
    return await BackgroundSyncService.executeSync();
  });
}

/// WhatsApp-style fully autonomous background message handler:
/// 1. Intercepts silent data-only FCM push when app is closed / killed / backgrounded.
/// 2. Bypasses platform channels by using pre-cached paths and cross-isolate safe SharedPreferences.
/// 3. Initializes local storage connection in the standalone Dart isolate.
/// 4. Parses and immediately writes incoming chat message into local cache (messages & contacts).
/// 5. Triggers local notification banner only after local cache write succeeds.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  try {
    WidgetsFlutterBinding.ensureInitialized();

    // 1. Secure cross-isolate session verification via SharedPreferences
    // (Checks chatspace_active_uid without exposing sensitive bearer API tokens in plaintext)
    String activeUid = '';
    try {
      final prefs = await SharedPreferences.getInstance();
      activeUid = prefs.getString(SecureStorageService.activeUidPrefKey) ?? '';
    } catch (e) {
      if (kDebugMode) print('[FCM] SharedPreferences activeUid check error: $e');
    }

    // Fallback: if activeUid wasn't cached yet, attempt to read user profile from SecureStorage
    if (activeUid.isEmpty) {
      try {
        final userStr = await SecureStorageService().getUser();
        if (userStr != null && userStr.isNotEmpty) {
          final dynamic decoded = jsonDecode(userStr);
          if (decoded is Map) {
            activeUid = decoded['id']?.toString() ?? decoded['_id']?.toString() ?? '';
          }
        }
      } catch (_) {}
    }

    if (activeUid.isEmpty) {
      if (kDebugMode) print('[FCM] Dropping background message: user is logged out (no activeUid)');
      return;
    }
    final currentUserId = activeUid;

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

    // Verify recipient: ensure the incoming message was actually addressed to this active user
    if (receiverId.isNotEmpty && receiverId != currentUserId) {
      if (kDebugMode) {
        print('[FCM] Dropping push: addressed to $receiverId but device user is $currentUserId');
      }
      return;
    }
    final senderName = data['senderName']?.toString() ?? data['title']?.toString() ?? 'User';
    final text = data['text']?.toString() ?? data['body']?.toString() ?? data['preview']?.toString() ?? '';
    final messageId = data['messageId']?.toString() ?? message.messageId ?? 'msg_${DateTime.now().millisecondsSinceEpoch}';
    final createdAt = data['createdAt']?.toString() ?? DateTime.now().toUtc().toIso8601String();
    final mediaUrl = data['mediaUrl']?.toString();
    final mediaType = data['mediaType']?.toString();
    final mediaName = data['mediaName']?.toString();
    final mediaSize = int.tryParse(data['mediaSize']?.toString() ?? '0');

    if (senderId.isEmpty && text.isEmpty && (mediaUrl == null || mediaUrl.isEmpty)) return;

    // 4. PREPARE & INITIALIZE DATABASE CONNECTION IN BACKGROUND ISOLATE
    final localStorage = LocalStorageService();
    // Explicit background initialization: connects to database files, handles isolates, avoids lock crashes
    await localStorage.initialize();

    // 5. WRITE TO LOCAL CACHE IMMEDIATELY (WhatsApp background sync engine)
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

    // 6. Parse historical lines for multi-message WhatsApp inbox-style grouping
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

    // 7. TRIGGER LOCAL BANNER ONLY AFTER LOCAL CACHE WRITE SUCCEEDS
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

  // A. Pre-Cache Storage Path and Session State on Main App Launch
  // (Bypasses path_provider & SecureStorage platform channel limitations in background isolates)
  try {
    final appDir = await getApplicationDocumentsDirectory();
    final cachePath = '${appDir.path}/chatspace_offline_cache';
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(LocalStorageService.cacheDirPrefKey, cachePath);

    // Extract user ID from SecureStore and save as chatspace_active_uid in SharedPreferences
    final secureStorage = SecureStorageService();
    final userStr = await secureStorage.getUser();
    if (userStr != null && userStr.isNotEmpty) {
      try {
        final dynamic decoded = jsonDecode(userStr);
        if (decoded is Map) {
          final uid = decoded['id']?.toString() ?? decoded['_id']?.toString() ?? '';
          if (uid.isNotEmpty) {
            await prefs.setString(SecureStorageService.activeUidPrefKey, uid);
          }
        }
      } catch (_) {}
    }

    // Security hardening: ensure no sensitive network bearer tokens remain in plaintext SharedPreferences
    await prefs.remove('chatspace_token');
    await prefs.remove('chatspace_user');
  } catch (e) {
    if (kDebugMode) print('[Main] Pre-cache setup error: $e');
  }

  // Register top-level background handler with Firebase Messaging
  FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
  // Pre-initialize offline storage engine connection
  await LocalStorageService().initialize();
  // Pre-initialize local notifications for incoming message alerts
  await NotificationService().initialize();
  // Pre-initialize Firebase Cloud Messaging
  await FcmService().initialize();
  // Initialize Workmanager for OS-driven headless background synchronization
  await Workmanager().initialize(callbackDispatcher);
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
