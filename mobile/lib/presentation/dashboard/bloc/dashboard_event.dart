import 'package:equatable/equatable.dart';

abstract class DashboardEvent extends Equatable {
  const DashboardEvent();

  @override
  List<Object?> get props => [];
}

class DashboardStarted extends DashboardEvent {
  const DashboardStarted();
}

class DashboardUsersRefreshRequested extends DashboardEvent {
  final bool showLoading;

  const DashboardUsersRefreshRequested({this.showLoading = false});

  @override
  List<Object?> get props => [showLoading];
}

class DashboardSearchChanged extends DashboardEvent {
  final String query;

  const DashboardSearchChanged(this.query);

  @override
  List<Object?> get props => [query];
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

  @override
  List<Object?> get props => [userId, status, lastSeenAt];
}
