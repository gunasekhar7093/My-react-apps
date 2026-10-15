class MessageModel {
  final String id;
  final String senderId;
  final String receiverId;
  final String text;
  final String createdAt;
  final String? mediaUrl;
  final String? mediaType;
  final String? mediaName;
  final int? mediaSize;

  const MessageModel({
    required this.id,
    required this.senderId,
    required this.receiverId,
    required this.text,
    required this.createdAt,
    this.mediaUrl,
    this.mediaType,
    this.mediaName,
    this.mediaSize,
  });

  bool get isMedia => mediaUrl != null && mediaUrl!.isNotEmpty;
  bool get isImage => mediaType == 'image';
  bool get isVideo => mediaType == 'video';

  factory MessageModel.fromJson(Map<String, dynamic> json) {
    return MessageModel(
      id: json['id']?.toString() ?? '',
      senderId: json['senderId']?.toString() ?? '',
      receiverId: json['receiverId']?.toString() ?? '',
      text: json['text']?.toString() ?? '',
      createdAt: json['createdAt']?.toString() ?? '',
      mediaUrl: json['mediaUrl']?.toString(),
      mediaType: json['mediaType']?.toString(),
      mediaName: json['mediaName']?.toString(),
      mediaSize: json['mediaSize'] is int
          ? json['mediaSize'] as int
          : int.tryParse(json['mediaSize']?.toString() ?? ''),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'senderId': senderId,
      'receiverId': receiverId,
      'text': text,
      'createdAt': createdAt,
      'mediaUrl': ?mediaUrl,
      'mediaType': ?mediaType,
      'mediaName': ?mediaName,
      'mediaSize': ?mediaSize,
    };
  }
}
