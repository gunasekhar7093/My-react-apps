import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../../data/models/message_model.dart';
import '../../data/models/user_model.dart';

/// Local offline persistence service for ChatSpace.
/// Caches user contacts and conversation messages on-device
/// so they can be viewed when mobile data or Wi-Fi is turned off.
class LocalStorageService {
  static final LocalStorageService _instance = LocalStorageService._internal();
  factory LocalStorageService() => _instance;
  LocalStorageService._internal();

  Directory? _cacheDir;

  Future<Directory> _getCacheDirectory() async {
    if (_cacheDir != null && await _cacheDir!.exists()) {
      return _cacheDir!;
    }
    final appDir = await getApplicationDocumentsDirectory();
    final dir = Directory('${appDir.path}/chatspace_offline_cache');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    _cacheDir = dir;
    return dir;
  }

  String _conversationKey(String u1, String u2) {
    final list = [u1, u2]..sort();
    return '${list[0]}_${list[1]}';
  }

  // ── User Contacts / Dashboard Cache ─────────────────────────────────────

  Future<File> _getUsersFile(String currentUserId) async {
    final dir = await _getCacheDirectory();
    return File('${dir.path}/users_$currentUserId.json');
  }

  Future<void> saveUsers(String currentUserId, List<UserModel> users) async {
    try {
      if (currentUserId.isEmpty) return;
      final file = await _getUsersFile(currentUserId);
      final jsonList = users.map((u) => u.toJson()).toList();
      await file.writeAsString(jsonEncode(jsonList), flush: true);
    } catch (e) {
      // Ignore cache write errors
    }
  }

  Future<List<UserModel>> getUsers(String currentUserId) async {
    try {
      if (currentUserId.isEmpty) return const [];
      final file = await _getUsersFile(currentUserId);
      if (!await file.exists()) return const [];
      final content = await file.readAsString();
      if (content.trim().isEmpty) return const [];
      final dynamic decoded = jsonDecode(content);
      if (decoded is! List) return const [];
      return decoded
          .whereType<Map>()
          .map((item) => UserModel.fromJson(Map<String, dynamic>.from(item)))
          .toList();
    } catch (_) {
      return const [];
    }
  }

  Future<void> zeroUnreadCount(String currentUserId, String partnerId) async {
    try {
      if (currentUserId.isEmpty || partnerId.isEmpty) return;
      final users = await getUsers(currentUserId);
      bool changed = false;
      final updated = users.map((u) {
        if (u.id == partnerId && u.unreadCount > 0) {
          changed = true;
          return u.copyWith(unreadCount: 0);
        }
        return u;
      }).toList();
      if (changed) {
        await saveUsers(currentUserId, updated);
      }
    } catch (_) {}
  }

  // ── Conversation Messages Cache ──────────────────────────────────────────

  Future<File> _getMessagesFile(String u1, String u2) async {
    final dir = await _getCacheDirectory();
    final key = _conversationKey(u1, u2);
    return File('${dir.path}/messages_$key.json');
  }

  Future<List<MessageModel>> getMessages(String userId, String otherUserId) async {
    try {
      final file = await _getMessagesFile(userId, otherUserId);
      if (!await file.exists()) return const [];
      final content = await file.readAsString();
      if (content.trim().isEmpty) return const [];
      final dynamic decoded = jsonDecode(content);
      if (decoded is! List) return const [];
      final list = decoded
          .whereType<Map>()
          .map((item) => MessageModel.fromJson(Map<String, dynamic>.from(item)))
          .toList();
      list.sort((a, b) => a.createdAt.compareTo(b.createdAt));
      return list;
    } catch (_) {
      return const [];
    }
  }

