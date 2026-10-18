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
typedef MessagesReadCallback = void Function({
  required String readerId,
  required String readAt,
});
typedef MessagesDeliveredCallback = void Function({
  required String receiverId,
  required List<String> messageIds,
  required String deliveredAt,
});
typedef SocketConnectionCallback = void Function();
typedef SocketErrorCallback = void Function(String message);
typedef MessageDeletedCallback = void Function(String messageId);

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
  final List<MessagesReadCallback> _extraMessagesReadCallbacks = [];
  final List<MessagesDeliveredCallback> _extraMessagesDeliveredCallbacks = [];
  final List<MessageDeletedCallback> _extraMessageDeletedCallbacks = [];

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
          // Match the server's reduced heartbeat so the mobile client doesn't
          // false-disconnect before the server's pong window closes.
          // Server: pingInterval=10 000ms, pingTimeout=8 000ms
          .setTimeout(8000)        // equivalent to pingTimeout on client side
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
      ..on('messages:read', (data) {
        if (data is! Map) return;
        final readerId = data['readerId']?.toString();
        final readAt = data['readAt']?.toString() ?? DateTime.now().toIso8601String();
        if (readerId == null) return;
        for (final cb in List.of(_extraMessagesReadCallbacks)) {
          cb(readerId: readerId, readAt: readAt);
        }
      })
      ..on('messages:delivered', (data) {
        if (data is! Map) return;
        final receiverId = data['receiverId']?.toString();
        final deliveredAt = data['deliveredAt']?.toString() ?? DateTime.now().toIso8601String();
        final messageIdsRaw = data['messageIds'];
        final messageIds = messageIdsRaw is List
            ? messageIdsRaw.map((e) => e.toString()).toList()
            : <String>[];
        if (receiverId == null) return;
        for (final cb in List.of(_extraMessagesDeliveredCallbacks)) {
          cb(receiverId: receiverId, messageIds: messageIds, deliveredAt: deliveredAt);
        }
      })
      ..on('message:delete', (data) {
        if (data is! Map) return;
        final messageId = data['messageId']?.toString();
        if (messageId == null || messageId.isEmpty) return;
        for (final cb in List.of(_extraMessageDeletedCallbacks)) {
          cb(messageId);
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

  /// Add a listener for when messages are read by the recipient (Two White Ticks).
  void addOnMessagesRead(MessagesReadCallback callback) {
    _extraMessagesReadCallbacks.add(callback);
  }

  /// Remove a previously added read status listener.
  void removeOnMessagesRead([MessagesReadCallback? callback]) {
    if (callback != null) {
      _extraMessagesReadCallbacks.remove(callback);
    } else {
      _extraMessagesReadCallbacks.clear();
    }
  }

  /// Add a listener for when messages are delivered to the recipient (Two Gray Ticks).
  void addOnMessagesDelivered(MessagesDeliveredCallback callback) {
    _extraMessagesDeliveredCallbacks.add(callback);
  }

  /// Remove a previously added delivery status listener.
  void removeOnMessagesDelivered([MessagesDeliveredCallback? callback]) {
    if (callback != null) {
      _extraMessagesDeliveredCallbacks.remove(callback);
    } else {
      _extraMessagesDeliveredCallbacks.clear();
    }
  }

  /// Notify server via socket that we have read incoming messages from sender.
  void emitMessagesRead(String senderId) {
    _socket?.emit('messages:read', {'senderId': senderId});
  }

  /// Acknowledge delivery of messages to this device.
  void emitMessagesDelivered(List<String> messageIds) {
    if (messageIds.isNotEmpty) {
      _socket?.emit('messages:delivered', {'messageIds': messageIds});
    }
  }

  /// Add a listener for when a message is deleted. Call [removeOnMessageDeleted] in dispose.
  void addOnMessageDeleted(MessageDeletedCallback callback) {
    _extraMessageDeletedCallbacks.add(callback);
  }

  /// Remove a previously added delete listener.
  void removeOnMessageDeleted([MessageDeletedCallback? callback]) {
    if (callback != null) {
      _extraMessageDeletedCallbacks.remove(callback);
    } else {
      _extraMessageDeletedCallbacks.clear();
    }
  }

  /// Notify server and receiver that a message has been deleted.
  void emitMessageDelete(String messageId) {
    _socket?.emit('message:delete', {'messageId': messageId});
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
