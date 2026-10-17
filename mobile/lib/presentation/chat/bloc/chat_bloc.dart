import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/network/socket_service.dart';
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
    on<ChatMarkedRead>(_onMarkedRead);
    on<ChatMessagesReadReceived>(_onMessagesReadReceived);
    on<ChatMessagesDeliveredReceived>(_onMessagesDeliveredReceived);
  }

  Future<void> _onStarted(ChatStarted event, Emitter<ChatState> emit) async {
    if (state.status == ChatStatus.ready || state.status == ChatStatus.loading) {
      return;
    }
    emit(state.copyWith(status: ChatStatus.loading, clearError: true));
    try {
      final messages = await repository.getMessages(
        userId: userId,
        otherUserId: otherUserId,
      );
      emit(state.copyWith(status: ChatStatus.ready, messages: messages));
      add(const ChatMarkedRead());

      // Acknowledge delivery for all incoming messages that haven't been delivered
      final undeliveredIds = messages
          .where((m) => m.receiverId == userId && (m.deliveredAt == null || m.deliveredAt!.isEmpty))
          .map((m) => m.id)
          .toList();
      if (undeliveredIds.isNotEmpty) {
        socket.emitMessagesDelivered(undeliveredIds);
      }
    } catch (error) {
      emit(state.copyWith(
        status: ChatStatus.failure,
        errorMessage: error.toString(),
      ));
    }
  }

  void _onMessageReceived(ChatMessageReceived event, Emitter<ChatState> emit) {
    if (event.message is! MessageModel) return;
    final message = event.message as MessageModel;
    if (!((message.senderId == userId && message.receiverId == otherUserId) ||
        (message.senderId == otherUserId && message.receiverId == userId))) {
      return;
    }
    if (state.messages.any((item) => item.id == message.id)) return;
    emit(state.copyWith(messages: [...state.messages, message], status: ChatStatus.ready));

    if (message.senderId == otherUserId) {
      // Chat is open: acknowledge delivery and mark read immediately
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
    if (state.sending) return;
    emit(state.copyWith(sending: true, clearError: true));
    try {
      await socket.sendMessage(
        receiverId: otherUserId,
        text: text,
        mediaUrl: event.mediaUrl,
        mediaType: event.mediaType,
        mediaName: event.mediaName,
        mediaSize: event.mediaSize,
      );
    } catch (error) {
      emit(state.copyWith(errorMessage: error.toString()));
    } finally {
      emit(state.copyWith(sending: false));
    }
  }

  Future<void> _onMarkedRead(
    ChatMarkedRead event,
    Emitter<ChatState> emit,
  ) async {
    try {
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
  }
}
