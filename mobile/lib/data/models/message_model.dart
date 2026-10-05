class MessageModel {
  final String id;
  final String senderId;
  final String receiverId;
  final String text;
  final String createdAt;

  const MessageModel({
    required this.id,
    required this.senderId,
    required this.receiverId,
    required this.text,
    required this.createdAt,
  });

  factory MessageModel.fromJson(Map<String, dynamic> json) {
    return MessageModel(
      id: json['id']?.toString() ?? '',
      senderId: json['senderId']?.toString() ?? '',
      receiverId: json['receiverId']?.toString() ?? '',
      text: json['text']?.toString() ?? '',
      createdAt: json['createdAt']?.toString() ?? '',
    );
  }
}