  /// Synchronizes server-fetched messages with the local offline cache.
  /// Handles additions, updates/status changes, AND server-side deletions/unsends.
  Future<void> syncMessages({
    required String userId,
    required String otherUserId,
    required List<MessageModel> fetchedMessages,
    required bool hasMore,
    String? before,
  }) async {
    try {
      final existing = await getMessages(userId, otherUserId);

      // Separate existing messages into local unconfirmed pending (outbox) and confirmed messages
      final pendingMessages = <MessageModel>[];
      final confirmedExisting = <MessageModel>[];

      final fetchedIds = fetchedMessages.map((m) => m.id).toSet();
      final fetchedClientTempIds = fetchedMessages
          .where((m) => m.clientTempId != null && m.clientTempId!.isNotEmpty)
          .map((m) => m.clientTempId!)
          .toSet();

      for (final m in existing) {
        if (m.isPending || m.id.startsWith('temp_')) {
          // If this pending message has now been confirmed by server, don't keep as pending
          final isConfirmed = fetchedIds.contains(m.id) ||
              (m.clientTempId != null && fetchedClientTempIds.contains(m.clientTempId));
          if (!isConfirmed) {
            pendingMessages.add(m);
          }
        } else {
          confirmedExisting.add(m);
        }
      }

      final Map<String, MessageModel> resultMap = {};
      final sortedFetched = List<MessageModel>.from(fetchedMessages)
        ..sort((a, b) => a.createdAt.compareTo(b.createdAt));

      if (before == null) {
        // Initial fetch / latest messages window
        if (!hasMore || sortedFetched.isEmpty) {
          // The server returned the full conversation or conversation is empty.
          // ALL confirmed messages that are not in fetchedMessages have been deleted!
          for (final m in sortedFetched) {
            resultMap[m.id] = m;
          }
        } else {
          // hasMore == true: fetchedMessages contains the newest messages down to oldestFetchedTime
          final oldestFetchedTime = sortedFetched.first.createdAt;
          // Keep confirmed older messages that are before the fetched window
          for (final m in confirmedExisting) {
            if (m.createdAt.compareTo(oldestFetchedTime) < 0) {
              resultMap[m.id] = m;
            }
          }
          // In the window [oldestFetchedTime, now], only fetchedMessages exist on server!
          for (final m in sortedFetched) {
            resultMap[m.id] = m;
          }
        }
      } else {
        // Pagination window: messages before `before`
        if (sortedFetched.isEmpty) {
          if (!hasMore) {
            // No older messages exist. Any message older than `before` was deleted.
            for (final m in confirmedExisting) {
              if (m.createdAt.compareTo(before) >= 0) {
                resultMap[m.id] = m;
              }
            }
          } else {
            for (final m in confirmedExisting) {
              resultMap[m.id] = m;
            }
          }
        } else {
          final oldestFetchedTime = sortedFetched.first.createdAt;
          for (final m in confirmedExisting) {
            if (m.createdAt.compareTo(before) >= 0) {
              // Newer messages outside this page: keep
              resultMap[m.id] = m;
            } else if (m.createdAt.compareTo(oldestFetchedTime) < 0) {
              // Older messages before this page: keep only if server has more older
              if (hasMore) {
                resultMap[m.id] = m;
              }
            }
            // Confirmed messages in [oldestFetchedTime, before] that aren't in fetchedMessages
            // are NOT kept, because they were deleted on server!
          }
          for (final m in sortedFetched) {
            resultMap[m.id] = m;
          }
        }
      }

      // Re-add any local unconfirmed pending messages
      for (final m in pendingMessages) {
        resultMap[m.id] = m;
      }

      final finalMessages = resultMap.values.toList()
        ..sort((a, b) => a.createdAt.compareTo(b.createdAt));

      final file = await _getMessagesFile(userId, otherUserId);
      final jsonList = finalMessages.map((m) => m.toJson()).toList();
      await file.writeAsString(jsonEncode(jsonList), flush: true);
    } catch (_) {}
  }

  Future<void> saveMessages(String userId, String otherUserId, List<MessageModel> newMessages) async {
    try {
      final existing = await getMessages(userId, otherUserId);
      final map = <String, MessageModel>{};
      for (final m in existing) {
        map[m.id] = m;
      }
      for (final m in newMessages) {
        map[m.id] = m;
      }
      final merged = map.values.toList()
        ..sort((a, b) => a.createdAt.compareTo(b.createdAt));

      final file = await _getMessagesFile(userId, otherUserId);
      final jsonList = merged.map((m) => m.toJson()).toList();
      await file.writeAsString(jsonEncode(jsonList), flush: true);
    } catch (_) {}
  }

  Future<void> appendSingleMessage(String userId, String otherUserId, MessageModel message) async {
    await saveMessages(userId, otherUserId, [message]);
  }

