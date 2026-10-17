import 'dart:async';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import '../constants/api_constants.dart';
import '../network/api_client.dart';
import 'notification_service.dart';

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  try {
    await Firebase.initializeApp();
  } catch (_) {}
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
      // 1. Initialize Firebase
      await Firebase.initializeApp();

      // 2. Register background handler
      FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

      final messaging = FirebaseMessaging.instance;

      // 3. Request permissions on Android 13+ and iOS
      await messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
        provisional: false,
      );

      // 4. Foreground message listener (when app is in foreground)
      FirebaseMessaging.onMessage.listen((RemoteMessage message) {
        final notification = message.notification;
        final senderId = message.data['senderId']?.toString() ?? '';
        final senderName = notification?.title ?? message.data['senderName']?.toString() ?? 'User';
        final body = notification?.body ?? '';

        if (senderId.isNotEmpty) {
          NotificationService().showMessageNotification(
            senderId: senderId,
            senderName: senderName,
            messageText: body,
          );
        }
      });

      // 5. When user taps notification while app was backgrounded
      FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
        final senderId = message.data['senderId']?.toString();
        if (senderId != null && senderId.isNotEmpty) {
          onMessageTapped?.call(senderId);
        }
      });

      // 6. When user opened app from terminated/closed state via notification tap
      final initialMessage = await messaging.getInitialMessage();
      if (initialMessage != null) {
        final senderId = initialMessage.data['senderId']?.toString();
        if (senderId != null && senderId.isNotEmpty) {
          Future.delayed(const Duration(milliseconds: 600), () {
            onMessageTapped?.call(senderId);
          });
        }
      }

      // 7. Token refresh listener
      // ignore: deprecated_member_use
      messaging.onTokenRefresh.listen((token) {
        syncTokenWithServer(token);
      });

      _initialized = true;
    } catch (e) {
      debugPrint('FCM initialize info: $e');
    }
  }

  /// Sends the device's FCM token to the server to store in user profile
  Future<void> registerDeviceToken() async {
    try {
      if (!_initialized) await initialize();
      // ignore: deprecated_member_use
      final token = await FirebaseMessaging.instance.getToken();
      if (token != null && token.isNotEmpty) {
        await syncTokenWithServer(token);
      }
    } catch (e) {
      debugPrint('FCM getToken notice: $e');
    }
  }

  Future<void> syncTokenWithServer(String token) async {
    try {
      await _apiClient.post(
        ApiConstants.fcmToken,
        body: {'token': token},
        authenticated: true,
      );
      debugPrint('FCM token registered with server.');
    } catch (e) {
      debugPrint('Could not sync FCM token with server: $e');
    }
  }
}
