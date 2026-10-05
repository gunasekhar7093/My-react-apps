class UserModel {
  final String id;
  final String name;
  final String username;
  final String phone;
  final String status;
  final String? lastSeenAt;

  const UserModel({
    required this.id,
    required this.name,
    required this.username,
    this.phone = '',
    this.status = 'offline',
    this.lastSeenAt,
  });

  factory UserModel.fromJson(Map<String, dynamic> json) {
    return UserModel(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      username: json['username']?.toString() ?? '',
      phone: json['phone']?.toString() ?? '',
      status: json['status']?.toString() ?? 'offline',
      lastSeenAt: json['lastSeenAt']?.toString(),
    );
  }
}
