import '../../../data/models/message_model.dart';

enum ChatStatus { initial, loading, ready, failure }

class ChatState {
  final ChatStatus status;
  final List<MessageModel> messages;
  final String? errorMessage;
  final bool sending;

  const ChatState({
    this.status = ChatStatus.initial,
    this.messages = const [],
    this.errorMessage,
    this.sending = false,
  });

  ChatState copyWith({
    ChatStatus? status,
    List<MessageModel>? messages,
    String? errorMessage,
    bool? sending,
    bool clearError = false,
  }) {
    return ChatState(
      status: status ?? this.status,
      messages: messages ?? this.messages,
      errorMessage: clearError ? null : errorMessage ?? this.errorMessage,
      sending: sending ?? this.sending,
    );
  }
}
