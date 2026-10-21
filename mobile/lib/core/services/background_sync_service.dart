import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';

import '../constants/api_constants.dart';
import '../storage/secure_storage_service.dart';
import 'local_storage_service.dart';
import '../../data/models/message_model.dart';

/// OS-Driven Headless Background Execution Service.
/// Matches WhatsApp's background sync engine:
/// - Tells the OS (Android WorkManager) to wake up the app when internet connection returns.
/// - Executes inside a standalone Dart isolate without UI or Socket.IO overhead.
/// - Flushes offline messages, read receipts, and deletions via lightweight HTTP REST endpoints.
class BackgroundSyncService {
  static const String taskName = "syncOfflineDataTask";
  static const String uniqueWorkName = "com.chatspace.offline_sync_task";

  /// Registers/schedules a persistent background task with the OS.
  /// Configured with NetworkType.connected constraint so the OS monitors network
  /// and automatically triggers this worker even if the app was killed or device restarted.
  static Future<void> scheduleOfflineSync() async {
    try {
      await Workmanager().registerOneOffTask(
        uniqueWorkName,
        taskName,
        constraints: Constraints(
          networkType: NetworkType.connected,
        ),
        existingWorkPolicy: ExistingWorkPolicy.keep,
      );
      if (kDebugMode) {
        print('[WorkManager] Successfully registered offline sync task with NetworkType.connected');
      }
    } catch (e) {
      if (kDebugMode) {
        print('[WorkManager] Failed to register task: $e');
      }
    }
  }

  /// Headless execution loop that runs inside the standalone background isolate.
  static Future<bool> executeSync() async {
    try {
      WidgetsFlutterBinding.ensureInitialized();

      // 1. Verify session in headless isolate via SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      final activeUid = prefs.getString(SecureStorageService.activeUidPrefKey);
      if (activeUid == null || activeUid.trim().isEmpty) {
        if (kDebugMode) {
          print('[WorkManager] Dropping background sync: no active user logged in.');
        }
        return true;
      }

      // 2. Initialize LocalStorageService using pre-cached SharedPreferences path (avoids MissingPluginException)
      final localStorage = LocalStorageService();
      await localStorage.initialize();

      // Attempt to load token if secure storage is accessible in this isolate
      String? token;
      try {
        token = await SecureStorageService().getToken();
      } catch (_) {}

      final authHeaders = <String, String>{
        'Content-Type': 'application/json',
        'x-user-id': activeUid,
        if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
      };

      final client = http.Client();
      try {
        // 3. Process Pending Messages Outbox (/api/messages/sync-offline)
        final pendingMessages = await localStorage.getPendingMessages(userId: activeUid);
        for (final pending in pendingMessages) {
          try {
            final uri = Uri.parse('${ApiConstants.baseUrl}/api/messages/sync-offline');
            final body = jsonEncode({
              'clientTempId': pending.clientTempId ?? pending.id,
              'receiverId': pending.receiverId,
              'text': pending.text,
              'createdAt': pending.createdAt,
              'mediaUrl': pending.mediaUrl,
              'mediaType': pending.mediaType,
              'mediaName': pending.mediaName,
              'mediaSize': pending.mediaSize,
              'replyTo': pending.replyTo?.toJson(),
            });

            final response = await client.post(
              uri,
              headers: authHeaders,
              body: body,
            ).timeout(const Duration(seconds: 15));

            if (response.statusCode == 200 || response.statusCode == 201) {
              final dynamic resJson = jsonDecode(response.body);
              if (resJson is Map && resJson['message'] is Map) {
                final confirmedMessage = MessageModel.fromJson(
                  Map<String, dynamic>.from(resJson['message'] as Map),
                );
                await localStorage.replacePendingMessage(
                  pending.senderId,
                  pending.receiverId,
                  pending.id,
                  confirmedMessage,
                );
                if (kDebugMode) {
                  print('[WorkManager] Synced offline message ${pending.id} -> ${confirmedMessage.id}');
                }
              }
            } else {
              if (kDebugMode) {
                print('[WorkManager] Failed syncing message ${pending.id}: HTTP ${response.statusCode}');
              }
            }
          } catch (e) {
            if (kDebugMode) {
              print('[WorkManager] Error sending pending message ${pending.id}: $e');
            }
          }
        }

        // 4. Process Pending Read Receipts (/api/messages/:userId/:otherUserId/read)
        final pendingReceipts = await localStorage.getPendingReadReceipts();
        for (final partnerId in pendingReceipts) {
          try {
            final uri = Uri.parse('${ApiConstants.baseUrl}/api/messages/$activeUid/$partnerId/read');
            final response = await client.post(
              uri,
              headers: authHeaders,
            ).timeout(const Duration(seconds: 10));

            if (response.statusCode >= 200 && response.statusCode < 300) {
              await localStorage.removePendingReadReceipt(partnerId);
              if (kDebugMode) {
                print('[WorkManager] Synced read receipt for partner $partnerId');
              }
            }
          } catch (e) {
            if (kDebugMode) {
              print('[WorkManager] Error syncing read receipt for $partnerId: $e');
            }
          }
        }

        // 5. Process Pending Deletions (/api/messages/:messageId)
        final pendingDeletions = await localStorage.getPendingDeletions();
        for (final messageId in pendingDeletions) {
          try {
            final uri = Uri.parse('${ApiConstants.baseUrl}/api/messages/$messageId');
            final response = await client.delete(
              uri,
              headers: authHeaders,
            ).timeout(const Duration(seconds: 10));

            if (response.statusCode == 200 || response.statusCode == 204 || response.statusCode == 404) {
              await localStorage.removePendingDeletion(messageId);
              if (kDebugMode) {
                print('[WorkManager] Synced message deletion for $messageId');
              }
            }
          } catch (e) {
            if (kDebugMode) {
              print('[WorkManager] Error syncing deletion for $messageId: $e');
            }
          }
        }
      } finally {
        client.close();
      }

      return true;
    } catch (e) {
      if (kDebugMode) {
        print('[WorkManager] Top-level failure during executeSync: $e');
      }
      return false;
    }
  }
}
