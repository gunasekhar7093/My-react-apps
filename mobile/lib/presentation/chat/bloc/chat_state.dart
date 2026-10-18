import '../../../data/models/message_model.dart';

enum ChatStatus { initial, loading, ready, failure }

class ChatState {
  final ChatStatus status;
  final List<MessageModel> messages;
  final String? errorMessage;
  final bool sending;
  final bool hasMoreOlder;
  final bool loadingOlder;

  const ChatState({
    this.status = ChatStatus.initial,
    this.messages = const [],
    this.errorMessage,
    this.sending = false,
    this.hasMoreOlder = true,
    this.loadingOlder = false,
  });

  ChatState copyWith({
    ChatStatus? status,
    List<MessageModel>? messages,
    String? errorMessage,
    bool? sending,
    bool? hasMoreOlder,
    bool? loadingOlder,
    bool clearError = false,
  }) {
    return ChatState(
      status: status ?? this.status,
      messages: messages ?? this.messages,
      errorMessage: clearError ? null : errorMessage ?? this.errorMessage,
      sending: sending ?? this.sending,
      hasMoreOlder: hasMoreOlder ?? this.hasMoreOlder,
      loadingOlder: loadingOlder ?? this.loadingOlder,
    );
  }
}
