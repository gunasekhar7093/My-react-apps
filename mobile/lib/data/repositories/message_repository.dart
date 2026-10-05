import '../../core/network/api_client.dart';
import '../models/message_model.dart';

class MessageRepository {
  final ApiClient apiClient;

  MessageRepository({ApiClient? apiClient})
      : apiClient = apiClient ?? ApiClient();

  Future<List<MessageModel>> getMessages({
    required String userId,
    required String otherUserId,
    int limit = 40,
  }) async {
    final data = await apiClient.get(
      '/api/messages/$userId/$otherUserId?limit=$limit',
      authenticated: true,
    );
    final messages = data['messages'];
    if (messages is! List) return const [];
    return messages
        .whereType<Map<String, dynamic>>()
        .map(MessageModel.fromJson)
        .toList();
  }

  Future<void> markAsRead({
    required String userId,
    required String otherUserId,
  }) async {
    await apiClient.post(
      '/api/messages/$userId/$otherUserId/read',
      authenticated: true,
    );
  }
}
