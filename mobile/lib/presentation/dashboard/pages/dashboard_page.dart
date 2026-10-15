import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import '../../../core/network/socket_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/models/user_model.dart';
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

class _DashboardPageState extends State<DashboardPage> {
  late final DashboardBloc _bloc;
  late final SocketService _socket;
  final _search = TextEditingController();
  DashboardFilter _currentFilter = DashboardFilter.all;

  @override void initState() {
    super.initState();
    _bloc = DashboardBloc(repository: UserRepository())..add(const DashboardStarted());
    _socket = SocketService();
    _connectSocket();
  }

  Future<void> _connectSocket() async {
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

        _bloc.add(DashboardPrivateMessageReceived(
          senderId: senderId,
          receiverId: receiverId,
          createdAt: createdAt,
          isIncoming: receiverId == currentUserId,
        ));
      },
    );
  }

  Future<void> _openChat(UserModel user, String currentUserId) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ChatPage(user: user, currentUserId: currentUserId),
      ),
    );
    if (mounted) {
      _bloc.add(const DashboardUsersRefreshRequested());
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
              context.read<AuthBloc>().add(const LogoutRequested());
            },
            child: const Text('Sign Out'),
          ),
        ],
      ),
    );
  }

  @override void dispose() {
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

    return BlocProvider.value(
      value: _bloc,
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
              child: CustomScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
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
                            onChanged: (q) => context.read<DashboardBloc>().add(DashboardSearchChanged(q)),
                            decoration: InputDecoration(
                              hintText: 'Search people by name...',
                              prefixIcon: const Icon(Icons.search_rounded, size: 22),
                              suffixIcon: state.searchQuery.isEmpty
                                  ? null
                                  : IconButton(
                                      icon: const Icon(Icons.close_rounded, size: 20),
                                      onPressed: () {
                                        _search.clear();
                                        context.read<DashboardBloc>().add(const DashboardSearchChanged(''));
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
            );
          },
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
    final isOnline = user.status == 'online';
    final initial = user.name.isNotEmpty ? user.name[0].toUpperCase() : '?';
    final gradient = AppTheme.getAvatarGradient(user.id.isNotEmpty ? user.id : user.name);

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
  }

  static String _lastSeen(String? value) {
    if (value == null || value.isEmpty) return 'Last seen recently';
    final d = DateTime.tryParse(value)?.toLocal();
    if (d == null) return 'Last seen recently';
    final diff = DateTime.now().difference(d);
    if (diff.inMinutes < 1) return 'Last seen just now';
    if (diff.inMinutes < 60) return 'Last seen ${diff.inMinutes}m ago';
    if (diff.inHours < 24) return 'Last seen ${diff.inHours}h ago';
    return 'Last seen ${DateFormat('MMM d, h:mm a').format(d)}';
  }
}