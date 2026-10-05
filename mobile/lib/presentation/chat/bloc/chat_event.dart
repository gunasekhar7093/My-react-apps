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
  const ChatMessageSendRequested(this.text);
}

class ChatMarkedRead extends ChatEvent {
  const ChatMarkedRead();
}
