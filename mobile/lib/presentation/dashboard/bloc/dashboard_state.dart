import '../../../data/models/user_model.dart';

enum DashboardStatus { initial, loading, ready, failure }

class DashboardState {
  final DashboardStatus status;
  final List<UserModel> users;
  final String searchQuery;
  final String? errorMessage;
  /// The id of the chat partner whose conversation is currently open.
  /// While non-null, incoming messages from this user must NOT increment
  /// the unread badge because the user is actively reading that chat.
  final String? openChatUserId;

  const DashboardState({
    this.status = DashboardStatus.initial,
    this.users = const [],
    this.searchQuery = '',
    this.errorMessage,
    this.openChatUserId,
  });

  List<UserModel> get filteredUsers {
    final query = searchQuery.trim().toLowerCase();
    final sorted = [...users]
      ..sort((a, b) {
        final aTime = a.latestMessageAt == null ? 0 : DateTime.tryParse(a.latestMessageAt!)?.millisecondsSinceEpoch ?? 0;
        final bTime = b.latestMessageAt == null ? 0 : DateTime.tryParse(b.latestMessageAt!)?.millisecondsSinceEpoch ?? 0;
        if (bTime != aTime) return bTime.compareTo(aTime);
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });

    if (query.isEmpty) return sorted;
    return sorted.where((user) =>
      user.name.toLowerCase().contains(query) ||
      user.username.toLowerCase().contains(query)
    ).toList();
  }

  int get onlineCount => users.where((user) => user.status == 'online').length;

  DashboardState copyWith({
    DashboardStatus? status,
    List<UserModel>? users,
    String? searchQuery,
    String? errorMessage,
    String? openChatUserId,
    bool clearOpenChatUserId = false,
  }) {
    return DashboardState(
      status: status ?? this.status,
      users: users ?? this.users,
      searchQuery: searchQuery ?? this.searchQuery,
      errorMessage: errorMessage,
      openChatUserId: clearOpenChatUserId ? null : openChatUserId ?? this.openChatUserId,
    );
  }
}
