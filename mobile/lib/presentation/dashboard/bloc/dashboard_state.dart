import '../../../data/models/user_model.dart';

enum DashboardStatus { initial, loading, ready, failure }

class DashboardState {
  final DashboardStatus status;
  final List<UserModel> users;
  final String searchQuery;
  final String? errorMessage;

  const DashboardState({
    this.status = DashboardStatus.initial,
    this.users = const [],
    this.searchQuery = '',
    this.errorMessage,
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
  }) {
    return DashboardState(
      status: status ?? this.status,
      users: users ?? this.users,
      searchQuery: searchQuery ?? this.searchQuery,
      errorMessage: errorMessage,
    );
  }
}
