abstract class DashboardEvent {
  const DashboardEvent();
}

class DashboardStarted extends DashboardEvent {
  const DashboardStarted();
}

class DashboardUsersRefreshRequested extends DashboardEvent {
  final bool showLoading;
  const DashboardUsersRefreshRequested({this.showLoading = false});
}

class DashboardSearchChanged extends DashboardEvent {
  final String query;
  const DashboardSearchChanged(this.query);
}

class DashboardUserStatusChanged extends DashboardEvent {
  final String userId;
  final String status;
  final String? lastSeenAt;

  const DashboardUserStatusChanged({
    required this.userId,
    required this.status,
    this.lastSeenAt,
  });
}

class DashboardPrivateMessageReceived extends DashboardEvent {
  final String senderId;
  final String receiverId;
  final String createdAt;

  const DashboardPrivateMessageReceived({
    required this.senderId,
    required this.receiverId,
    required this.createdAt,
  });
}