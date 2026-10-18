import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/network/socket_service.dart';
import '../../../core/services/notification_service.dart';
import '../../../data/models/message_model.dart';
import '../../../data/repositories/message_repository.dart';
import 'chat_event.dart';
import 'chat_state.dart';

class ChatBloc extends Bloc<ChatEvent, ChatState> {
  final MessageRepository repository;
  final SocketService socket;
  final String userId;
  final String otherUserId;

  ChatBloc({
    required this.repository,
    required this.socket,
    required this.userId,
    required this.otherUserId,
  }) : super(const ChatState()) {
    on<ChatStarted>(_onStarted);
    on<ChatMessageReceived>(_onMessageReceived);
    on<ChatMessageSendRequested>(_onSendRequested);
    on<ChatFlushPendingRequested>(_onFlushPendingRequested);
    on<ChatMarkedRead>(_onMarkedRead);
    on<ChatMessagesReadReceived>(_onMessagesReadReceived);
    on<ChatMessagesDeliveredReceived>(_onMessagesDeliveredReceived);
    on<ChatMessageDeleteRequested>(_onDeleteRequested);
    on<ChatMessageDeletedReceived>(_onDeletedReceived);
    on<ChatLoadOlderMessagesRequested>(_onLoadOlderMessagesRequested);
  }

  Future<void> _onStarted(ChatStarted event, Emitter<ChatState> emit) async {
    if (state.status == ChatStatus.ready || state.status == ChatStatus.loading) {
      return;
    }
    NotificationService().cancelSenderNotification(otherUserId);

    // 1. Immediately load and emit cached messages so offline users can view chat history instantly
    final cached = await repository.getCachedMessages(
      userId: userId,
      otherUserId: otherUserId,
    );
    if (cached.isNotEmpty) {
      emit(state.copyWith(
        status: ChatStatus.ready,
        messages: cached,
        clearError: true,
      ));
    } else {
      emit(state.copyWith(status: ChatStatus.loading, clearError: true));
    }

    // If socket is already connected, flush any cached pending messages right away
    if (socket.isConnected) {
      add(const ChatFlushPendingRequested());
    }

    // 2. Fetch latest messages from server in background
    try {
      final result = await repository.getMessages(
        userId: userId,
        otherUserId: otherUserId,
      );

      // Preserve any pending offline messages that haven't reached the server yet
      final pendingList = await repository.getPendingMessages(
        userId: userId,
        otherUserId: otherUserId,
      );
      final serverIds = result.messages.map((m) => m.id).toSet();
      final stillPending = pendingList.where((p) => !serverIds.contains(p.id)).toList();
      final combined = [...result.messages, ...stillPending];

      emit(state.copyWith(
        status: ChatStatus.ready,
        messages: combined,
        hasMoreOlder: result.hasMore,
        clearError: true,
      ));
      add(const ChatMarkedRead());

      if (stillPending.isNotEmpty && socket.isConnected) {
        add(const ChatFlushPendingRequested());
      }

      // Acknowledge delivery for all incoming messages that haven't been delivered
      final undeliveredIds = result.messages
          .where((m) => m.receiverId == userId && (m.deliveredAt == null || m.deliveredAt!.isEmpty))
          .map((m) => m.id)
          .toList();
      if (undeliveredIds.isNotEmpty) {
        socket.emitMessagesDelivered(undeliveredIds);
      }
    } catch (error) {
      // If we already have cached messages in state, stay in ready state so user can view history!
      emit(state.copyWith(
        status: state.messages.isNotEmpty ? ChatStatus.ready : ChatStatus.failure,
        errorMessage: state.messages.isNotEmpty ? null : error.toString(),
      ));
    }
  }

  Future<void> _onLoadOlderMessagesRequested(
    ChatLoadOlderMessagesRequested event,
    Emitter<ChatState> emit,
  ) async {
    if (state.loadingOlder || !state.hasMoreOlder || state.messages.isEmpty) return;

    emit(state.copyWith(loadingOlder: true));
    try {
      final oldest = state.messages.first;
      final result = await repository.getMessages(
        userId: userId,
        otherUserId: otherUserId,
        before: oldest.createdAt,
      );

      if (result.messages.isEmpty) {
        emit(state.copyWith(loadingOlder: false, hasMoreOlder: false));
        return;
      }

      final existingIds = state.messages.map((m) => m.id).toSet();
      final newOlder = result.messages.where((m) => !existingIds.contains(m.id)).toList();

      final combined = [...newOlder, ...state.messages];
      emit(state.copyWith(
        loadingOlder: false,
        messages: combined,
        hasMoreOlder: result.hasMore,
      ));
    } catch (_) {
      // If offline or network error while scrolling back, gracefully finish loading
      emit(state.copyWith(loadingOlder: false));
    }
  }

