import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import '../../../core/network/socket_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/models/message_model.dart';
import '../../../data/models/user_model.dart';
import '../../../data/repositories/message_repository.dart';
import '../bloc/chat_bloc.dart';
import '../bloc/chat_event.dart';
import '../bloc/chat_state.dart';

class ChatPage extends StatefulWidget {
  final UserModel user;
  final String currentUserId;
  const ChatPage({super.key, required this.user, required this.currentUserId});
  @override State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  late final SocketService _socket;
  late final ChatBloc _bloc;
  final _controller = TextEditingController();
  final _scrollController = ScrollController();

  @override void initState() {
    super.initState();
    _socket = SocketService();
    _bloc = ChatBloc(
      repository: MessageRepository(),
      socket: _socket,
      userId: widget.currentUserId,
      otherUserId: widget.user.id,
    )..add(const ChatStarted());
    _connectSocket();
  }

  Future<void> _connectSocket() async {
    await _socket.connect(
      onUserStatus: ({required String userId, required String status, String? lastSeenAt}) {},
      onMessage: (json) {
        _bloc.add(ChatMessageReceived(MessageModel.fromJson(json)));
        if (_scrollController.hasClients && _scrollController.offset < 80) {
          _scrollToBottom();
        }
      },
    );
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          0,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
        );
      }
    });
  }

  @override void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    _socket.disconnect();
    _bloc.close();
    super.dispose();
  }

  void _send() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    _bloc.add(ChatMessageSendRequested(text));
    _controller.clear();
    _scrollToBottom();
  }

  @override Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isOnline = widget.user.status == 'online';
    final initial = widget.user.name.isNotEmpty ? widget.user.name[0].toUpperCase() : '?';
    final gradient = AppTheme.getAvatarGradient(widget.user.id.isNotEmpty ? widget.user.id : widget.user.name);

    return BlocProvider.value(
      value: _bloc,
      child: Scaffold(
        appBar: AppBar(
          titleSpacing: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_rounded),
            onPressed: () => Navigator.of(context).pop(),
          ),
          title: Row(
            children: [
              // Hero Avatar with Live Online Dot
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Hero(
                    tag: 'avatar_${widget.user.id}',
                    child: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(colors: gradient),
                        shape: BoxShape.circle,
                      ),
                      child: Center(
                        child: Text(
                          initial,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    right: -1,
                    bottom: -1,
                    child: Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        color: isOnline ? AppTheme.onlineColor : AppTheme.offlineColor,
                        shape: BoxShape.circle,
                        border: Border.all(color: theme.scaffoldBackgroundColor, width: 2),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 12),
              // Name and Presence
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.user.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                    ),
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
                          const SizedBox(width: 5),
                          const Text(
                            'Online now',
                            style: TextStyle(
                              color: AppTheme.onlineColor,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ] else
                          Text(
                            _lastSeen(widget.user.lastSeenAt),
                            style: TextStyle(
                              color: theme.colorScheme.onSurfaceVariant,
                              fontSize: 12,
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.refresh_rounded),
              tooltip: 'Refresh messages',
              onPressed: () => _bloc.add(const ChatStarted()),
            ),
            const SizedBox(width: 4),
          ],
        ),
        body: BlocBuilder<ChatBloc, ChatState>(
          builder: (context, state) {
            if (state.status == ChatStatus.loading && state.messages.isEmpty) {
              return const Center(
                child: SizedBox(
                  width: 30,
                  height: 30,
                  child: CircularProgressIndicator(strokeWidth: 2.5),
                ),
              );
            }

            if (state.status == ChatStatus.failure && state.messages.isEmpty) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.wifi_off_rounded, size: 40, color: theme.colorScheme.error),
                      const SizedBox(height: 12),
                      Text(
                        'Unable to load messages',
                        style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 16),
                      FilledButton.icon(
                        onPressed: () => _bloc.add(const ChatStarted()),
                        icon: const Icon(Icons.refresh_rounded),
                        label: const Text('Try Again'),
                      ),
                    ],
                  ),
                ),
              );
            }

            return Column(
              children: [
                // Messages List View (reverse: true so latest messages appear at bottom without scrolling)
                Expanded(
                  child: state.messages.isEmpty
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(32),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  width: 64,
                                  height: 64,
                                  decoration: BoxDecoration(
                                    color: theme.colorScheme.primary.withValues(alpha: 0.1),
                                    shape: BoxShape.circle,
                                  ),
                                  child: Icon(
                                    Icons.waving_hand_rounded,
                                    size: 32,
                                    color: theme.colorScheme.primary,
                                  ),
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  'Say hello to ${widget.user.name}!',
                                  style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  'No messages yet. Send a greeting to begin chatting.',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(color: theme.colorScheme.onSurfaceVariant, fontSize: 13),
                                ),
                              ],
                            ),
                          ),
                        )
                      : ListView.builder(
                          controller: _scrollController,
                          reverse: true,
                          padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
                          itemCount: state.messages.length,
                          itemBuilder: (context, index) {
                            // In reverse: true, index 0 is at the bottom (latest message)
                            final chronologicalIndex = state.messages.length - 1 - index;
                            final current = state.messages[chronologicalIndex];
                            final showDateHeader = chronologicalIndex == 0 ||
                                !_isSameDay(
                                  current.createdAt,
                                  state.messages[chronologicalIndex - 1].createdAt,
                                );

                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                if (showDateHeader)
                                  _DateBadge(dateString: current.createdAt),
                                _Bubble(
                                  text: current.text,
                                  time: _time(current.createdAt),
                                  mine: current.senderId == widget.currentUserId,
                                ),
                              ],
                            );
                          },
                        ),
                ),

                // Error feedback bar
                if (state.errorMessage != null)
                  Container(
                    margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.error.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.info_outline_rounded, size: 16, color: theme.colorScheme.error),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            state.errorMessage!,
                            style: TextStyle(color: theme.colorScheme.error, fontSize: 12),
                          ),
                        ),
                      ],
                    ),
                  ),

                // Floating Input Dock
                SafeArea(
                  top: false,
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                    decoration: BoxDecoration(
                      color: theme.scaffoldBackgroundColor,
                      border: Border(
                        top: BorderSide(
                          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
                          width: 0.8,
                        ),
                      ),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Container(
                            decoration: BoxDecoration(
                              color: theme.colorScheme.surfaceContainerHigh.withValues(alpha: 0.5),
                              borderRadius: BorderRadius.circular(24),
                            ),
                            child: TextField(
                              controller: _controller,
                              minLines: 1,
                              maxLines: 4,
                              textCapitalization: TextCapitalization.sentences,
                              onSubmitted: (_) => _send(),
                              decoration: InputDecoration(
                                hintText: 'Message ${widget.user.name}...',
                                hintStyle: TextStyle(
                                  color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                                  fontSize: 14,
                                ),
                                filled: false,
                                border: InputBorder.none,
                                enabledBorder: InputBorder.none,
                                focusedBorder: InputBorder.none,
                                contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        // Send Button
                        Container(
                          width: 46,
                          height: 46,
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [AppTheme.primaryColor, AppTheme.accentColor],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: AppTheme.primaryColor.withValues(alpha: 0.35),
                                blurRadius: 10,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: Material(
                            color: Colors.transparent,
                            child: InkWell(
                              onTap: state.sending ? null : _send,
                              borderRadius: BorderRadius.circular(23),
                              child: Center(
                                child: state.sending
                                    ? const SizedBox(
                                        width: 18,
                                        height: 18,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: Colors.white,
                                        ),
                                      )
                                    : const Icon(
                                        Icons.send_rounded,
                                        color: Colors.white,
                                        size: 20,
                                      ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  static bool _isSameDay(String date1Str, String date2Str) {
    final d1 = DateTime.tryParse(date1Str)?.toLocal();
    final d2 = DateTime.tryParse(date2Str)?.toLocal();
    if (d1 == null || d2 == null) return true;
    return d1.year == d2.year && d1.month == d2.month && d1.day == d2.day;
  }

  static String _time(String value) {
    final d = DateTime.tryParse(value)?.toLocal();
    return d == null ? '' : DateFormat('h:mm a').format(d);
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

class _DateBadge extends StatelessWidget {
  final String dateString;
  const _DateBadge({required this.dateString});

  @override Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final date = DateTime.tryParse(dateString)?.toLocal();
    if (date == null) return const SizedBox.shrink();

    final now = DateTime.now();
    final isToday = date.year == now.year && date.month == now.month && date.day == now.day;
    final isYesterday = date.year == now.year &&
        date.month == now.month &&
        date.day == now.subtract(const Duration(days: 1)).day;

    final label = isToday
        ? 'Today'
        : isYesterday
            ? 'Yesterday'
            : DateFormat('MMMM d, yyyy').format(date);

    return Center(
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 14),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHigh.withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: theme.colorScheme.onSurfaceVariant,
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  final String text;
  final String time;
  final bool mine;

  const _Bubble({
    required this.text,
    required this.time,
    required this.mine,
  });

  @override Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final maxWidth = MediaQuery.sizeOf(context).width * 0.78;

    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(maxWidth: maxWidth),
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.fromLTRB(14, 8, 12, 7),
        decoration: BoxDecoration(
          gradient: mine
              ? const LinearGradient(
                  colors: [AppTheme.primaryColor, AppTheme.accentColor],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                )
              : null,
          color: mine ? null : theme.colorScheme.surfaceContainerHigh.withValues(alpha: 0.8),
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(mine ? 16 : 4),
            bottomRight: Radius.circular(mine ? 4 : 16),
          ),
          boxShadow: [
            BoxShadow(
              color: mine
                  ? AppTheme.primaryColor.withValues(alpha: 0.16)
                  : Colors.black.withValues(alpha: 0.04),
              blurRadius: 4,
              offset: const Offset(0, 1.5),
            ),
          ],
        ),
        child: Wrap(
          alignment: WrapAlignment.end,
          crossAxisAlignment: WrapCrossAlignment.end,
          spacing: 8,
          runSpacing: 2,
          children: [
            Text(
              text,
              style: TextStyle(
                color: mine ? Colors.white : theme.colorScheme.onSurface,
                fontSize: 15,
                height: 1.3,
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(bottom: 1),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (time.isNotEmpty)
                    Text(
                      time,
                      style: TextStyle(
                        color: mine
                            ? Colors.white.withValues(alpha: 0.75)
                            : theme.colorScheme.onSurfaceVariant,
                        fontSize: 10,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  if (mine) ...[
                    const SizedBox(width: 4),
                    Icon(
                      Icons.done_all_rounded,
                      size: 13,
                      color: Colors.white.withValues(alpha: 0.85),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}