import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import '../../../core/network/socket_service.dart';
import '../../../data/models/user_model.dart';
import '../../../data/repositories/user_repository.dart';
import '../../auth/bloc/auth_bloc.dart';
import '../../auth/bloc/auth_event.dart';
import '../bloc/dashboard_bloc.dart';
import '../bloc/dashboard_event.dart';
import '../bloc/dashboard_state.dart';
import '../../chat/pages/chat_page.dart';

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});
  @override State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  late final DashboardBloc _bloc;
  late final SocketService _socket;
  final _search = TextEditingController();

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
        if (!mounted || senderId == null || receiverId == null || createdAt == null) return;
        _bloc.add(DashboardPrivateMessageReceived(
          senderId: senderId,
          receiverId: receiverId,
          createdAt: createdAt,
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

  @override void dispose() { _search.dispose(); _socket.disconnect(); _bloc.close(); super.dispose(); }

  @override Widget build(BuildContext context) {
    final me = context.select((AuthBloc b) => b.state.user);
    final initial = me?.name.isNotEmpty == true ? me!.name[0].toUpperCase() : '?';
    return BlocProvider.value(value: _bloc, child: Scaffold(
      appBar: AppBar(title: const Text('ChatSpace', style: TextStyle(fontWeight: FontWeight.w700)),
        actions: [CircleAvatar(radius: 18, child: Text(initial)), const SizedBox(width: 8),
          IconButton(onPressed: () => context.read<AuthBloc>().add(const LogoutRequested()), icon: const Icon(Icons.logout_rounded)), const SizedBox(width: 8)]),
      body: BlocBuilder<DashboardBloc, DashboardState>(builder: (context, state) => RefreshIndicator(
        onRefresh: () async { context.read<DashboardBloc>().add(const DashboardUsersRefreshRequested()); await Future<void>.delayed(const Duration(milliseconds: 300)); },
        child: CustomScrollView(physics: const AlwaysScrollableScrollPhysics(), slivers: [
          SliverToBoxAdapter(child: Padding(padding: const EdgeInsets.fromLTRB(20, 20, 20, 8), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('People', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 4), Text('${state.users.length} people · ${state.onlineCount} online'), const SizedBox(height: 16),
            TextField(controller: _search, onChanged: (q) => context.read<DashboardBloc>().add(DashboardSearchChanged(q)),
              decoration: InputDecoration(hintText: 'Search by name or email', prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: state.searchQuery.isEmpty ? null : IconButton(onPressed: () { _search.clear(); context.read<DashboardBloc>().add(const DashboardSearchChanged('')); }, icon: const Icon(Icons.close_rounded)),
                filled: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none))),
          ]))),
          if (state.status == DashboardStatus.loading && state.users.isEmpty) const SliverFillRemaining(child: Center(child: CircularProgressIndicator()))
          else if (state.status == DashboardStatus.failure && state.users.isEmpty) SliverFillRemaining(child: Center(child: FilledButton.icon(onPressed: () => context.read<DashboardBloc>().add(const DashboardUsersRefreshRequested(showLoading: true)), icon: const Icon(Icons.refresh), label: const Text('Try again'))))
          else if (state.filteredUsers.isEmpty) const SliverFillRemaining(child: Center(child: Text('No people found')))
          else SliverPadding(padding: const EdgeInsets.fromLTRB(20, 8, 20, 24), sliver: SliverList.builder(itemCount: state.filteredUsers.length, itemBuilder: (context, i) {
            final user = state.filteredUsers[i];
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _UserCard(
                user: user,
                currentUserId: me?.id,
                onTap: me?.id == null ? null : () => _openChat(user, me!.id),
              ),
            );
          })),
        ]),
      )),
    ));
  }
}

class _UserCard extends StatelessWidget {
  final String? currentUserId;
  final UserModel user;
  final VoidCallback? onTap;
  const _UserCard({required this.user, this.currentUserId, this.onTap});
  @override Widget build(BuildContext context) {
    final theme = Theme.of(context); final online = user.status == 'online';
    final initial = user.name.isNotEmpty ? user.name[0].toUpperCase() : '?';
    return Card(child: ListTile(leading: Stack(children: [CircleAvatar(radius: 26, child: Text(initial)), Positioned(right: 0, bottom: 0, child: Container(width: 13, height: 13, decoration: BoxDecoration(color: online ? Colors.green : theme.colorScheme.outlineVariant, shape: BoxShape.circle, border: Border.all(color: theme.colorScheme.surface, width: 2))))]),
      title: Row(children: [Expanded(child: Text(user.name, maxLines: 1, overflow: TextOverflow.ellipsis)), if (user.unreadCount > 0) Padding(padding: const EdgeInsets.only(left: 8), child: Badge(label: Text(user.unreadCount > 99 ? '99+' : '${user.unreadCount}')))]),
      subtitle: Text(online ? 'Online now' : _lastSeen(user.lastSeenAt)), trailing: const Icon(Icons.chevron_right_rounded),
      onTap: onTap));
  }
  static String _lastSeen(String? value) {
    if (value == null || value.isEmpty) return 'Last seen recently'; final d = DateTime.tryParse(value)?.toLocal(); if (d == null) return 'Last seen recently';
    final diff = DateTime.now().difference(d); if (diff.inMinutes < 1) return 'Last seen just now'; if (diff.inMinutes < 60) return 'Last seen ${diff.inMinutes} min ago'; if (diff.inHours < 24) return 'Last seen ${diff.inHours}h ago';
    return 'Last seen ${DateFormat('dd MMM, h:mm a').format(d)}';
  }
}