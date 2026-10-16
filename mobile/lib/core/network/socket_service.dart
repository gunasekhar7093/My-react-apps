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

/// A single Socket.IO client that is created once in DashboardPage and shared
/// with ChatPage.  ChatPage registers page-level callbacks via [addOnMessage]
/// / [addOnUserStatus] and removes them in dispose without ever calling
/// [connect] or [disconnect].
class SocketService {
  final SecureStorageService storage;
  io.Socket? _socket;

  // Primary handlers registered at connection time (DashboardPage)
  UserStatusCallback? _onUserStatus;
  MessageCallback? _onMessage;

  // Secondary handlers registered by ChatPage while a chat is open.
  // Using a list so multiple listeners can coexist without stomping.
  final List<MessageCallback> _extraMessageCallbacks = [];
  final List<UserStatusCallback> _extraStatusCallbacks = [];

  SocketService({SecureStorageService? storage})
      : storage = storage ?? SecureStorageService();

  bool get isConnected => _socket?.connected == true;

  Future<void> connect({
    required UserStatusCallback onUserStatus,
    MessageCallback? onMessage,
    SocketConnectionCallback? onConnected,
    SocketErrorCallback? onError,
  }) async {
    _onUserStatus = onUserStatus;
    _onMessage = onMessage;

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
        final lastSeenAt = data['lastSeenAt']?.toString();
        // Dispatch to primary handler (DashboardPage)
        _onUserStatus?.call(
          userId: userId,
          status: status,
          lastSeenAt: lastSeenAt,
        );
        // Dispatch to any extra handlers (ChatPage)
        for (final cb in List.of(_extraStatusCallbacks)) {
          cb(userId: userId, status: status, lastSeenAt: lastSeenAt);
        }
      })
      ..on('private:message', (data) {
        if (data is! Map) return;
        final msg = Map<String, dynamic>.from(data);
        // Dispatch to primary handler (DashboardPage)
        _onMessage?.call(msg);
        // Dispatch to any extra handlers (ChatPage)
        for (final cb in List.of(_extraMessageCallbacks)) {
          cb(msg);
        }
      })
      ..connect();
  }

  // ── Secondary callback management (used by ChatPage) ─────────────────────

  /// Add an additional message listener. Call [removeOnMessage] in dispose.
  void addOnMessage(MessageCallback callback) {
    _extraMessageCallbacks.add(callback);
  }

  /// Remove a previously added message listener.
  void removeOnMessage([MessageCallback? callback]) {
    if (callback != null) {
      _extraMessageCallbacks.remove(callback);
    } else {
      _extraMessageCallbacks.clear();
    }
  }

  /// Add an additional user-status listener. Call [removeOnUserStatus] in dispose.
  void addOnUserStatus(UserStatusCallback callback) {
    _extraStatusCallbacks.add(callback);
  }

  /// Remove a previously added user-status listener.
  void removeOnUserStatus([UserStatusCallback? callback]) {
    if (callback != null) {
      _extraStatusCallbacks.remove(callback);
    } else {
      _extraStatusCallbacks.clear();
    }
  }

  // ── Message sending ───────────────────────────────────────────────────────

  Future<Map<String, dynamic>> sendMessage({
    required String receiverId,
    String text = '',
    String? mediaUrl,
    String? mediaType,
    String? mediaName,
    int? mediaSize,
  }) async {
    final socket = _socket;
    if (socket == null || socket.connected != true) {
      throw const SocketException('Chat connection is unavailable.');
    }

    final completer = Completer<Map<String, dynamic>>();
    socket.emitWithAck(
      'private:message',
      // ignore: use_null_aware_elements
      {
        'receiverId': receiverId,
        'text': text,
        if (mediaUrl != null) 'mediaUrl': mediaUrl,
        if (mediaType != null) 'mediaType': mediaType,
        if (mediaName != null) 'mediaName': mediaName,
        if (mediaSize != null) 'mediaSize': mediaSize,
      },
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
    _extraMessageCallbacks.clear();
    _extraStatusCallbacks.clear();
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
