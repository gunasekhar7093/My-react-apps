import 'dart:async';
import 'dart:convert';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import '../../firebase_options.dart';
import '../constants/api_constants.dart';
import '../network/api_client.dart';
import '../storage/secure_storage_service.dart';
import 'notification_service.dart';

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  try {
    // If the user has logged out, ignore all background messages
    final userToken = await SecureStorageService().getToken();
    if (userToken == null || userToken.isEmpty) {
      if (kDebugMode) print('[FCM] Dropping background notification: user is logged out');
      return;
    }

    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    // If Android didn't display the notification automatically (e.g. data-only payload),
    // display it manually via local notification service
    if (message.notification == null) {
      final senderId = message.data['senderId']?.toString() ?? '';
      final senderName = message.data['senderName']?.toString() ?? 'User';
      final text = message.data['text']?.toString() ?? message.data['preview']?.toString() ?? '';

      List<String>? historicalLines;
      final rawLines = message.data['unreadLines']?.toString();
      if (rawLines != null && rawLines.isNotEmpty) {
        try {
          final decoded = jsonDecode(rawLines);
          if (decoded is List) {
            historicalLines = decoded.map((e) => e.toString()).toList();
          }
        } catch (_) {}
      }

      if (senderId.isNotEmpty) {
        await NotificationService().showMessageNotification(
          senderId: senderId,
          senderName: senderName,
          messageText: text,
          historicalLines: historicalLines,
        );
      }
    }
  } catch (e) {
    if (kDebugMode) print('[FCM] background handler error: $e');
  }
}

/// Service managing Firebase Cloud Messaging for notifications when app is closed.
class FcmService {
  static final FcmService _instance = FcmService._internal();
  factory FcmService() => _instance;
  FcmService._internal();

  final ApiClient _apiClient = ApiClient();
  bool _initialized = false;
  void Function(String userId)? onMessageTapped;

  /// Initialize Firebase & Firebase Messaging
  Future<void> initialize({void Function(String userId)? onOpenChat}) async {
    if (onOpenChat != null) onMessageTapped = onOpenChat;
    if (_initialized) return;

    try {
      // 1. Initialize Firebase with platform-specific options
      try {
        await Firebase.initializeApp(
          options: DefaultFirebaseOptions.currentPlatform,
        );
      } catch (e) {
        // May already be initialized
        if (Firebase.apps.isEmpty) {
          await Firebase.initializeApp();
        }
      }

      // 2. Register background handler
      FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

      final messaging = FirebaseMessaging.instance;

      // 3. Foreground message listener (when app is in foreground)
      FirebaseMessaging.onMessage.listen((RemoteMessage message) async {
        final userToken = await SecureStorageService().getToken();
        if (userToken == null || userToken.isEmpty) return;

        final notification = message.notification;
        final senderId = message.data['senderId']?.toString() ?? '';
        final senderName = notification?.title ?? message.data['senderName']?.toString() ?? 'User';
        final body = notification?.body ?? message.data['text']?.toString() ?? '';

        List<String>? historicalLines;
        final rawLines = message.data['unreadLines']?.toString();
        if (rawLines != null && rawLines.isNotEmpty) {
          try {
            final decoded = jsonDecode(rawLines);
            if (decoded is List) {
              historicalLines = decoded.map((e) => e.toString()).toList();
            }
          } catch (_) {}
        }

        if (senderId.isNotEmpty) {
          NotificationService().showMessageNotification(
            senderId: senderId,
            senderName: senderName,
            messageText: body,
            historicalLines: historicalLines,
          );
        }
      });

      // 4. When user taps notification while app was backgrounded
      FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
        final senderId = message.data['senderId']?.toString();
        if (senderId != null && senderId.isNotEmpty) {
          NotificationService().cancelSenderNotification(senderId);
          onMessageTapped?.call(senderId);
        }
      });

      // 5. When user opened app from terminated/closed state via notification tap
      final initialMessage = await messaging.getInitialMessage();
      if (initialMessage != null) {
        final senderId = initialMessage.data['senderId']?.toString();
        if (senderId != null && senderId.isNotEmpty) {
          NotificationService().cancelSenderNotification(senderId);
          Future.delayed(const Duration(milliseconds: 600), () {
            onMessageTapped?.call(senderId);
          });
        }
      }

      // 6. Token refresh listener
      // ignore: deprecated_member_use
      messaging.onTokenRefresh.listen((token) {
        syncTokenWithServer(token);
      });

      _initialized = true;
      if (kDebugMode) print('[FCM] Initialized successfully');
    } catch (e) {
      if (kDebugMode) print('[FCM] initialize error: $e');
    }
  }

  /// Sends the device's FCM token to the server to store in user profile
  Future<void> registerDeviceToken({int retryCount = 0}) async {
    try {
      if (!_initialized) await initialize();

      final messaging = FirebaseMessaging.instance;

      // Request notification permissions
      try {
        await messaging.requestPermission(
          alert: true,
          badge: true,
          sound: true,
          provisional: false,
        );
      } catch (_) {}

      // ignore: deprecated_member_use
      final token = await messaging.getToken();
      if (kDebugMode) print('[FCM] Retrieved device token: $token');

      if (token != null && token.isNotEmpty) {
        await syncTokenWithServer(token);
      } else if (retryCount < 3) {
        if (kDebugMode) print('[FCM] Token is null, scheduling retry ${retryCount + 1} in 4s...');
        Future.delayed(const Duration(seconds: 4), () {
          registerDeviceToken(retryCount: retryCount + 1);
        });
      }
    } catch (e) {
      if (kDebugMode) print('[FCM] registerDeviceToken error: $e');
      if (retryCount < 3) {
        Future.delayed(const Duration(seconds: 5), () {
          registerDeviceToken(retryCount: retryCount + 1);
        });
      }
    }
  }

  Future<void> syncTokenWithServer(String token) async {
    try {
      if (kDebugMode) print('[FCM] Syncing device token with server...');
      final response = await _apiClient.post(
        ApiConstants.fcmToken,
        body: {'token': token},
        authenticated: true,
      );
      if (kDebugMode) print('[FCM] Server token registration success: $response');
    } catch (e) {
      if (kDebugMode) print('[FCM] Could not sync FCM token with server: $e');
    }
  }

  /// Unregisters and deletes the device's FCM token upon logout.
  /// Prevents any notifications from arriving when logged out.
  Future<void> unregisterDeviceToken() async {
    try {
      // 1. Unregister token on backend
      try {
        await _apiClient.delete(
          ApiConstants.fcmToken,
          authenticated: true,
        );
        if (kDebugMode) print('[FCM] Server token unregistration sent');
      } catch (e) {
        if (kDebugMode) print('[FCM] Failed to unregister token from server: $e');
      }

      // 2. Invalidate and delete local FCM token
      try {
        // ignore: deprecated_member_use
        await FirebaseMessaging.instance.deleteToken();
        if (kDebugMode) print('[FCM] Local token deleted successfully');
      } catch (e) {
        if (kDebugMode) print('[FCM] Failed to delete local token: $e');
      }
    } catch (e) {
      if (kDebugMode) print('[FCM] unregisterDeviceToken error: $e');
    }
  }
}
