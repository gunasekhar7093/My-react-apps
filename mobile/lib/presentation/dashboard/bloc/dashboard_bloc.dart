import 'dart:async';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../data/repositories/user_repository.dart';
import 'dashboard_event.dart';
import 'dashboard_state.dart';
import '../../../data/models/user_model.dart';

class DashboardBloc extends Bloc<DashboardEvent, DashboardState> {
  final UserRepository repository;
  Timer? _refreshTimer;

  DashboardBloc({required this.repository}) : super(const DashboardState()) {
    on<DashboardStarted>(_onStarted);
    on<DashboardUsersRefreshRequested>(_onRefresh);
    on<DashboardSearchChanged>(_onSearchChanged);
    on<DashboardUserStatusChanged>(_onStatusChanged);
    on<DashboardPrivateMessageReceived>(_onPrivateMessageReceived);
  }

  Future<void> _onStarted(DashboardStarted event, Emitter<DashboardState> emit) async {
    if (state.users.isNotEmpty) return;
    await _loadUsers(emit, showLoading: true);
    _refreshTimer?.cancel();
    _refreshTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      add(const DashboardUsersRefreshRequested());
    });
  }

  Future<void> _onRefresh(DashboardUsersRefreshRequested event, Emitter<DashboardState> emit) async {
    await _loadUsers(emit, showLoading: event.showLoading);
  }

  Future<void> _loadUsers(Emitter<DashboardState> emit, {required bool showLoading}) async {
    if (showLoading) emit(state.copyWith(status: DashboardStatus.loading, errorMessage: null));
    try {
      final users = await repository.getUsers();
      if (_sameUsers(state.users, users)) {
        if (state.status != DashboardStatus.ready) {
          emit(state.copyWith(status: DashboardStatus.ready, errorMessage: null));
        }
        return;
      }
      emit(state.copyWith(status: DashboardStatus.ready, users: users, errorMessage: null));
    } catch (error) {
      emit(state.copyWith(
        status: state.users.isEmpty ? DashboardStatus.failure : DashboardStatus.ready,
        errorMessage: error.toString(),
      ));
    }
  }

  void _onSearchChanged(DashboardSearchChanged event, Emitter<DashboardState> emit) {
    emit(state.copyWith(searchQuery: event.query));
  }

  void _onStatusChanged(DashboardUserStatusChanged event, Emitter<DashboardState> emit) {
    final users = state.users.map((user) {
      if (user.id != event.userId) return user;
      return UserModel(
        id: user.id,
        name: user.name,
        username: user.username,
        phone: user.phone,
        status: event.status,
        lastSeenAt: event.lastSeenAt ?? user.lastSeenAt,
        latestMessageAt: user.latestMessageAt,
        unreadCount: user.unreadCount,
      );
    }).toList();
    emit(state.copyWith(users: users));
  }

  void _onPrivateMessageReceived(
    DashboardPrivateMessageReceived event,
    Emitter<DashboardState> emit,
  ) {
    final users = state.users.map((user) {
      if (user.id == event.senderId) {
        return UserModel(
          id: user.id,
          name: user.name,
          username: user.username,
          phone: user.phone,
          status: user.status,
          lastSeenAt: user.lastSeenAt,
          latestMessageAt: event.createdAt,
          unreadCount: event.isIncoming ? user.unreadCount + 1 : user.unreadCount,
        );
      }

      if (user.id == event.receiverId) {
        return UserModel(
          id: user.id,
          name: user.name,
          username: user.username,
          phone: user.phone,
          status: user.status,
          lastSeenAt: user.lastSeenAt,
          latestMessageAt: event.createdAt,
          unreadCount: user.unreadCount,
        );
      }

      return user;
    }).toList();

    emit(state.copyWith(users: users));
  }

  bool _sameUsers(List a, List b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i].id != b[i].id ||
          a[i].name != b[i].name ||
          a[i].username != b[i].username ||
          a[i].status != b[i].status ||
          a[i].lastSeenAt != b[i].lastSeenAt ||
          a[i].latestMessageAt != b[i].latestMessageAt ||
          a[i].unreadCount != b[i].unreadCount) {
        return false;
      }
    }
    return true;
  }

  @override
  Future<void> close() {
    _refreshTimer?.cancel();
    return super.close();
  }
}