import 'package:socket_io_client/socket_io_client.dart' as io;

import '../constants/api_constants.dart';
import '../storage/secure_storage_service.dart';

typedef UserStatusCallback = void Function({
  required String userId,
  required String status,
  String? lastSeenAt,
});

class SocketService {
  final SecureStorageService storage;
  io.Socket? _socket;

  SocketService({SecureStorageService? storage})
      : storage = storage ?? SecureStorageService();

  Future<void> connect({required UserStatusCallback onUserStatus}) async {
    if (_socket?.connected == true) return;

    final token = await storage.getToken();
    if (token == null || token.isEmpty) return;

    _socket = io.io(
      ApiConstants.baseUrl,
      io.OptionBuilder()
          .setTransports(['websocket'])
          .setAuth({'token': token})
          .disableAutoConnect()
          .enableReconnection()
          .build(),
    );

    _socket!
      ..on('user:status', (data) {
        if (data is! Map) return;
        final userId = data['userId']?.toString();
        final status = data['status']?.toString();
        if (userId == null || status == null) return;

        onUserStatus(
          userId: userId,
          status: status,
          lastSeenAt: data['lastSeenAt']?.toString(),
        );
      })
      ..connect();
  }

  void disconnect() {
    _socket?.disconnect();
    _socket?.dispose();
    _socket = null;
  }
}
