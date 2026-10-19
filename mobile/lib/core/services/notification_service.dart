import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Service managing system/push-like notifications for incoming messages.
class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  static const MethodChannel _nativeChannel =
      MethodChannel('com.dgs.chatspace/notifications');

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

      final launchDetails =
          await _notificationsPlugin.getNotificationAppLaunchDetails();
      if (launchDetails?.didNotificationLaunchApp ?? false) {
        final payload = launchDetails?.notificationResponse?.payload;
        if (payload != null && payload.isNotEmpty) {
          Future.delayed(const Duration(milliseconds: 600), () {
            onNotificationTapped?.call(payload);
          });
        }
      }

      if (!kIsWeb && Platform.isAndroid) {
        final androidPlugin =
            _notificationsPlugin.resolvePlatformSpecificImplementation<
                AndroidFlutterLocalNotificationsPlugin>();
        const androidChannel = AndroidNotificationChannel(
          _channelId,
          _channelName,
          description: _channelDescription,
          importance: Importance.max,
          playSound: true,
          enableVibration: true,
        );
        await androidPlugin?.createNotificationChannel(androidChannel);
      }

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

  final Map<String, List<String>> _senderMessages = {};
  final Map<String, String> _senderNames = {};

  /// Deduplication: track recent unique message IDs shown so that if both the socket
  /// and the FCM push arrive for the exact same message, it is only displayed once.
  /// Genuine identical messages (e.g. 5 consecutive "hi"s) have different IDs and are kept!
  final Set<String> _recentMessageIds = {};

  /// Set this to the currently open chat user's ID so that incoming notifications
  /// from that user are suppressed while the conversation is visible on screen.
  String? openChatUserId;

  String _formatPreview(String messageText, String? mediaType) {
    String text = messageText.trim();
    if (text.isEmpty && mediaType != null) {
      if (mediaType == 'image') {
        text = '📷 Photo';
      } else if (mediaType == 'video') {
        text = '🎥 Video';
      } else {
        text = '📁 Attachment';
      }
    } else if (mediaType != null && mediaType.isNotEmpty) {
      if (mediaType == 'image') {
        text = '📷 $text';
      } else if (mediaType == 'video') {
        text = '🎥 $text';
      }
    }
    return text.isEmpty ? 'New message' : text;
  }

  /// Display a WhatsApp-like multi-line system notification for incoming messages.
  Future<void> showMessageNotification({
    required String senderId,
    required String senderName,
    required String messageText,
    String? messageId,
    String? mediaType,
    List<String>? historicalLines,
  }) async {
    try {
      if (!_initialized) {
        await initialize();
      }

      // If the user is actively looking at this sender's chat, don't show a
      // heads-up banner — it would be intrusive and redundant.
      if (openChatUserId != null && openChatUserId == senderId) return;

      // Deduplication by messageId: if this exact message was already processed
      // (e.g. socket arrived first, or FCM arrived first), do not display it again.
      if (messageId != null && messageId.isNotEmpty) {
        if (_recentMessageIds.contains(messageId)) {
          return;
        }
        _recentMessageIds.add(messageId);
        if (_recentMessageIds.length > 200) {
          _recentMessageIds.remove(_recentMessageIds.first);
        }
      }

      _senderNames[senderId] = senderName;

      final preview = _formatPreview(messageText, mediaType);

      final messages = _senderMessages.putIfAbsent(senderId, () => []);

      if (historicalLines != null && historicalLines.isNotEmpty) {
        messages
          ..clear()
          ..addAll(historicalLines);
      } else {
        messages.add(preview);
      }

      if (messages.length > 7) {
        messages.removeRange(0, messages.length - 7);
      }

      final count = messages.length;
      final title = count > 1 ? '$senderName ($count messages)' : senderName;
      final bodyText = count > 1 ? messages.join('\n') : messages.last;

      final StyleInformation styleInformation = count > 1
          ? InboxStyleInformation(
              messages,
              contentTitle: title,
              summaryText: '$count new messages',
            )
          : BigTextStyleInformation(
              bodyText,
              contentTitle: senderName,
              summaryText: 'ChatSpace',
            );

      final androidDetails = AndroidNotificationDetails(
        _channelId,
        _channelName,
        channelDescription: _channelDescription,
        importance: Importance.max,
        priority: Priority.high,
        playSound: true,
        enableVibration: true,
        category: AndroidNotificationCategory.message,
        tag: senderId,
        number: count,
        styleInformation: styleInformation,
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

      // On Android, use id = 0 with tag = senderId so that this local notification
      // and FCM background notifications (which FCM always posts with tag = senderId, id = 0)
      // share the exact same Android notification slot.
      // This guarantees that incoming FCM messages replace the socket notification
      // (and vice-versa) instead of creating duplicate notifications in the shade.
      // Different senders are differentiated by tag = senderId.
      final notifId = (!kIsWeb && Platform.isAndroid) ? 0 : (senderId.hashCode & 0x7FFFFFFF);

      await _notificationsPlugin.show(
        id: notifId,
        title: title,
        body: bodyText,
        notificationDetails: details,
        payload: senderId,
      );
    } catch (e) {
      debugPrint('Failed to show message notification: $e');
    }
  }

  /// Dismisses all notifications originating from a specific sender
  /// (both local notifications and background Firebase notifications)
  Future<void> cancelSenderNotification(String senderId) async {
    if (senderId.isEmpty) return;
    _senderMessages.remove(senderId);
    _senderNames.remove(senderId);
    final hashId = (senderId.hashCode & 0x7FFFFFFF);
    try {
      // Cancel id 0 with tag = senderId (matches FCM and local Android notifications)
      await _notificationsPlugin.cancel(id: 0, tag: senderId);
    } catch (_) {}
    try {
      // Also cancel legacy hashId if previously posted
      await _notificationsPlugin.cancel(id: hashId, tag: senderId);
    } catch (_) {}
    try {
      await _notificationsPlugin.cancel(id: hashId);
    } catch (_) {}
    try {
      if (!kIsWeb && Platform.isAndroid) {
        await _nativeChannel.invokeMethod('cancelNotification', {
          'tag': senderId,
          'id': 0,
        });
        await _nativeChannel.invokeMethod('cancelNotification', {
          'tag': senderId,
          'id': hashId,
        });
      }
    } catch (_) {}
  }

  /// Dismisses all notifications currently showing for this app
  Future<void> cancelAllNotifications() async {
    _senderMessages.clear();
    _senderNames.clear();
    _recentMessageIds.clear();
    try {
      await _notificationsPlugin.cancelAll();
    } catch (_) {}
    try {
      if (!kIsWeb && Platform.isAndroid) {
        await _nativeChannel.invokeMethod('cancelAll');
      }
    } catch (_) {}
  }
}
