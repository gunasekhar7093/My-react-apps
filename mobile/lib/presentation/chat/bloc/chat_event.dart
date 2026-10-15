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
