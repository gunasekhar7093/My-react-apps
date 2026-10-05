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
    if (message.senderId == otherUserId) add(const ChatMarkedRead());
  }

  Future<void> _onSendRequested(
    ChatMessageSendRequested event,
    Emitter<ChatState> emit,
  ) async {
    final text = event.text.trim();
    if (text.isEmpty || state.sending) return;
    emit(state.copyWith(sending: true, clearError: true));
    try {
      await socket.sendMessage(receiverId: otherUserId, text: text);
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
      await repository.markAsRead(userId: userId, otherUserId: otherUserId);
    } catch (_) {
      // Reading messages should not interrupt the conversation UI.
    }
  }
}