  Future<void> deleteMessage(String userId, String otherUserId, String messageId) async {
    try {
      await removePendingMessage(messageId);
      final existing = await getMessages(userId, otherUserId);
      final filtered = existing
          .where((m) => m.id != messageId && m.clientTempId != messageId)
          .toList();
      final file = await _getMessagesFile(userId, otherUserId);
      final jsonList = filtered.map((m) => m.toJson()).toList();
      await file.writeAsString(jsonEncode(jsonList), flush: true);
    } catch (_) {}
  }

  /// Deletes a message from all local caches (specific conversation or scans all conversations)
  Future<void> deleteMessageEverywhere(String messageId, {String? userId, String? otherUserId}) async {
    try {
      await removePendingMessage(messageId);

      if (userId != null && otherUserId != null && userId.isNotEmpty && otherUserId.isNotEmpty) {
        await deleteMessage(userId, otherUserId, messageId);
      }

      // Also ensure it is removed across all conversation cache files if present
      final dir = await _getCacheDirectory();
      if (!await dir.exists()) return;
      final files = dir.listSync().whereType<File>();
      for (final file in files) {
        final filename = file.uri.pathSegments.last;
        if (filename.startsWith('messages_') && filename.endsWith('.json')) {
          try {
            final content = await file.readAsString();
            if (content.contains(messageId)) {
              final dynamic decoded = jsonDecode(content);
              if (decoded is List) {
                final filtered = decoded.where((item) {
                  if (item is Map) {
                    final id = item['id']?.toString();
                    final clientTempId = item['clientTempId']?.toString();
                    return id != messageId && clientTempId != messageId;
                  }
                  return true;
                }).toList();
                await file.writeAsString(jsonEncode(filtered), flush: true);
              }
            }
          } catch (_) {}
        }
      }
    } catch (_) {}
  }

  Future<void> markMessagesAsRead(String userId, String otherUserId, {required String readAt}) async {
    try {
      final existing = await getMessages(userId, otherUserId);
      bool changed = false;
      final updated = existing.map((m) {
        if (m.senderId == otherUserId && (m.readAt == null || m.readAt!.isEmpty)) {
          changed = true;
          return MessageModel(
            id: m.id,
            senderId: m.senderId,
            receiverId: m.receiverId,
            text: m.text,
            createdAt: m.createdAt,
            deliveredAt: m.deliveredAt ?? readAt,
            readAt: readAt,
            mediaUrl: m.mediaUrl,
            mediaType: m.mediaType,
            mediaName: m.mediaName,
            mediaSize: m.mediaSize,
            senderName: m.senderName,
          );
        }
        return m;
      }).toList();

      if (changed) {
        final file = await _getMessagesFile(userId, otherUserId);
        final jsonList = updated.map((m) => m.toJson()).toList();
        await file.writeAsString(jsonEncode(jsonList), flush: true);
      }
    } catch (_) {}
  }

  Future<void> markMessagesAsDelivered(String userId, String otherUserId, List<String> messageIds, {required String deliveredAt}) async {
    try {
      if (messageIds.isEmpty) return;
      final idSet = messageIds.toSet();
      final existing = await getMessages(userId, otherUserId);
      bool changed = false;
      final updated = existing.map((m) {
        if (idSet.contains(m.id) && (m.deliveredAt == null || m.deliveredAt!.isEmpty)) {
          changed = true;
          return MessageModel(
            id: m.id,
            senderId: m.senderId,
            receiverId: m.receiverId,
            text: m.text,
            createdAt: m.createdAt,
            deliveredAt: deliveredAt,
            readAt: m.readAt,
            mediaUrl: m.mediaUrl,
            mediaType: m.mediaType,
            mediaName: m.mediaName,
            mediaSize: m.mediaSize,
            senderName: m.senderName,
          );
        }
        return m;
      }).toList();

      if (changed) {
        final file = await _getMessagesFile(userId, otherUserId);
        final jsonList = updated.map((m) => m.toJson()).toList();
        await file.writeAsString(jsonEncode(jsonList), flush: true);
      }
    } catch (_) {}
  }

  // ── Offline Pending Outbox Queue ──────────────────────────────────────────

  // In-flight sending tracker to prevent duplicate concurrent socket sends
  static final Set<String> _inFlightMessageIds = {};

  bool isMessageInFlight(String id) => _inFlightMessageIds.contains(id);
  void markMessageInFlight(String id) => _inFlightMessageIds.add(id);
  void clearMessageInFlight(String id) => _inFlightMessageIds.remove(id);