  void _onMessageReceived(ChatMessageReceived event, Emitter<ChatState> emit) {
    if (event.message is! MessageModel) return;
    final message = event.message as MessageModel;
    if (!((message.senderId == userId && message.receiverId == otherUserId) ||
        (message.senderId == otherUserId && message.receiverId == userId))) {
      return;
    }

    // If this is our own message echo from server, check if it matches a pending message
    if (message.senderId == userId) {
      final pendingIdx = state.messages.indexWhere(
        (m) =>
            (m.isPending || m.id.startsWith('temp_')) &&
            (m.text == message.text ||
                (m.mediaUrl != null && m.mediaUrl == message.mediaUrl)),
      );
      if (pendingIdx != -1) {
        final tempId = state.messages[pendingIdx].id;
        final updatedList = List<MessageModel>.from(state.messages);
        updatedList[pendingIdx] = message;
        emit(state.copyWith(messages: updatedList, status: ChatStatus.ready));

        repository.replacePendingMessage(
          userId: userId,
          otherUserId: otherUserId,
          tempId: tempId,
          confirmedMessage: message,
        );
        return;
      }
    }

    if (state.messages.any((item) => item.id == message.id)) return;
    emit(state.copyWith(messages: [...state.messages, message], status: ChatStatus.ready));

    // Save to local cache
    repository.saveSingleMessage(
      userId: userId,
      otherUserId: otherUserId,
      message: message,
    );

    if (message.senderId == otherUserId) {
      // Chat is open: dismiss notifications, acknowledge delivery, and mark read immediately
      NotificationService().cancelSenderNotification(otherUserId);
      socket.emitMessagesDelivered([message.id]);
      add(const ChatMarkedRead());
    }
  }

  Future<void> _onSendRequested(
    ChatMessageSendRequested event,
    Emitter<ChatState> emit,
  ) async {
    final text = event.text.trim();
    if (text.isEmpty && (event.mediaUrl == null || event.mediaUrl!.isEmpty)) return;

    final tempId = 'temp_${DateTime.now().microsecondsSinceEpoch}';
    final nowIso = DateTime.now().toIso8601String();
    final isOnline = socket.isConnected;

    final pendingMessage = MessageModel(
      id: tempId,
      senderId: userId,
      receiverId: otherUserId,
      text: text,
      createdAt: nowIso,
      mediaUrl: event.mediaUrl,
      mediaType: event.mediaType,
      mediaName: event.mediaName,
      mediaSize: event.mediaSize,
      isPending: !isOnline,
    );

    // Optimistically add to conversation:
    // If online: immediately shows Single Tick (✓ MessageStatus.sent) with ZERO clock flicker!
    // If offline: immediately shows Clock Icon (🕒 MessageStatus.pending).
    emit(state.copyWith(
      messages: [...state.messages, pendingMessage],
      status: ChatStatus.ready,
      clearError: true,
    ));

    // Save locally to message cache
    await repository.saveSingleMessage(
      userId: userId,
      otherUserId: otherUserId,
      message: pendingMessage,
    );

    // If offline, queue in pending outbox for automatic retry when internet returns
    if (!isOnline) {
      await repository.savePendingMessage(pendingMessage);
    }

    // If socket is connected, attempt sending immediately
    if (isOnline) {
      try {
        final res = await socket.sendMessage(
          receiverId: otherUserId,
          text: text,
          mediaUrl: event.mediaUrl,
          mediaType: event.mediaType,
          mediaName: event.mediaName,
          mediaSize: event.mediaSize,
        );
        final confirmedRaw = res['message'];
        if (confirmedRaw is Map) {
          final confirmedMessage = MessageModel.fromJson(Map<String, dynamic>.from(confirmedRaw));
          await repository.replacePendingMessage(
            userId: userId,
            otherUserId: otherUserId,
            tempId: tempId,
            confirmedMessage: confirmedMessage,
          );
          final updated = state.messages.map((m) => m.id == tempId ? confirmedMessage : m).toList();
          emit(state.copyWith(messages: updated));
        }
      } catch (_) {
        // If sending failed (network drop/timeout), transition to Clock Icon (🕒) and queue
        final markedPending = pendingMessage.copyWith(isPending: true);
        await repository.saveSingleMessage(
          userId: userId,
          otherUserId: otherUserId,
          message: markedPending,
        );
        await repository.savePendingMessage(markedPending);
        final updated = state.messages.map((m) => m.id == tempId ? markedPending : m).toList();
        emit(state.copyWith(messages: updated));
      }
    }
  }

