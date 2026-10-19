import 'dart:convert';

enum MessageStatus {
  pending,   // Clock Icon (🕒): Queued locally on device, waiting for internet
  sent,      // One Gray Tick (✓): Sent to server, not yet reached recipient's device
  delivered, // Two Gray Ticks (✓✓): Delivered to recipient's device
  read,      // Two White Ticks (✓✓): Recipient has opened and read the message
}

class MessageReplyModel {
  final String id;
  final String text;
  final String senderId;
  final String senderName;
  final String? mediaType;
  final String? mediaUrl;

  const MessageReplyModel({
    required this.id,
    required this.text,
    required this.senderId,
    required this.senderName,
    this.mediaType,
    this.mediaUrl,
  });

  factory MessageReplyModel.fromJson(Map<String, dynamic> json) {
    return MessageReplyModel(
      id: json['id']?.toString() ?? '',
      text: json['text']?.toString() ?? '',
      senderId: json['senderId']?.toString() ?? '',
      senderName: json['senderName']?.toString() ?? '',
      mediaType: json['mediaType']?.toString(),
      mediaUrl: json['mediaUrl']?.toString(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'text': text,
      'senderId': senderId,
      'senderName': senderName,
      'mediaType': ?mediaType,
      'mediaUrl': ?mediaUrl,
    };
  }
}

class MessageModel {
  final String id;
  final String? clientTempId;
  final String senderId;
  final String receiverId;
  final String text;
  final String createdAt;
  final String? deliveredAt;
  final String? readAt;
  final String? mediaUrl;
  final String? mediaType;
  final String? mediaName;
  final int? mediaSize;
  final String? senderName;
  final bool isPending;
  final MessageReplyModel? replyTo;

  const MessageModel({
    required this.id,
    this.clientTempId,
    required this.senderId,
    required this.receiverId,
    required this.text,
    required this.createdAt,
    this.deliveredAt,
    this.readAt,
    this.mediaUrl,
    this.mediaType,
    this.mediaName,
    this.mediaSize,
    this.senderName,
    this.isPending = false,
    this.replyTo,
  });

  bool get isMedia => mediaUrl != null && mediaUrl!.isNotEmpty;
  bool get isImage => mediaType == 'image';
  bool get isVideo => mediaType == 'video';

  MessageStatus get status {
    if (isPending) {
      return MessageStatus.pending;
    }
    if (readAt != null && readAt!.isNotEmpty) {
      return MessageStatus.read;
    }
    if (deliveredAt != null && deliveredAt!.isNotEmpty) {
      return MessageStatus.delivered;
    }
    return MessageStatus.sent;
  }

  static MessageReplyModel? _parseReplyTo(dynamic val) {
    if (val == null) return null;
    if (val is Map) {
      return MessageReplyModel.fromJson(Map<String, dynamic>.from(val));
    }
    if (val is String && val.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(val);
        if (decoded is Map) {
          return MessageReplyModel.fromJson(Map<String, dynamic>.from(decoded));
        }
      } catch (_) {}
    }
    return null;
  }

