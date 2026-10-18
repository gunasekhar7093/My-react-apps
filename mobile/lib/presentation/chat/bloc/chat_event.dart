abstract class ChatEvent {
  const ChatEvent();
}

class ChatStarted extends ChatEvent {
  const ChatStarted();
}

class ChatMessageReceived extends ChatEvent {
  final dynamic message;
  const ChatMessageReceived(this.message);
}

class ChatMessageSendRequested extends ChatEvent {
  final String text;
  final String? mediaUrl;
  final String? mediaType;
  final String? mediaName;
  final int? mediaSize;

  const ChatMessageSendRequested(
    this.text, {
    this.mediaUrl,
    this.mediaType,
    this.mediaName,
    this.mediaSize,
  });
}

class ChatMarkedRead extends ChatEvent {
  const ChatMarkedRead();
}

class ChatMessagesReadReceived extends ChatEvent {
  final String readerId;
  final String readAt;
  const ChatMessagesReadReceived({required this.readerId, required this.readAt});
}

class ChatMessagesDeliveredReceived extends ChatEvent {
  final String receiverId;
  final List<String> messageIds;
  final String deliveredAt;
  const ChatMessagesDeliveredReceived({
    required this.receiverId,
    required this.messageIds,
    required this.deliveredAt,
  });
}

class ChatMessageDeleteRequested extends ChatEvent {
  final String messageId;
  const ChatMessageDeleteRequested(this.messageId);
}

class ChatMessageDeletedReceived extends ChatEvent {
  final String messageId;
  const ChatMessageDeletedReceived(this.messageId);
}

class ChatLoadOlderMessagesRequested extends ChatEvent {
  const ChatLoadOlderMessagesRequested();
}