  Future<void> _onFlushPendingRequested(
    ChatFlushPendingRequested event,
    Emitter<ChatState> emit,
  ) async {
    if (!socket.isConnected) return;

    final pendingList = await repository.getPendingMessages(
      userId: userId,
      otherUserId: otherUserId,
    );

    final queueMap = <String, MessageModel>{};
    for (final m in state.messages) {
      if (m.isPending || m.id.startsWith('temp_')) {
        queueMap[m.id] = m;
      }
    }
    for (final m in pendingList) {
      queueMap[m.id] = m;
    }

    if (queueMap.isEmpty) return;

    final queue = queueMap.values.toList()
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));

    for (final pending in queue) {
      if (!socket.isConnected) break;
      try {
        final res = await socket.sendMessage(
          receiverId: otherUserId,
          text: pending.text,
          mediaUrl: pending.mediaUrl,
          mediaType: pending.mediaType,
          mediaName: pending.mediaName,
          mediaSize: pending.mediaSize,
        );
        final confirmedRaw = res['message'];
        if (confirmedRaw is Map) {
          final confirmed = MessageModel.fromJson(Map<String, dynamic>.from(confirmedRaw));
          await repository.replacePendingMessage(
            userId: userId,
            otherUserId: otherUserId,
            tempId: pending.id,
            confirmedMessage: confirmed,
          );
          final updated = state.messages.map((m) => m.id == pending.id ? confirmed : m).toList();
          emit(state.copyWith(messages: updated));
        }
      } catch (_) {
        // Disconnected or socket error; pause flush and resume on next connect
        break;
      }
    }
  }

  Future<void> _onMarkedRead(
    ChatMarkedRead event,
    Emitter<ChatState> emit,
  ) async {
    try {
      NotificationService().cancelSenderNotification(otherUserId);
      socket.emitMessagesRead(otherUserId);
      await repository.markAsRead(userId: userId, otherUserId: otherUserId);
    } catch (_) {
      // Reading messages should not interrupt the conversation UI.
    }
  }

  void _onMessagesReadReceived(
    ChatMessagesReadReceived event,
    Emitter<ChatState> emit,
  ) {
    if (event.readerId != otherUserId) return;
    final updated = state.messages.map((m) {
      if (m.senderId == userId && (m.readAt == null || m.readAt!.isEmpty)) {
        return m.copyWith(readAt: event.readAt, deliveredAt: event.readAt);
      }
      return m;
    }).toList();
    emit(state.copyWith(messages: updated));
  }

  void _onMessagesDeliveredReceived(
    ChatMessagesDeliveredReceived event,
    Emitter<ChatState> emit,
  ) {
    if (event.receiverId != otherUserId) return;
    final idSet = event.messageIds.toSet();
    final updated = state.messages.map((m) {
      if (m.senderId == userId && (m.deliveredAt == null || m.deliveredAt!.isEmpty)) {
        if (idSet.isEmpty || idSet.contains(m.id)) {
          return m.copyWith(deliveredAt: event.deliveredAt);
        }
      }
      return m;
    }).toList();
    emit(state.copyWith(messages: updated));

    repository.updateDelivered(
      userId: userId,
      otherUserId: otherUserId,
      messageIds: event.messageIds,
      deliveredAt: event.deliveredAt,
    );
  }

  Future<void> _onDeleteRequested(
    ChatMessageDeleteRequested event,
    Emitter<ChatState> emit,
  ) async {
    final updated = state.messages.where((m) => m.id != event.messageId).toList();
    emit(state.copyWith(messages: updated));
    try {
      socket.emitMessageDelete(event.messageId);
      await repository.deleteMessage(
        userId: userId,
        otherUserId: otherUserId,
        messageId: event.messageId,
      );
    } catch (_) {
      // Optimistic delete
    }
  }

  void _onDeletedReceived(
    ChatMessageDeletedReceived event,
    Emitter<ChatState> emit,
  ) {
    final updated = state.messages.where((m) => m.id != event.messageId).toList();
    emit(state.copyWith(messages: updated));

    repository.deleteMessage(
      userId: userId,
      otherUserId: otherUserId,
      messageId: event.messageId,
    );
  }
}