  factory MessageModel.fromJson(Map<String, dynamic> json) {
    return MessageModel(
      id: json['id']?.toString() ?? '',
      clientTempId: json['clientTempId']?.toString(),
      senderId: json['senderId']?.toString() ?? '',
      receiverId: json['receiverId']?.toString() ?? '',
      text: json['text']?.toString() ?? '',
      createdAt: json['createdAt']?.toString() ?? '',
      deliveredAt: json['deliveredAt']?.toString(),
      readAt: json['readAt']?.toString(),
      mediaUrl: json['mediaUrl']?.toString(),
      mediaType: json['mediaType']?.toString(),
      mediaName: json['mediaName']?.toString(),
      senderName: json['senderName']?.toString(),
      isPending: json['isPending'] == true || json['status'] == 'pending',
      mediaSize: json['mediaSize'] is int
          ? json['mediaSize'] as int
          : int.tryParse(json['mediaSize']?.toString() ?? ''),
      replyTo: _parseReplyTo(json['replyTo']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'clientTempId': ?clientTempId,
      'senderId': senderId,
      'receiverId': receiverId,
      'text': text,
      'createdAt': createdAt,
      'deliveredAt': ?deliveredAt,
      'readAt': ?readAt,
      'mediaUrl': ?mediaUrl,
      'mediaType': ?mediaType,
      'mediaName': ?mediaName,
      'mediaSize': ?mediaSize,
      'senderName': ?senderName,
      'isPending': isPending,
      'replyTo': ?replyTo?.toJson(),
    };
  }

  MessageModel copyWith({
    String? id,
    String? clientTempId,
    String? senderId,
    String? receiverId,
    String? text,
    String? createdAt,
    String? deliveredAt,
    String? readAt,
    String? mediaUrl,
    String? mediaType,
    String? mediaName,
    int? mediaSize,
    String? senderName,
    bool? isPending,
    MessageReplyModel? replyTo,
  }) {
    return MessageModel(
      id: id ?? this.id,
      clientTempId: clientTempId ?? this.clientTempId,
      senderId: senderId ?? this.senderId,
      receiverId: receiverId ?? this.receiverId,
      text: text ?? this.text,
      createdAt: createdAt ?? this.createdAt,
      deliveredAt: deliveredAt ?? this.deliveredAt,
      readAt: readAt ?? this.readAt,
      mediaUrl: mediaUrl ?? this.mediaUrl,
      mediaType: mediaType ?? this.mediaType,
      mediaName: mediaName ?? this.mediaName,
      mediaSize: mediaSize ?? this.mediaSize,
      senderName: senderName ?? this.senderName,
      isPending: isPending ?? this.isPending,
      replyTo: replyTo ?? this.replyTo,
    );
  }

  /// Deduplicates a collection of messages.
  /// - Strips redundant copies (matching `id` or matching `clientTempId` or `id == clientTempId`).
  /// - Prefers confirmed/server messages over pending temporary messages.
  /// - Prefers messages with read/delivered status over unacknowledged ones.
  /// - Returns a list sorted chronologically by `createdAt`.
  static List<MessageModel> deduplicate(Iterable<MessageModel> messages) {
    if (messages.isEmpty) return const [];

    final list = messages.toList();

    // Sort so confirmed messages precede pending messages,
    // ensuring confirmed messages claim their IDs and clientTempIds first!
    list.sort((a, b) {
      final aPending = a.isPending || a.id.startsWith('temp_');
      final bPending = b.isPending || b.id.startsWith('temp_');
      if (aPending != bPending) {
        return aPending ? 1 : -1;
      }
      final aHasStatus = (a.readAt != null && a.readAt!.isNotEmpty) ||
          (a.deliveredAt != null && a.deliveredAt!.isNotEmpty);
      final bHasStatus = (b.readAt != null && b.readAt!.isNotEmpty) ||
          (b.deliveredAt != null && b.deliveredAt!.isNotEmpty);
      if (aHasStatus != bHasStatus) {
        return aHasStatus ? -1 : 1;
      }
      return 0;
    });

    final seenIds = <String>{};
    final result = <MessageModel>[];

    for (final m in list) {
      final id = m.id.trim();
      final clientTempId = m.clientTempId?.trim();

      final isDuplicateId = id.isNotEmpty && seenIds.contains(id);
      final isDuplicateTempId = clientTempId != null &&
          clientTempId.isNotEmpty &&
          seenIds.contains(clientTempId);

      if (isDuplicateId || isDuplicateTempId) {
        continue;
      }

      if (id.isNotEmpty) {
        seenIds.add(id);
      }
      if (clientTempId != null && clientTempId.isNotEmpty) {
        seenIds.add(clientTempId);
      }

      result.add(m);
    }

    result.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return result;
  }
}

