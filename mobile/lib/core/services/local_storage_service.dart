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
      final existing = await getMessages(userId, otherUserId);
      final filtered = existing.where((m) => m.id != messageId).toList();
      final file = await _getMessagesFile(userId, otherUserId);
      final jsonList = filtered.map((m) => m.toJson()).toList();
      await file.writeAsString(jsonEncode(jsonList), flush: true);
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

      if (userId != null && otherUserId != null) {
        return list
            .where((m) =>
                (m.senderId == userId && m.receiverId == otherUserId) ||
                (m.senderId == otherUserId && m.receiverId == userId))
            .toList();
      }
      return list;
    } catch (_) {
      return const [];
    }
  }

  Future<void> savePendingMessage(MessageModel message) async {
    try {
      final existing = await getPendingMessages();
      final map = <String, MessageModel>{for (final m in existing) m.id: m};
      map[message.id] = message;
      final file = await _getPendingQueueFile();
      final jsonList = map.values.map((m) => m.toJson()).toList();
      await file.writeAsString(jsonEncode(jsonList), flush: true);
    } catch (_) {}
  }

  Future<void> removePendingMessage(String tempId) async {
    try {
      final existing = await getPendingMessages();
      final filtered = existing.where((m) => m.id != tempId).toList();
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
        if (m.id == tempId) {
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
}