  Future<File> _getPendingQueueFile() async {
    final dir = await _getCacheDirectory();
    return File('${dir.path}/pending_outbox_queue.json');
  }

  Future<List<MessageModel>> getPendingMessages({String? userId, String? otherUserId}) async {
    try {
      final file = await _getPendingQueueFile();
      if (!await file.exists()) return const [];
      final content = await file.readAsString();
      if (content.trim().isEmpty) return const [];
      final dynamic decoded = jsonDecode(content);
      if (decoded is! List) return const [];
      final list = decoded
          .whereType<Map>()
          .map((item) => MessageModel.fromJson(Map<String, dynamic>.from(item)))
          .toList();

      List<MessageModel> filtered = list;
      if (userId != null && otherUserId != null) {
        filtered = list
            .where((m) =>
                (m.senderId == userId && m.receiverId == otherUserId) ||
                (m.senderId == otherUserId && m.receiverId == userId))
            .toList();
      }
      filtered.sort((a, b) => a.createdAt.compareTo(b.createdAt));
      return filtered;
    } catch (_) {
      return const [];
    }
  }

  Future<void> savePendingMessage(MessageModel message) async {
    try {
      final existing = await getPendingMessages();
      final map = <String, MessageModel>{for (final m in existing) m.id: m};
      map[message.id] = message;
      final sortedList = map.values.toList()
        ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
      final file = await _getPendingQueueFile();
      final jsonList = sortedList.map((m) => m.toJson()).toList();
      await file.writeAsString(jsonEncode(jsonList), flush: true);
    } catch (_) {}
  }

  Future<void> removePendingMessage(String tempId) async {
    try {
      final existing = await getPendingMessages();
      final filtered = existing
          .where((m) => m.id != tempId && m.clientTempId != tempId)
          .toList()
        ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
      final file = await _getPendingQueueFile();
      final jsonList = filtered.map((m) => m.toJson()).toList();
      await file.writeAsString(jsonEncode(jsonList), flush: true);
    } catch (_) {}
  }

  Future<void> replacePendingMessage(
    String userId,
    String otherUserId,
    String tempId,
    MessageModel confirmedMessage,
  ) async {
    try {
      // 1. Remove from pending queue
      await removePendingMessage(tempId);

      // 2. Replace in conversation messages cache
      final existing = await getMessages(userId, otherUserId);
      final replaced = existing.map((m) {
        if (m.id == tempId || (m.clientTempId != null && m.clientTempId == tempId)) {
          return confirmedMessage;
        }
        return m;
      }).toList();

      // Ensure confirmedMessage exists in the list if tempId was not found
      if (!replaced.any((m) => m.id == confirmedMessage.id)) {
        replaced.add(confirmedMessage);
      }
      replaced.sort((a, b) => a.createdAt.compareTo(b.createdAt));

      final file = await _getMessagesFile(userId, otherUserId);
      final jsonList = replaced.map((m) => m.toJson()).toList();
      await file.writeAsString(jsonEncode(jsonList), flush: true);
    } catch (_) {}
  }

  // ── Pending Read Receipts Queue ──────────────────────────────────────────

  Future<File> _getPendingReadReceiptsFile() async {
    final dir = await _getCacheDirectory();
    return File('${dir.path}/pending_read_receipts.json');
  }

  Future<Set<String>> getPendingReadReceipts() async {
    try {
      final file = await _getPendingReadReceiptsFile();
      if (!await file.exists()) return <String>{};
      final content = await file.readAsString();
      if (content.trim().isEmpty) return <String>{};
      final dynamic decoded = jsonDecode(content);
      if (decoded is List) {
        return decoded.map((e) => e.toString()).toSet();
      }
    } catch (_) {}
    return <String>{};
  }

  Future<void> addPendingReadReceipt(String partnerId) async {
    try {
      if (partnerId.isEmpty) return;
      final existing = await getPendingReadReceipts();
      existing.add(partnerId);
      final file = await _getPendingReadReceiptsFile();
      await file.writeAsString(jsonEncode(existing.toList()), flush: true);
    } catch (_) {}
  }

  Future<void> removePendingReadReceipt(String partnerId) async {
    try {
      final existing = await getPendingReadReceipts();
      if (existing.remove(partnerId)) {
        final file = await _getPendingReadReceiptsFile();
        await file.writeAsString(jsonEncode(existing.toList()), flush: true);
      }
    } catch (_) {}
  }
}

