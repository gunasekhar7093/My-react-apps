import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import '../../../core/constants/api_constants.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/socket_service.dart';
import '../../../core/services/fcm_service.dart';
import '../../../core/services/local_storage_service.dart';
import '../../../core/services/notification_service.dart';
import '../../../core/services/presence_connection_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/models/message_model.dart';
import '../../../data/models/user_model.dart';
import '../../../data/repositories/message_repository.dart';
import '../../../data/repositories/user_repository.dart';
import '../../auth/bloc/auth_bloc.dart';
import '../../auth/bloc/auth_event.dart';
import '../bloc/dashboard_bloc.dart';
import '../bloc/dashboard_event.dart';
import '../bloc/dashboard_state.dart';
import '../../chat/pages/chat_page.dart';

enum DashboardFilter { all, online, unread }

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});
  @override State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> with WidgetsBindingObserver {
  late final DashboardBloc _bloc;
  late final SocketService _socket;
  final _search = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  final _apiClient = ApiClient();
  DashboardFilter _currentFilter = DashboardFilter.all;

  @override void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _searchFocusNode.addListener(_onSearchFocusChanged);
    _bloc = DashboardBloc(repository: UserRepository())..add(const DashboardStarted());
    _socket = SocketService();
    PresenceConnectionService().initialize(_socket);
    PresenceConnectionService().reconnectCounter.addListener(_onPresenceRestored);
    NotificationService().initialize(
      onSelectUser: (userId) {
        if (!mounted) return;
        NotificationService().cancelSenderNotification(userId);
        final currentUserId = context.read<AuthBloc>().state.user?.id;
        if (currentUserId == null) return;
        final user = _findOrBuildUser(userId);
        _openChat(user, currentUserId);
      },
    );
    FcmService().initialize(
      onOpenChat: (userId) {
        if (!mounted) return;
        NotificationService().cancelSenderNotification(userId);
        final currentUserId = context.read<AuthBloc>().state.user?.id;
        if (currentUserId == null) return;
        final user = _findOrBuildUser(userId);
        _openChat(user, currentUserId);
      },
    );
    FcmService().registerDeviceToken();
    _connectSocket();
  }

  void _onSearchFocusChanged() {
    if (mounted) setState(() {});
  }

  void _onPresenceRestored() async {
    if (mounted) {
      await _flushPendingReadReceipts();
      if (mounted) {
        _bloc.add(const DashboardUsersRefreshRequested());
      }
    }
  }

  /// Finds user in bloc list or constructs a fallback model
  UserModel _findOrBuildUser(String userId, [String? fallbackName]) {
    try {
      return _bloc.state.users.firstWhere((u) => u.id == userId);
    } catch (_) {
      final name = (fallbackName != null && fallbackName.isNotEmpty) ? fallbackName : 'User';
      return UserModel(
        id: userId,
        name: name,
        username: name.toLowerCase().replaceAll(' ', ''),
        phone: '',
        status: 'online',
        unreadCount: 1,
      );
    }
  }

  /// Triggers a WhatsApp-like notification (system heads-up + in-app banner)
  void _handleIncomingNotification(Map<String, dynamic> message, String currentUserId) {
    final senderId = message['senderId']?.toString() ?? '';
    if (senderId.isEmpty) return;

    final rawSenderName = message['senderName']?.toString();
    final user = _findOrBuildUser(senderId, rawSenderName);
    final senderName = (rawSenderName != null && rawSenderName.isNotEmpty)
        ? rawSenderName
        : (user.name.isNotEmpty ? user.name : user.username);

    final text = message['text']?.toString() ?? '';
    final mediaType = message['mediaType']?.toString();
    final messageId = message['id']?.toString();

    List<String>? historicalLines;
    final rawLines = message['unreadLines'];
    if (rawLines is List) {
      historicalLines = rawLines.map((e) => e.toString()).toList();
    }

    // WhatsApp-like heads-up system notification
    NotificationService().showMessageNotification(
      senderId: senderId,
      senderName: senderName,
      messageText: text,
      messageId: messageId,
      mediaType: mediaType,
      historicalLines: historicalLines,
    );
  }

  /// Called by Flutter when the app lifecycle changes.
  /// We use this to proactively signal online/offline so other users see
  /// the change instantly instead of waiting for ping/pong timeout.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    switch (state) {
      case AppLifecycleState.resumed:
        // App came to foreground — signal online immediately
        _updateStatus('online');
        break;
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
      case AppLifecycleState.hidden:
        // App went to background or is being closed — signal offline immediately
        _updateStatus('offline');
        break;
      case AppLifecycleState.inactive:
        // Brief inactive state (e.g. notification shade opened) — ignore
        break;
    }
  }

  /// Calls /api/me/status to instantly broadcast the user's status to all others.
  /// This is the proactive signal — the socket ping/pong is just a fallback.
  Future<void> _updateStatus(String status) async {
    try {
      await _apiClient.post(
        ApiConstants.meStatus,
        body: {'status': status},
        authenticated: true,
      );
    } catch (_) {
      // Silently ignore — the ping/pong fallback will catch any missed update.
    }
  }

  bool _isFlushingPending = false;
  Future<void> _flushAllPendingMessages() async {
    if (!_socket.isConnected || _isFlushingPending) return;
    _isFlushingPending = true;
    try {
      final openChatId = _bloc.state.openChatUserId;
      final localStorage = LocalStorageService();
      final allPending = await localStorage.getPendingMessages();
      if (allPending.isEmpty) return;

      for (final pending in allPending) {
        if (!_socket.isConnected) break;
        // Never touch messages belonging to currently open chat — ChatBloc handles its own open chat!
        if (openChatId != null && (pending.receiverId == openChatId || pending.senderId == openChatId)) {
          continue;
        }
        if (localStorage.isMessageInFlight(pending.id)) continue;
        localStorage.markMessageInFlight(pending.id);
        try {
          final res = await _socket.sendMessage(
            receiverId: pending.receiverId,
            text: pending.text,
            clientTempId: pending.id,
            createdAt: pending.createdAt,
            mediaUrl: pending.mediaUrl,
            mediaType: pending.mediaType,
            mediaName: pending.mediaName,
            mediaSize: pending.mediaSize,
          );
          final confirmedRaw = res['message'];
          if (confirmedRaw is Map) {
            final confirmed = MessageModel.fromJson(Map<String, dynamic>.from(confirmedRaw));
            await localStorage.replacePendingMessage(
              pending.senderId,
              pending.receiverId,
              pending.id,
              confirmed,
            );
          }
        } catch (_) {
          break;
        } finally {
          localStorage.clearMessageInFlight(pending.id);
        }
      }
    } finally {
      _isFlushingPending = false;
    }
  }

  Future<void> _preSyncRecentConversations() async {
    try {
      final currentUserId = context.read<AuthBloc>().state.user?.id;
      if (currentUserId == null || currentUserId.isEmpty) return;
      final users = _bloc.state.users;
      final activeUsers = users
          .where((u) => u.latestMessageAt != null && u.latestMessageAt!.isNotEmpty)
          .toList()
        ..sort((a, b) => (b.latestMessageAt ?? '').compareTo(a.latestMessageAt ?? ''));
      final topUsers = activeUsers.take(4).toList();
      for (final otherUser in topUsers) {
        MessageRepository()
            .getMessages(userId: currentUserId, otherUserId: otherUser.id)
            .catchError((_) => const MessagesResult(messages: []));
      }
    } catch (_) {}
  }

  bool _isFlushingReadReceipts = false;

  Future<void> _flushPendingReadReceipts() async {
    if (_isFlushingReadReceipts) return;
    _isFlushingReadReceipts = true;
    try {
      final currentUserId = context.read<AuthBloc>().state.user?.id;
      if (currentUserId == null || currentUserId.isEmpty) return;
      final pendingPartners = await MessageRepository().getPendingReadReceipts();
      if (pendingPartners.isEmpty) return;

      for (final partnerId in pendingPartners) {
        if (_socket.isConnected) {
          _socket.emitMessagesRead(partnerId);
        }
        try {
          await ApiClient().post(
            '/api/messages/$currentUserId/$partnerId/read',
            authenticated: true,
          );
          await MessageRepository().removePendingReadReceipt(partnerId);
          if (mounted) {
            _bloc.add(DashboardUserUnreadCleared(partnerId));
          }
        } catch (_) {}
      }
    } catch (_) {} finally {
      _isFlushingReadReceipts = false;
    }
  }

  Future<void> _connectSocket() async {
    _socket.addOnConnect(() {
      _flushAllPendingMessages();
      _flushPendingReadReceipts();
      _preSyncRecentConversations();
    });
    await _socket.connect(
      onUserStatus: ({required String userId, required String status, String? lastSeenAt}) {
        if (mounted) {
          _bloc.add(DashboardUserStatusChanged(userId: userId, status: status, lastSeenAt: lastSeenAt));
        }
      },
      onMessage: (message) {
        final senderId = message['senderId']?.toString();
        final receiverId = message['receiverId']?.toString();
        final createdAt = message['createdAt']?.toString();
        final currentUserId = context.read<AuthBloc>().state.user?.id;
        if (!mounted ||
            senderId == null ||
            receiverId == null ||
            createdAt == null ||
            currentUserId == null) {
          return;
        }

        final isIncoming = receiverId == currentUserId;

        // If a chat is not open or not with this sender/receiver, update DashboardBloc state
        if (_bloc.state.openChatUserId == null ||
            (_bloc.state.openChatUserId != senderId && _bloc.state.openChatUserId != receiverId)) {
          _bloc.add(DashboardPrivateMessageReceived(
            senderId: senderId,
            receiverId: receiverId,
            createdAt: createdAt,
            isIncoming: isIncoming,
          ));
        }

        // WhatsApp notification: trigger when received message from someone else and user is not looking at their chat
        if (isIncoming && senderId != currentUserId && _bloc.state.openChatUserId != senderId) {
          _handleIncomingNotification(message, currentUserId);
        }
      },
    );
  }

  Future<void> _openChat(UserModel user, String currentUserId) async {
    // Proactively unfocus search bar before opening chat so Flutter route focus manager
    // does not restore focus and pop up the keyboard when returning to the dashboard.
    _searchFocusNode.unfocus();
    FocusScope.of(context).unfocus();

    // If a chat is already open (e.g. tapping banner to switch conversations), pop it first
    if (_bloc.state.openChatUserId != null) {
      Navigator.of(context).popUntil((route) => route.isFirst);
    }

    // Dismiss notifications for this user when opening their chat
    NotificationService().cancelSenderNotification(user.id);

    // Suppress any new notifications while this chat is on screen
    NotificationService().openChatUserId = user.id;

    // Tell the bloc the chat is open so unread badges are suppressed
    _bloc.add(DashboardOpenChatChanged(user.id));
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ChatPage(
          user: user,
          currentUserId: currentUserId,
          socket: _socket,
          dashboardBloc: _bloc,
        ),
      ),
    );
    // Chat closed — re-enable notifications, unfocus search bar, and refresh user list
    NotificationService().openChatUserId = null;
    if (mounted) {
      _searchFocusNode.unfocus();
      FocusScope.of(context).unfocus();
      _bloc
        ..add(const DashboardOpenChatChanged(null))
        ..add(const DashboardUsersRefreshRequested());
    }
  }

  void _confirmLogout() {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Sign Out'),
        content: const Text('Are you sure you want to sign out of ChatSpace?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
              foregroundColor: Colors.white,
            ),
            onPressed: () {
              Navigator.of(ctx).pop();
              NotificationService().cancelAllNotifications();
              _socket.disconnect();
              context.read<AuthBloc>().add(const LogoutRequested());
            },
            child: const Text('Sign Out'),
          ),
        ],
      ),
    );
  }

  @override void dispose() {
    _searchFocusNode.removeListener(_onSearchFocusChanged);
    _searchFocusNode.dispose();
    WidgetsBinding.instance.removeObserver(this);
    PresenceConnectionService().reconnectCounter.removeListener(_onPresenceRestored);
    _search.dispose();
    _socket.disconnect();
    _bloc.close();
    super.dispose();
  }

  @override Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final me = context.select((AuthBloc b) => b.state.user);
    final initial = me?.name.isNotEmpty == true ? me!.name[0].toUpperCase() : '?';
    final myGradient = AppTheme.getAvatarGradient(me?.id ?? me?.name ?? '');

    final canPopScope = !_searchFocusNode.hasFocus && _search.text.isEmpty;

    return BlocProvider.value(
      value: _bloc,
      child: BlocListener<DashboardBloc, DashboardState>(
        listenWhen: (previous, current) =>
            previous.users.isEmpty && current.users.isNotEmpty,
        listener: (context, state) {
          _preSyncRecentConversations();
        },
        child: PopScope(
          canPop: canPopScope,
          onPopInvokedWithResult: (didPop, _) {
            if (didPop) return;
            if (_searchFocusNode.hasFocus) {
              _searchFocusNode.unfocus();
            }
            if (_search.text.isNotEmpty) {
              _search.clear();
              context.read<DashboardBloc>().add(const DashboardSearchChanged(''));
            }
            setState(() {});
          },
          child: Scaffold(
        appBar: AppBar(
          title: Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [AppTheme.primaryColor, AppTheme.accentColor],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.chat_bubble_rounded, color: Colors.white, size: 18),
              ),
              const SizedBox(width: 12),
              const Text('ChatSpace', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 20)),
            ],
          ),
          actions: [
            // Current User Avatar
            Tooltip(
              message: me?.name ?? 'My Profile',
              child: Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  gradient: LinearGradient(colors: myGradient),
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: Text(
                    initial,
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 14),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            // Logout Action
            IconButton(
              icon: const Icon(Icons.logout_rounded, size: 22),
              tooltip: 'Sign Out',
              onPressed: _confirmLogout,
            ),
            const SizedBox(width: 8),
          ],
        ),
        body: BlocBuilder<DashboardBloc, DashboardState>(
          builder: (context, state) {
            // Apply chip filter on top of search filtered users
            final displayUsers = state.filteredUsers.where((u) {
              if (_currentFilter == DashboardFilter.online) return u.status == 'online';
              if (_currentFilter == DashboardFilter.unread) return u.unreadCount > 0;
              return true;
            }).toList();

            return RefreshIndicator(
              onRefresh: () async {
                context.read<DashboardBloc>().add(const DashboardUsersRefreshRequested());
                await Future<void>.delayed(const Duration(milliseconds: 300));
              },
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTap: () {
                  if (_searchFocusNode.hasFocus) {
                    _searchFocusNode.unfocus();
                  }
                },
                child: NotificationListener<ScrollNotification>(
                  onNotification: (notification) {
                    if (notification is ScrollStartNotification && _searchFocusNode.hasFocus) {
                      _searchFocusNode.unfocus();
                    }
                    return false;
                  },
                  child: CustomScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                    slivers: [
                  // Header Bar & Search Box
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Online Status Chips Row
                          Row(
                            children: [
                              Text(
                                'Messages',
                                style: theme.textTheme.headlineSmall?.copyWith(
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: -0.5,
                                ),
                              ),
                              const Spacer(),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                decoration: BoxDecoration(
                                  color: AppTheme.onlineColor.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Container(
                                      width: 7,
                                      height: 7,
                                      decoration: const BoxDecoration(
                                        color: AppTheme.onlineColor,
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      '${state.onlineCount} online',
                                      style: const TextStyle(
                                        color: AppTheme.onlineColor,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),

                          // Search Bar
                          TextField(
                            controller: _search,
                            focusNode: _searchFocusNode,
                            onChanged: (q) {
                              setState(() {});
                              context.read<DashboardBloc>().add(DashboardSearchChanged(q));
                            },
                            decoration: InputDecoration(
                              hintText: 'Search people by name...',
                              prefixIcon: const Icon(Icons.search_rounded, size: 22),
                              suffixIcon: state.searchQuery.isEmpty
                                  ? null
                                  : IconButton(
                                      icon: const Icon(Icons.close_rounded, size: 20),
                                      onPressed: () {
                                        _search.clear();
                                        _searchFocusNode.unfocus();
                                        context.read<DashboardBloc>().add(const DashboardSearchChanged(''));
                                        setState(() {});
                                      },
                                    ),
                            ),
                          ),
                          const SizedBox(height: 12),

                          // Filter Chips
                          SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: Row(
                              children: [
                                _FilterChip(
                                  label: 'All (${state.users.length})',
                                  selected: _currentFilter == DashboardFilter.all,
                                  onSelected: () => setState(() => _currentFilter = DashboardFilter.all),
                                ),
                                const SizedBox(width: 8),
                                _FilterChip(
                                  label: 'Online (${state.onlineCount})',
                                  selected: _currentFilter == DashboardFilter.online,
                                  onSelected: () => setState(() => _currentFilter = DashboardFilter.online),
                                ),
                                const SizedBox(width: 8),
                                _FilterChip(
                                  label: 'Unread',
                                  selected: _currentFilter == DashboardFilter.unread,
                                  onSelected: () => setState(() => _currentFilter = DashboardFilter.unread),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  // Content States
                  if (state.status == DashboardStatus.loading && state.users.isEmpty)
                    const SliverFillRemaining(
                      child: Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            SizedBox(width: 32, height: 32, child: CircularProgressIndicator(strokeWidth: 3)),
                            SizedBox(height: 16),
                            Text('Loading conversations...'),
                          ],
                        ),
                      ),
                    )
                  else if (state.status == DashboardStatus.failure && state.users.isEmpty)
                    SliverFillRemaining(
                      child: Center(
                        child: Padding(
                          padding: const EdgeInsets.all(32),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 68,
                                height: 68,
                                decoration: BoxDecoration(
                                  color: theme.colorScheme.error.withValues(alpha: 0.1),
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(Icons.wifi_off_rounded, size: 32, color: theme.colorScheme.error),
                              ),
                              const SizedBox(height: 18),
                              Text(
                                'Connection Offline',
                                style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                "Unable to reach ChatSpace. Please check your network or try again.",
                                textAlign: TextAlign.center,
                                style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                              ),
                              const SizedBox(height: 20),
                              FilledButton.icon(
                                onPressed: () => context.read<DashboardBloc>().add(
                                  const DashboardUsersRefreshRequested(showLoading: true),
                                ),
                                icon: const Icon(Icons.refresh_rounded, size: 18),
                                label: const Text('Try Again'),
                              ),
                            ],
                          ),
                        ),
                      ),
                    )
                  else if (displayUsers.isEmpty)
                    SliverFillRemaining(
                      child: Center(
                        child: Padding(
                          padding: const EdgeInsets.all(32),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 64,
                                height: 64,
                                decoration: BoxDecoration(
                                  color: theme.colorScheme.surfaceContainerHigh,
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(
                                  Icons.search_off_rounded,
                                  size: 32,
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                              const SizedBox(height: 16),
                              Text(
                                'No people found',
                                style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                state.searchQuery.isNotEmpty
                                    ? 'No contacts matching "${state.searchQuery}"'
                                    : 'There are no other registered users yet.',
                                textAlign: TextAlign.center,
                                style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                              ),
                            ],
                          ),
                        ),
                      ),
                    )
                  else
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                      sliver: SliverList.builder(
                        itemCount: displayUsers.length,
                        itemBuilder: (context, i) {
                          final user = displayUsers[i];
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: _UserCard(
                              user: user,
                              currentUserId: me?.id,
                              onTap: me?.id == null ? null : () => _openChat(user, me!.id),
                            ),
                          );
                        },
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    ),
    ),
    ),
    ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onSelected;

  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onSelected,
  });

  @override Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onSelected,
      borderRadius: BorderRadius.circular(20),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: selected
              ? theme.colorScheme.primary
              : theme.colorScheme.surfaceContainerHigh.withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? theme.colorScheme.onPrimary : theme.colorScheme.onSurfaceVariant,
            fontSize: 13,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
      ),
    );
  }
}

