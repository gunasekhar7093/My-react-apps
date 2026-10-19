import 'dart:async';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../data/repositories/user_repository.dart';
import 'dashboard_event.dart';
import 'dashboard_state.dart';
import '../../../data/models/user_model.dart';

class DashboardBloc extends Bloc<DashboardEvent, DashboardState> {
  final UserRepository repository;
  Timer? _refreshTimer;
  final List<DashboardPrivateMessageReceived> _pendingMessages = [];

  DashboardBloc({required this.repository}) : super(const DashboardState()) {
    on<DashboardStarted>(_onStarted);
    on<DashboardUsersRefreshRequested>(_onRefresh);
    on<DashboardSearchChanged>(_onSearchChanged);
    on<DashboardUserStatusChanged>(_onStatusChanged);
    on<DashboardPrivateMessageReceived>(_onPrivateMessageReceived);
    on<DashboardUnreadCountReconciled>(_onUnreadCountReconciled);
    on<DashboardOpenChatChanged>(_onOpenChatChanged);
    on<DashboardUserUnreadCleared>(_onUserUnreadCleared);
  }

  Future<void> _onStarted(DashboardStarted event, Emitter<DashboardState> emit) async {
    final cached = await repository.getCachedUsers();
    if (cached.isNotEmpty && state.users.isEmpty) {
      emit(state.copyWith(status: DashboardStatus.ready, users: cached, errorMessage: null));
    }
    await _loadUsers(emit, showLoading: state.users.isEmpty);
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
      final pendingPartners = await repository.localStorage.getPendingReadReceipts();
      final adjustedUsers = users.map((u) {
        if (u.id == state.openChatUserId || pendingPartners.contains(u.id)) {
          return u.copyWith(unreadCount: 0);
        }
        return u;
      }).toList();

      if (_sameUsers(state.users, adjustedUsers)) {
        if (state.status != DashboardStatus.ready) {
          emit(state.copyWith(status: DashboardStatus.ready, errorMessage: null));
        }
        _replayPendingMessages(emit);
        return;
      }
      emit(state.copyWith(status: DashboardStatus.ready, users: adjustedUsers, errorMessage: null));
      _replayPendingMessages(emit);
    } catch (error) {
      emit(state.copyWith(
        status: state.users.isEmpty ? DashboardStatus.failure : DashboardStatus.ready,
        errorMessage: state.users.isEmpty ? error.toString() : null,
      ));
    }
  }

  void _replayPendingMessages(Emitter<DashboardState> emit) {
    if (_pendingMessages.isEmpty || state.users.isEmpty) return;

    final pending = List<DashboardPrivateMessageReceived>.from(_pendingMessages);
    _pendingMessages.clear();

    final incomingBySender = <String, int>{};
    for (final event in pending) {
      // Don't increment unread for the chat that's currently open
      if (event.isIncoming && event.senderId != state.openChatUserId) {
        incomingBySender[event.senderId] =
            (incomingBySender[event.senderId] ?? 0) + 1;
      }
    }

    if (incomingBySender.isEmpty) return;

    final users = state.users.map((user) {
      final pendingCount = incomingBySender[user.id] ?? 0;
      if (pendingCount == 0) return user;

      return UserModel(
        id: user.id,
        name: user.name,
        username: user.username,
        phone: user.phone,
        status: user.status,
        lastSeenAt: user.lastSeenAt,
        latestMessageAt: user.latestMessageAt,
        unreadCount: user.unreadCount + pendingCount,
      );
    }).toList();

    emit(state.copyWith(users: users));
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
    if (state.users.isEmpty) {
      _pendingMessages.add(event);
      return;
    }

    // Determine the "other" user's id from our perspective
    // isIncoming=true  → senderId is the other user
    // isIncoming=false → receiverId is the other user (we sent it)
    final otherUserId = event.isIncoming ? event.senderId : event.receiverId;

    // If the chat for this user is currently open, the user is actively reading
    // — do NOT increment the unread badge, just update latestMessageAt.
    final chatIsOpen = state.openChatUserId == otherUserId;

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
          unreadCount: (event.isIncoming && !chatIsOpen)
              ? user.unreadCount + 1
              : user.unreadCount,
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
    repository.saveCachedUsers(users);

    // If this contact does not exist in our local contact list yet, refresh user list immediately
    final exists = state.users.any((u) => u.id == otherUserId);
    if (!exists) {
      add(const DashboardUsersRefreshRequested());
    } else if (event.isIncoming && !chatIsOpen) {
      // Only reconcile with server when a badge was actually incremented
      _reconcileUnreadCount(event.senderId);
    }
  }

  /// Called when the user opens or closes a chat screen.
  void _onOpenChatChanged(DashboardOpenChatChanged event, Emitter<DashboardState> emit) {
    final openUserId = event.openUserId;

    if (openUserId == null) {
      // Chat closed — clear the tracking so future messages behave normally
      emit(state.copyWith(clearOpenChatUserId: true));
      return;
    }

    // Chat opened — zero out the unread count for this user immediately in state and persistent disk cache!
    final users = state.users.map((user) {
      if (user.id != openUserId) return user;
      return user.copyWith(unreadCount: 0);
    }).toList();

    emit(state.copyWith(users: users, openChatUserId: openUserId));
    repository.saveCachedUsers(users);
    repository.zeroUnreadCount(openUserId);
  }

  void _onUserUnreadCleared(
    DashboardUserUnreadCleared event,
    Emitter<DashboardState> emit,
  ) {
    if (isClosed) return;
    final users = state.users.map((user) {
      if (user.id != event.userId) return user;
      return user.copyWith(unreadCount: 0);
    }).toList();
    emit(state.copyWith(users: users));
    repository.saveCachedUsers(users);
    repository.zeroUnreadCount(event.userId);
  }

  Future<void> _reconcileUnreadCount(String senderId) async {
    try {
      final latestUsers = await repository.getUsers();
      final serverUser = latestUsers.cast<UserModel?>().firstWhere(
        (user) => user?.id == senderId,
        orElse: () => null,
      );
      if (serverUser == null || isClosed) return;

      final currentUser = state.users.cast<UserModel?>().firstWhere(
        (user) => user?.id == senderId,
        orElse: () => null,
      );
      if (currentUser == null) return;

      add(DashboardUnreadCountReconciled(serverUser));
    } catch (_) {
      // The local +1 update already gives immediate feedback.
    }
  }

  void _onUnreadCountReconciled(
    DashboardUnreadCountReconciled event,
    Emitter<DashboardState> emit,
  ) {
    if (isClosed) return;

    // Don't overwrite the unread count if the chat is currently open
    // (it was already zeroed out by _onOpenChatChanged)
    if (state.openChatUserId == event.user.id) return;

    final users = state.users.map((user) {
      if (user.id != event.user.id) return user;

      return UserModel(
        id: user.id,
        name: user.name,
        username: user.username,
        phone: user.phone,
        status: event.user.status,
        lastSeenAt: event.user.lastSeenAt,
        latestMessageAt: event.user.latestMessageAt ?? user.latestMessageAt,
        unreadCount: event.user.unreadCount > user.unreadCount
            ? event.user.unreadCount
            : user.unreadCount,
      );
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
    _pendingMessages.clear();
    return super.close();
  }
}
