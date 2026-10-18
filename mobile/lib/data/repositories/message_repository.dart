import '../../core/network/api_client.dart';
import '../../core/services/local_storage_service.dart';
import '../models/message_model.dart';

class MessagesResult {
  final List<MessageModel> messages;
  final bool hasMore;

  const MessagesResult({
    required this.messages,
    this.hasMore = false,
  });
}

class MessageRepository {
  final ApiClient apiClient;
  final LocalStorageService localStorage;

  MessageRepository({
    ApiClient? apiClient,
    LocalStorageService? localStorage,
  })  : apiClient = apiClient ?? ApiClient(),
        localStorage = localStorage ?? LocalStorageService();

  Future<List<MessageModel>> getCachedMessages({
    required String userId,
    required String otherUserId,
  }) async {
    return localStorage.getMessages(userId, otherUserId);
  }

  Future<MessagesResult> getMessages({
    required String userId,
    required String otherUserId,
    String? before,
    int limit = 40,
  }) async {
    try {
      final query = before != null && before.isNotEmpty
          ? '?limit=$limit&before=${Uri.encodeComponent(before)}'
          : '?limit=$limit';

      final data = await apiClient.get(
        '/api/messages/$userId/$otherUserId$query',
        authenticated: true,
      );
      final rawList = data['messages'];
      final hasMore = data['hasMore'] == true;
      if (rawList is! List) {
        return MessagesResult(messages: const [], hasMore: hasMore);
      }
      final fetched = rawList
          .whereType<Map>()
          .map((m) => MessageModel.fromJson(Map<String, dynamic>.from(m)))
          .toList();

      // Synchronize cache with server data:
      // Adds new messages, updates changed messages, and prunes deleted messages!
      await localStorage.syncMessages(
        userId: userId,
        otherUserId: otherUserId,
        fetchedMessages: fetched,
        hasMore: hasMore,
        before: before,
      );

      return MessagesResult(messages: fetched, hasMore: hasMore);
    } catch (e) {
      if (before == null) {
        final cached = await localStorage.getMessages(userId, otherUserId);
        if (cached.isNotEmpty) {
          return MessagesResult(messages: cached, hasMore: false);
        }
      }
      rethrow;
    }
  }

  Future<void> saveSingleMessage({
    required String userId,
    required String otherUserId,
    required MessageModel message,
  }) async {
    await localStorage.appendSingleMessage(userId, otherUserId, message);
  }

  Future<void> markAsRead({
    required String userId,
    required String otherUserId,
  }) async {
    final now = DateTime.now().toIso8601String();
    await localStorage.markMessagesAsRead(userId, otherUserId, readAt: now);
    try {
      await apiClient.post(
        '/api/messages/$userId/$otherUserId/read',
        authenticated: true,
      );
    } catch (_) {}
  }

  Future<void> deleteLocalMessage({
    required String userId,
    required String otherUserId,
    required String messageId,
  }) async {
    await localStorage.deleteMessage(userId, otherUserId, messageId);
  }

  Future<void> deleteMessage({
    required String userId,
    required String otherUserId,
    required String messageId,
  }) async {
    await localStorage.deleteMessage(userId, otherUserId, messageId);
    try {
      await apiClient.delete(
        '/api/messages/$messageId',
        authenticated: true,
      );
    } catch (_) {}
  }

  Future<void> updateDelivered({
    required String userId,
    required String otherUserId,
    required List<String> messageIds,
    required String deliveredAt,
  }) async {
    await localStorage.markMessagesAsDelivered(
      userId,
      otherUserId,
      messageIds,
      deliveredAt: deliveredAt,
    );
  }

  Future<List<MessageModel>> getPendingMessages({
    required String userId,
    required String otherUserId,
  }) async {
    return localStorage.getPendingMessages(
      userId: userId,
      otherUserId: otherUserId,
    );
  }

  Future<void> savePendingMessage(MessageModel message) async {
    await localStorage.savePendingMessage(message);
  }

  Future<void> replacePendingMessage({
    required String userId,
    required String otherUserId,
    required String tempId,
    required MessageModel confirmedMessage,
  }) async {
    await localStorage.replacePendingMessage(
      userId,
      otherUserId,
      tempId,
      confirmedMessage,
    );
  }

  Future<void> removePendingMessage(String tempId) async {
    await localStorage.removePendingMessage(tempId);
  }

  bool isMessageInFlight(String id) => localStorage.isMessageInFlight(id);
  void markMessageInFlight(String id) => localStorage.markMessageInFlight(id);
  void clearMessageInFlight(String id) => localStorage.clearMessageInFlight(id);
}