class _UserCard extends StatelessWidget {
  final String? currentUserId;
  final UserModel user;
  final VoidCallback? onTap;

  const _UserCard({
    required this.user,
    this.currentUserId,
    this.onTap,
  });

  @override Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final initial = user.name.isNotEmpty ? user.name[0].toUpperCase() : '?';
    final gradient = AppTheme.getAvatarGradient(user.id.isNotEmpty ? user.id : user.name);

    return ValueListenableBuilder<bool>(
      valueListenable: PresenceConnectionService().isPresenceLiveNotifier,
      builder: (context, isPresenceLive, _) {
        final isOnline = isPresenceLive && user.status == 'online';

        return Material(
          color: theme.cardTheme.color,
          shape: theme.cardTheme.shape,
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  // Avatar with Hero and Live Presence Indicator
                  Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Hero(
                        tag: 'avatar_${user.id}',
                        child: Container(
                          width: 52,
                          height: 52,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: gradient,
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: gradient[0].withValues(alpha: 0.25),
                                blurRadius: 8,
                                offset: const Offset(0, 3),
                              ),
                            ],
                          ),
                          child: Center(
                            child: Text(
                              initial,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 20,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                      ),
                      if (isPresenceLive)
                        Positioned(
                          right: 0,
                          bottom: 0,
                          child: Container(
                            width: 14,
                            height: 14,
                            decoration: BoxDecoration(
                              color: isOnline ? AppTheme.onlineColor : AppTheme.offlineColor,
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: theme.scaffoldBackgroundColor,
                                width: 2.5,
                              ),
                              boxShadow: isOnline
                                  ? [
                                      BoxShadow(
                                        color: AppTheme.onlineColor.withValues(alpha: 0.45),
                                        blurRadius: 4,
                                      ),
                                    ]
                                  : null,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(width: 14),

                  // Contact Name & Status
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          user.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                            letterSpacing: -0.2,
                          ),
                        ),
                        if (isPresenceLive) ...[
                          const SizedBox(height: 3),
                          Row(
                            children: [
                              if (isOnline) ...[
                                Container(
                                  width: 6,
                                  height: 6,
                                  decoration: const BoxDecoration(
                                    color: AppTheme.onlineColor,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                const Text(
                                  'Online now',
                                  style: TextStyle(
                                    color: AppTheme.onlineColor,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ] else
                                Expanded(
                                  child: Text(
                                    _lastSeen(user.lastSeenAt),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: theme.colorScheme.onSurfaceVariant,
                                      fontSize: 12,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),

                  // Trailing unread badge & chevron
                  if (user.unreadCount > 0)
                    Container(
                      margin: const EdgeInsets.only(right: 6),
                      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primary,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        user.unreadCount > 99 ? '99+' : '${user.unreadCount}',
                        style: TextStyle(
                          color: theme.colorScheme.onPrimary,
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  Icon(
                    Icons.chevron_right_rounded,
                    color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
                    size: 22,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  static String _lastSeen(String? value) {
    if (value == null || value.isEmpty) return 'Last seen recently';
    final d = DateTime.tryParse(value)?.toLocal();
    if (d == null) return 'Last seen recently';

    final now = DateTime.now();
    final today     = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final dDate     = DateTime(d.year, d.month, d.day);

    final timeStr = DateFormat('hh:mm a').format(d);

    if (dDate == today) {
      return 'Last seen today at $timeStr';
    } else if (dDate == yesterday) {
      return 'Last seen yesterday at $timeStr';
    } else {
      final dateStr = DateFormat('dd/MM/yyyy').format(d);
      return 'Last seen $dateStr at $timeStr';
    }
  }
}