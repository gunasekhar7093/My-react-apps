import 'dart:async';

import 'package:socket_io_client/socket_io_client.dart' as io;

import '../constants/api_constants.dart';
import '../storage/secure_storage_service.dart';

typedef UserStatusCallback = void Function({
  required String userId,
  required String status,
  String? lastSeenAt,
});
typedef MessageCallback = void Function(Map<String, dynamic> message);
typedef SocketConnectionCallback = void Function();
typedef SocketErrorCallback = void Function(String message);

class SocketService {
  final SecureStorageService storage;
  io.Socket? _socket;

  SocketService({SecureStorageService? storage})
      : storage = storage ?? SecureStorageService();

  bool get isConnected => _socket?.connected == true;

  Future<void> connect({
    required UserStatusCallback onUserStatus,
    MessageCallback? onMessage,
    SocketConnectionCallback? onConnected,
    SocketErrorCallback? onError,
  }) async {
    if (_socket?.connected == true) return;

    final token = await storage.getToken();
    if (token == null || token.isEmpty) {
      onError?.call('No authentication token is available.');
      return;
    }

    _socket?.dispose();
    _socket = io.io(
      ApiConstants.baseUrl,
      io.OptionBuilder()
          // WebSocket is preferred, but polling fallback is important for
          // Flutter Web running through a Codespaces/tunnel proxy.
          .setTransports(['websocket', 'polling'])
          .setAuth({'token': token})
          .disableAutoConnect()
          .enableReconnection()
          .setReconnectionAttempts(10)
          .setReconnectionDelay(1000)
          .setReconnectionDelayMax(5000)
          .build(),
    );

    final socket = _socket!;
    socket
      ..onConnect((_) {
        onConnected?.call();
      })
      ..onConnectError((data) {
        onError?.call(data?.toString() ?? 'Socket connection failed.');
      })
      ..onError((data) {
        onError?.call(data?.toString() ?? 'Socket error.');
      })
      ..onDisconnect((_) {})
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
      ..on('private:message', (data) {
        if (onMessage == null || data is! Map) return;
        onMessage(Map<String, dynamic>.from(data));
      })
      ..connect();
  }

  Future<Map<String, dynamic>> sendMessage({
    required String receiverId,
    required String text,
  }) async {
    final socket = _socket;
    if (socket == null || socket.connected != true) {
      throw const SocketException('Chat connection is unavailable.');
    }

    final completer = Completer<Map<String, dynamic>>();
    socket.emitWithAck(
      'private:message',
      {'receiverId': receiverId, 'text': text},
      ack: (data) {
        if (!completer.isCompleted) {
          completer.complete(
            data is Map
                ? Map<String, dynamic>.from(data)
                : {'ok': false, 'error': 'Invalid server response.'},
          );
        }
      },
    );

    final response = await completer.future.timeout(
      const Duration(seconds: 10),
      onTimeout: () => throw const SocketException('Message send timed out.'),
    );

    if (response['ok'] != true) {
      throw SocketException(
        response['error']?.toString() ?? 'Could not send message.',
      );
    }
    return response;
  }

  void disconnect() {
    _socket?.disconnect();
    _socket?.dispose();
    _socket = null;
  }
}

class SocketException implements Exception {
  final String message;
  const SocketException(this.message);
  @override
  String toString() => message;
}
