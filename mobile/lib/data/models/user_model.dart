class UserModel {
  final String id;
  final String name;
  final String username;
  final String phone;
  final String status;
  final String? lastSeenAt;
  final String? latestMessageAt;
  final int unreadCount;

  const UserModel({
    required this.id,
    required this.name,
    required this.username,
    this.phone = '',
    this.status = 'offline',
    this.lastSeenAt,
    this.latestMessageAt,
    this.unreadCount = 0,
  });

  factory UserModel.fromJson(Map<String, dynamic> json) {
    return UserModel(
      id: json['id']?.toString() ?? json['_id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      username: json['username']?.toString() ?? '',
      phone: json['phone']?.toString() ?? '',
      status: json['status']?.toString() ?? 'offline',
      lastSeenAt: json['lastSeenAt']?.toString(),
      latestMessageAt: json['latestMessageAt']?.toString(),
      unreadCount: int.tryParse(json['unreadCount']?.toString() ?? '') ?? 0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'username': username,
      'phone': phone,
      'status': status,
      'lastSeenAt': lastSeenAt,
      'latestMessageAt': latestMessageAt,
      'unreadCount': unreadCount,
    };
  }

  UserModel copyWith({
    String? id,
    String? name,
    String? username,
    String? phone,
    String? status,
    String? lastSeenAt,
    String? latestMessageAt,
    int? unreadCount,
  }) {
    return UserModel(
      id: id ?? this.id,
      name: name ?? this.name,
      username: username ?? this.username,
      phone: phone ?? this.phone,
      status: status ?? this.status,
      lastSeenAt: lastSeenAt ?? this.lastSeenAt,
      latestMessageAt: latestMessageAt ?? this.latestMessageAt,
      unreadCount: unreadCount ?? this.unreadCount,
    );
  }
}
