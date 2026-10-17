import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Service managing system/push-like notifications for incoming messages.
class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FlutterLocalNotificationsPlugin _notificationsPlugin =
      FlutterLocalNotificationsPlugin();

  bool _initialized = false;
  void Function(String userId)? onNotificationTapped;

  static const String _channelId = 'chatspace_messages_channel';
  static const String _channelName = 'Chat Messages';
  static const String _channelDescription =
      'Notifications for received messages from users in ChatSpace';

  /// Initialize notification settings and request permissions if needed.
  Future<void> initialize({void Function(String userId)? onSelectUser}) async {
    if (_initialized) {
      if (onSelectUser != null) onNotificationTapped = onSelectUser;
      return;
    }
    onNotificationTapped = onSelectUser;

    try {
      const androidSettings =
          AndroidInitializationSettings('@mipmap/ic_launcher');
      const darwinSettings = DarwinInitializationSettings(
        requestAlertPermission: true,
        requestBadgePermission: true,
        requestSoundPermission: true,
      );

      const initSettings = InitializationSettings(
        android: androidSettings,
        iOS: darwinSettings,
        macOS: darwinSettings,
      );

      await _notificationsPlugin.initialize(
        settings: initSettings,
        onDidReceiveNotificationResponse: (NotificationResponse response) {
          final payload = response.payload;
          if (payload != null && payload.isNotEmpty) {
            onNotificationTapped?.call(payload);
          }
        },
      );

      await requestPermissions();
      _initialized = true;
    } catch (e) {
      debugPrint('NotificationService init error: $e');
    }
  }

  /// Request permissions on Android 13+ and iOS.
  Future<void> requestPermissions() async {
    try {
      if (!kIsWeb && Platform.isAndroid) {
        final androidPlugin =
            _notificationsPlugin.resolvePlatformSpecificImplementation<
                AndroidFlutterLocalNotificationsPlugin>();
        await androidPlugin?.requestNotificationsPermission();
      } else if (!kIsWeb && (Platform.isIOS || Platform.isMacOS)) {
        final iosPlugin =
            _notificationsPlugin.resolvePlatformSpecificImplementation<
                IOSFlutterLocalNotificationsPlugin>();
        await iosPlugin?.requestPermissions(
          alert: true,
          badge: true,
          sound: true,
        );
      }
    } catch (e) {
      debugPrint('Notification permissions request error: $e');
    }
  }

  /// Display a WhatsApp-like heads-up system notification for an incoming message.
  Future<void> showMessageNotification({
    required String senderId,
    required String senderName,
    required String messageText,
    String? mediaType,
  }) async {
    try {
      if (!_initialized) {
        await initialize();
      }

      // Format preview like WhatsApp: if media, show icon indicator
      String bodyText = messageText.trim();
      if (bodyText.isEmpty && mediaType != null) {
        if (mediaType == 'image') {
          bodyText = '📷 Photo';
        } else if (mediaType == 'video') {
          bodyText = '🎥 Video';
        } else {
          bodyText = '📁 Attachment';
        }
      } else if (mediaType != null && mediaType.isNotEmpty) {
        if (mediaType == 'image') {
          bodyText = '📷 $bodyText';
        } else if (mediaType == 'video') {
          bodyText = '🎥 $bodyText';
        }
      }

      final androidDetails = AndroidNotificationDetails(
        _channelId,
        _channelName,
        channelDescription: _channelDescription,
        importance: Importance.max,
        priority: Priority.high,
        playSound: true,
        enableVibration: true,
        category: AndroidNotificationCategory.message,
        styleInformation: BigTextStyleInformation(
          bodyText,
          contentTitle: senderName,
          summaryText: 'ChatSpace',
        ),
      );

      const darwinDetails = DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      );

      final details = NotificationDetails(
        android: androidDetails,
        iOS: darwinDetails,
      );

      // Unique notification id based on senderId hash so different senders don't overwrite each other
      final notifId = (senderId.hashCode & 0x7FFFFFFF);

      await _notificationsPlugin.show(
        id: notifId,
        title: senderName,
        body: bodyText,
        notificationDetails: details,
        payload: senderId,
      );
    } catch (e) {
      debugPrint('Failed to show message notification: $e');
    }
  }
}
