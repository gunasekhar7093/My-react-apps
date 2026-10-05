import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import '../../../core/network/socket_service.dart';
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
    _bloc = ChatBloc(repository: MessageRepository(), socket: _socket, userId: widget.currentUserId, otherUserId: widget.user.id)..add(const ChatStarted());
    _connectSocket();
  }

  Future<void> _connectSocket() async {
    await _socket.connect(
      onUserStatus: ({required String userId, required String status, String? lastSeenAt}) {},
      onMessage: (json) => _bloc.add(ChatMessageReceived(MessageModel.fromJson(json))),
    );
  }

  @override void dispose() { _controller.dispose(); _scrollController.dispose(); _socket.disconnect(); _bloc.close(); super.dispose(); }
  void _send() { final text = _controller.text.trim(); if (text.isEmpty) return; _bloc.add(ChatMessageSendRequested(text)); _controller.clear(); }

  @override Widget build(BuildContext context) {
    return BlocProvider.value(value: _bloc, child: Scaffold(
      appBar: AppBar(titleSpacing: 0, title: Row(children: [
        CircleAvatar(radius: 19, child: Text(widget.user.name.isEmpty ? '?' : widget.user.name[0].toUpperCase())),
        const SizedBox(width: 10), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(widget.user.name, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          Text(widget.user.status == 'online' ? 'Online now' : _lastSeen(widget.user.lastSeenAt), style: const TextStyle(fontSize: 12)),
        ])),
      ])),
      body: BlocBuilder<ChatBloc, ChatState>(builder: (context, state) {
        if (state.status == ChatStatus.loading && state.messages.isEmpty) return const Center(child: CircularProgressIndicator());
        if (state.status == ChatStatus.failure && state.messages.isEmpty) return Center(child: FilledButton.icon(onPressed: () => _bloc.add(const ChatStarted()), icon: const Icon(Icons.refresh), label: const Text('Try again')));
        return Column(children: [
          Expanded(child: ListView.builder(controller: _scrollController, padding: const EdgeInsets.fromLTRB(16, 18, 16, 12), itemCount: state.messages.length, itemBuilder: (_, index) {
            final m = state.messages[index];
            return _Bubble(text: m.text, time: _time(m.createdAt), mine: m.senderId == widget.currentUserId);
          })),
          if (state.errorMessage != null) Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: Text(state.errorMessage!, style: TextStyle(color: Theme.of(context).colorScheme.error))),
          SafeArea(top: false, child: Padding(padding: const EdgeInsets.fromLTRB(12, 8, 12, 12), child: Row(children: [
            Expanded(child: TextField(controller: _controller, minLines: 1, maxLines: 5, decoration: InputDecoration(hintText: 'Message ${widget.user.name}', filled: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none), contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12)))),
            const SizedBox(width: 8),
            IconButton.filled(onPressed: state.sending ? null : _send, icon: state.sending ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.send_rounded)),
          ]))),
        ]);
      }),
    ));
  }

  String _time(String value) { final d = DateTime.tryParse(value)?.toLocal(); return d == null ? '' : DateFormat('h:mm a').format(d); }
  String _lastSeen(String? value) {
    if (value == null || value.isEmpty) return 'Last seen recently';
    final d = DateTime.tryParse(value)?.toLocal(); if (d == null) return 'Last seen recently';
    final diff = DateTime.now().difference(d);
    if (diff.inMinutes < 1) return 'Last seen just now';
    if (diff.inMinutes < 60) return 'Last seen ${diff.inMinutes} min ago';
    if (diff.inHours < 24) return 'Last seen ${diff.inHours}h ago';
    return 'Last seen ${DateFormat('dd MMM, h:mm a').format(d)}';
  }
}

class _Bubble extends StatelessWidget {
  final String text; final String time; final bool mine;
  const _Bubble({required this.text, required this.time, required this.mine});
  @override Widget build(BuildContext context) {
    final color = mine ? Theme.of(context).colorScheme.primary : Theme.of(context).colorScheme.surfaceContainerHighest;
    final textColor = mine ? Theme.of(context).colorScheme.onPrimary : Theme.of(context).colorScheme.onSurfaceVariant;
    return Align(alignment: mine ? Alignment.centerRight : Alignment.centerLeft, child: Container(
      constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * .78),
      margin: const EdgeInsets.only(bottom: 8), padding: const EdgeInsets.fromLTRB(14, 10, 14, 8),
      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.only(topLeft: const Radius.circular(18), topRight: const Radius.circular(18), bottomLeft: Radius.circular(mine ? 18 : 4), bottomRight: Radius.circular(mine ? 4 : 18))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
        Align(alignment: Alignment.centerLeft, child: Text(text, style: TextStyle(color: textColor, fontSize: 15))),
        if (time.isNotEmpty) ...[const SizedBox(height: 3), Text(time, style: TextStyle(color: textColor.withValues(alpha: .72), fontSize: 10))],
      ]),
    ));
  }
}