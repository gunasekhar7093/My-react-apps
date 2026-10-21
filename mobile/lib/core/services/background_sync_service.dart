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

  /// In-memory debouncer/throttler flag.
  /// Prevents redundant OS WorkManager task registrations and OS rate-limits
  /// when multiple offline messages or read receipts are queued rapidly.
  static bool _isSyncScheduled = false;

  /// Exposes whether a background sync task has already been scheduled in this session.
  static bool get isSyncScheduled => _isSyncScheduled;

  /// Resets the sync scheduling throttle state.
  /// Called when pending outbox data has been flushed or when network presence
  /// transitions back to a clean online state.
  static void resetSyncSchedule() {
    _isSyncScheduled = false;
    if (kDebugMode) {
      print('[WorkManager] Reset _isSyncScheduled to false');
    }
  }

  /// Registers/schedules a persistent background task with the OS.
  /// Configured with NetworkType.connected constraint so the OS monitors network
  /// and automatically triggers this worker even if the app was killed or device restarted.
  static Future<void> scheduleOfflineSync() async {
    // Skip duplicate registration if a task is already scheduled in this session
    if (_isSyncScheduled) {
      if (kDebugMode) {
        print('[WorkManager] Sync task already scheduled for current session, skipping duplicate registration.');
      }
      return;
    }

    try {
      await Workmanager().registerOneOffTask(
        uniqueWorkName,
        taskName,
        constraints: Constraints(
          networkType: NetworkType.connected,
        ),
        existingWorkPolicy: ExistingWorkPolicy.replace,
        initialDelay: Duration.zero,
        backoffPolicy: BackoffPolicy.exponential,
        backoffPolicyDelay: const Duration(seconds: 10),
      );
      _isSyncScheduled = true;
      if (kDebugMode) {
        print('[WorkManager] Successfully registered offline sync task with NetworkType.connected (ExistingWorkPolicy.replace)');
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

      // 1. Initialize LocalStorageService first
      final localStorage = LocalStorageService();
      await localStorage.initialize();

      // 2. Verify session in headless isolate via SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      String? activeUid = prefs.getString(SecureStorageService.activeUidPrefKey);

      // Fallback: If activeUid wasn't cached, resolve directly from the queued offline outbox messages
      if (activeUid == null || activeUid.trim().isEmpty) {
        final allPending = await localStorage.getPendingMessages();
        if (allPending.isNotEmpty) {
          activeUid = allPending.first.senderId;
          await prefs.setString(SecureStorageService.activeUidPrefKey, activeUid);
        }
      }

      if (activeUid == null || activeUid.trim().isEmpty) {
        if (kDebugMode) {
          print('[WorkManager] Dropping background sync: no active user logged in or pending outbox empty.');
        }
        return true;
      }

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

      bool allSucceeded = true;
      final client = http.Client();
      try {
        // 3. Process Pending Messages Outbox (/api/messages/sync-offline)
        final allPending = await localStorage.getPendingMessages();
        final pendingMessages = allPending.where((m) => m.senderId == activeUid).toList();

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

            // 60-second timeout safely absorbs free-tier Render server wakeups
            final response = await client.post(
              uri,
              headers: authHeaders,
              body: body,
            ).timeout(const Duration(seconds: 60));

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
              allSucceeded = false;
              if (kDebugMode) {
                print('[WorkManager] Failed syncing message ${pending.id}: HTTP ${response.statusCode}');
              }
            }
          } catch (e) {
            allSucceeded = false;
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
            ).timeout(const Duration(seconds: 15));

            if (response.statusCode >= 200 && response.statusCode < 300) {
              await localStorage.removePendingReadReceipt(partnerId);
              if (kDebugMode) {
                print('[WorkManager] Synced read receipt for partner $partnerId');
              }
            } else {
              allSucceeded = false;
            }
          } catch (e) {
            allSucceeded = false;
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
            ).timeout(const Duration(seconds: 15));

            if (response.statusCode == 200 || response.statusCode == 204 || response.statusCode == 404) {
              await localStorage.removePendingDeletion(messageId);
              if (kDebugMode) {
                print('[WorkManager] Synced message deletion for $messageId');
              }
            } else {
              allSucceeded = false;
            }
          } catch (e) {
            allSucceeded = false;
            if (kDebugMode) {
              print('[WorkManager] Error syncing deletion for $messageId: $e');
            }
          }
        }
      } finally {
        client.close();
      }

      if (allSucceeded) {
        resetSyncSchedule();
      }
      return allSucceeded;
    } catch (e) {
      if (kDebugMode) {
        print('[WorkManager] Top-level failure during executeSync: $e');
      }
      return false;
    }
  }
}
