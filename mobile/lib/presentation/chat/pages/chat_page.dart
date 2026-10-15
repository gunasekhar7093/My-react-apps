import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../../../core/constants/api_constants.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/socket_service.dart';
import '../../../core/storage/secure_storage_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/models/message_model.dart';
import '../../../data/models/user_model.dart';
import '../../../data/repositories/message_repository.dart';
import '../bloc/chat_bloc.dart';
import '../bloc/chat_event.dart';
import '../bloc/chat_state.dart';
import '../widgets/media_viewers.dart';

class ChatPage extends StatefulWidget {
  final UserModel user;
  final String currentUserId;
  const ChatPage({super.key, required this.user, required this.currentUserId});
  @override State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  late final SocketService _socket;
  late final ChatBloc _bloc;
  final _apiClient = ApiClient();
  final _picker = ImagePicker();
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  String? _token;
  String? _currentUserName;

  @override void initState() {
    super.initState();
    SecureStorageService().getToken().then((val) {
      if (mounted) setState(() => _token = val);
    });
    SecureStorageService().getUser().then((val) {
      if (val != null) {
        try {
          final data = jsonDecode(val);
          if (mounted) {
            setState(() {
              _currentUserName = data['name']?.toString() ?? data['username']?.toString();
            });
          }
        } catch (_) {}
      }
    });
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

  void _openAttachmentPicker() {
    final theme = Theme.of(context);
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: theme.scaffoldBackgroundColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: theme.colorScheme.outlineVariant,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Share Media',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _MediaOptionItem(
                      icon: Icons.camera_alt_rounded,
                      label: 'Camera',
                      gradient: const [Color(0xFFEF4444), Color(0xFFF97316)],
                      onTap: () {
                        Navigator.of(ctx).pop();
                        _pickMedia(ImageSource.camera, isVideo: false);
                      },
                    ),
                    _MediaOptionItem(
                      icon: Icons.photo_library_rounded,
                      label: 'Photos',
                      gradient: const [Color(0xFF6366F1), Color(0xFF8B5CF6)],
                      onTap: () {
                        Navigator.of(ctx).pop();
                        _pickMedia(ImageSource.gallery, isVideo: false);
                      },
                    ),
                    _MediaOptionItem(
                      icon: Icons.videocam_rounded,
                      label: 'Record Video',
                      gradient: const [Color(0xFFEC4899), Color(0xFFF43F5E)],
                      onTap: () {
                        Navigator.of(ctx).pop();
                        _pickMedia(ImageSource.camera, isVideo: true);
                      },
                    ),
                    _MediaOptionItem(
                      icon: Icons.video_collection_rounded,
                      label: 'Videos',
                      gradient: const [Color(0xFF10B981), Color(0xFF06B6D4)],
                      onTap: () {
                        Navigator.of(ctx).pop();
                        _pickMedia(ImageSource.gallery, isVideo: true);
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 12),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _pickMedia(ImageSource source, {required bool isVideo}) async {
    try {
      final XFile? file = isVideo
          ? await _picker.pickVideo(source: source)
          : await _picker.pickImage(source: source, imageQuality: 85);

      if (file == null || !mounted) return;
      _showMediaPreviewAndSend(file, isVideo: isVideo);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not select media: $e'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    }
  }

  Future<void> _showMediaPreviewAndSend(XFile file, {required bool isVideo}) async {
    final bytes = await file.readAsBytes();
    if (!mounted) return;

    final captionController = TextEditingController();
    final theme = Theme.of(context);

    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: theme.scaffoldBackgroundColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) {
        bool uploading = false;
        String? uploadError;

        return StatefulBuilder(
          builder: (context, setModalState) {
            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom,
                left: 16,
                right: 16,
                top: 16,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        isVideo ? 'Send Video' : 'Send Photo',
                        style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close_rounded),
                        onPressed: uploading ? null : () => Navigator.of(sheetContext).pop(),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  // Preview Container
                  ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: Container(
                      height: 220,
                      color: Colors.black12,
                      child: isVideo
                          ? Stack(
                              fit: StackFit.expand,
                              children: [
                                Container(
                                  decoration: const BoxDecoration(
                                    gradient: LinearGradient(
                                      colors: [Color(0xFF1E1E2E), Color(0xFF121218)],
                                      begin: Alignment.topCenter,
                                      end: Alignment.bottomCenter,
                                    ),
                                  ),
                                  child: Center(
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.all(16),
                                          decoration: BoxDecoration(
                                            color: Colors.white.withValues(alpha: 0.15),
                                            shape: BoxShape.circle,
                                          ),
                                          child: const Icon(Icons.videocam_rounded, size: 40, color: Colors.white),
                                        ),
                                        const SizedBox(height: 12),
                                        Padding(
                                          padding: const EdgeInsets.symmetric(horizontal: 16),
                                          child: Text(
                                            file.name,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          _formatBytes(bytes.length),
                                          style: const TextStyle(color: Colors.white70, fontSize: 11),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            )
                          : Image.memory(
                              bytes,
                              fit: BoxFit.cover,
                              width: double.infinity,
                            ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (uploadError != null) ...[
                    Text(
                      uploadError!,
                      style: TextStyle(color: theme.colorScheme.error, fontSize: 12),
                    ),
                    const SizedBox(height: 8),
                  ],
                  // Caption Input & Send Button
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: captionController,
                          enabled: !uploading,
                          textCapitalization: TextCapitalization.sentences,
                          decoration: InputDecoration(
                            hintText: 'Add a caption...',
                            filled: true,
                            fillColor: theme.colorScheme.surfaceContainerHigh.withValues(alpha: 0.5),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(20),
                              borderSide: BorderSide.none,
                            ),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        width: 44,
                        height: 44,
                        decoration: const BoxDecoration(
                          gradient: LinearGradient(
                            colors: [AppTheme.primaryColor, AppTheme.accentColor],
                          ),
                          shape: BoxShape.circle,
                        ),
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            borderRadius: BorderRadius.circular(22),
                            onTap: uploading
                                ? null
                                : () async {
                                    setModalState(() {
                                      uploading = true;
                                      uploadError = null;
                                    });
                                    try {
                                      final mimeType = file.mimeType ?? _lookupMimeType(file.name, isVideo: isVideo);
                                      final uploadRes = await _apiClient.uploadMedia(
                                        bytes: bytes,
                                        filePath: file.path,
                                        filename: file.name,
                                        mimeType: mimeType,
                                      );

                                      if (sheetContext.mounted) {
                                        Navigator.of(sheetContext).pop();
                                      }

                                      _bloc.add(
                                        ChatMessageSendRequested(
                                          captionController.text.trim(),
                                          mediaUrl: uploadRes['mediaUrl']?.toString(),
                                          mediaType: uploadRes['mediaType']?.toString() ?? (isVideo ? 'video' : 'image'),
                                          mediaName: uploadRes['mediaName']?.toString() ?? file.name,
                                          mediaSize: uploadRes['mediaSize'] is int ? uploadRes['mediaSize'] as int : bytes.length,
                                        ),
                                      );
                                      _scrollToBottom();
                                    } catch (err) {
                                      setModalState(() {
                                        uploading = false;
                                        uploadError = 'Upload failed: $err';
                                      });
                                    }
                                  },
                            child: Center(
                              child: uploading
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white,
                                      ),
                                    )
                                  : const Icon(Icons.send_rounded, color: Colors.white, size: 20),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                ],
              ),
            );
          },
        );
      },
    );
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
                            'Online',
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
        ),
        body: BlocConsumer<ChatBloc, ChatState>(
          listener: (context, state) {
            if (state.errorMessage != null && state.errorMessage!.isNotEmpty) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(state.errorMessage!),
                  backgroundColor: theme.colorScheme.error,
                  behavior: SnackBarBehavior.floating,
                ),
              );
            }
          },
          builder: (context, state) {
            if (state.status == ChatStatus.loading && state.messages.isEmpty) {
              return const Center(
                child: SizedBox(
                  width: 32,
                  height: 32,
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
                                  'No messages yet. Send a greeting or photo to begin chatting.',
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
                            final chronologicalIndex = state.messages.length - 1 - index;
                            final current = state.messages[chronologicalIndex];
                            final showDateHeader = chronologicalIndex == 0 ||
                                !_isSameDay(
                                  current.createdAt,
                                  state.messages[chronologicalIndex - 1].createdAt,
                                );

                            final isMine = current.senderId == widget.currentUserId;
                            final senderName = isMine ? 'You' : widget.user.name;
                            final avatarInitial = isMine
                                ? (_currentUserName != null && _currentUserName!.isNotEmpty
                                    ? _currentUserName![0].toUpperCase()
                                    : 'Y')
                                : (widget.user.name.isNotEmpty ? widget.user.name[0].toUpperCase() : '?');

                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                if (showDateHeader)
                                  _DateBadge(dateString: current.createdAt),
                                _Bubble(
                                  message: current,
                                  time: _time(current.createdAt),
                                  mine: isMine,
                                  token: _token,
                                  senderName: senderName,
                                  avatarInitial: avatarInitial,
                                ),
                              ],
                            );
                          },
                        ),
                ),

                // Floating Input Dock
                SafeArea(
                  top: false,
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(12, 8, 16, 12),
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
                        // Media Attachment Button
                        IconButton(
                          icon: Icon(
                            Icons.add_circle_outline_rounded,
                            color: theme.colorScheme.primary,
                            size: 26,
                          ),
                          tooltip: 'Share photo or video',
                          onPressed: _openAttachmentPicker,
                        ),
                        const SizedBox(width: 4),
                        // Text Input
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

  static String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  static String _lookupMimeType(String filename, {required bool isVideo}) {
    final dotIndex = filename.lastIndexOf('.');
    final ext = dotIndex != -1 ? filename.substring(dotIndex + 1).toLowerCase() : '';
    switch (ext) {
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'png':
        return 'image/png';
      case 'gif':
        return 'image/gif';
      case 'webp':
        return 'image/webp';
      case 'bmp':
        return 'image/bmp';
      case 'heic':
        return 'image/heic';
      case 'heif':
        return 'image/heif';
      case 'mp4':
        return 'video/mp4';
      case 'mov':
        return 'video/quicktime';
      case 'mkv':
        return 'video/x-matroska';
      case 'webm':
        return 'video/webm';
      case '3gp':
        return 'video/3gpp';
      case 'avi':
        return 'video/x-msvideo';
      case 'm4v':
        return 'video/x-m4v';
      default:
        return isVideo ? 'video/mp4' : 'image/jpeg';
    }
  }
}

class _MediaOptionItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final List<Color> gradient;
  final VoidCallback onTap;

  const _MediaOptionItem({
    required this.icon,
    required this.label,
    required this.gradient,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
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
                    color: gradient[0].withValues(alpha: 0.35),
                    blurRadius: 8,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: Icon(icon, color: Colors.white, size: 26),
            ),
            const SizedBox(height: 8),
            Text(
              label,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
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
  final MessageModel message;
  final String time;
  final bool mine;
  final String? token;
  final String senderName;
  final String? avatarInitial;

  const _Bubble({
    required this.message,
    required this.time,
    required this.mine,
    this.token,
    required this.senderName,
    this.avatarInitial,
  });

  @override Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final maxWidth = MediaQuery.sizeOf(context).width * 0.78;

    final hasMedia = message.isMedia;
    final mediaUrl = message.mediaUrl;
    final baseMediaUrl = mediaUrl != null && mediaUrl.isNotEmpty
        ? (mediaUrl.startsWith('http')
            ? mediaUrl
            : (mediaUrl.startsWith('/')
                ? '${ApiConstants.baseUrl}$mediaUrl'
                : '${ApiConstants.baseUrl}/$mediaUrl'))
        : '';
    final fullMediaUrl = baseMediaUrl.isNotEmpty && token != null && token!.isNotEmpty && !baseMediaUrl.contains('token=')
        ? (baseMediaUrl.contains('?') ? '$baseMediaUrl&token=$token' : '$baseMediaUrl?token=$token')
        : baseMediaUrl;

    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(maxWidth: maxWidth),
        margin: const EdgeInsets.only(bottom: 6),
        padding: hasMedia
            ? const EdgeInsets.all(5)
            : const EdgeInsets.fromLTRB(14, 8, 12, 7),
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
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Media Content (Image or Video)
            if (hasMedia) ...[
              if (message.isVideo)
                VideoPlayerBubble(
                  videoUrl: fullMediaUrl,
                  filename: message.mediaName,
                  fileSize: message.mediaSize,
                  onTap: () {
                    Navigator.of(context).push(
                      FullScreenVideoViewer.route(
                        videoUrl: fullMediaUrl,
                        title: message.mediaName,
                        senderName: senderName,
                        senderId: message.senderId,
                        timestamp: message.createdAt,
                        caption: message.text,
                        avatarInitial: avatarInitial,
                      ),
                    );
                  },
                )
              else
                GestureDetector(
                  onTap: () {
                    Navigator.of(context).push(
                      FullScreenImageViewer.route(
                        imageUrl: fullMediaUrl,
                        title: message.mediaName,
                        heroTag: 'media_${message.id}',
                        senderName: senderName,
                        senderId: message.senderId,
                        timestamp: message.createdAt,
                        caption: message.text,
                        avatarInitial: avatarInitial,
                      ),
                    );
                  },
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Hero(
                      tag: 'media_${message.id}',
                      child: Image.network(
                        fullMediaUrl,
                        fit: BoxFit.cover,
                        width: double.infinity,
                        height: 200,
                        loadingBuilder: (context, child, progress) {
                          if (progress == null) return child;
                          return Container(
                            height: 180,
                            color: Colors.black12,
                            child: const Center(
                              child: SizedBox(
                                width: 28,
                                height: 28,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              ),
                            ),
                          );
                        },
                        errorBuilder: (context, error, stackTrace) => Container(
                          height: 140,
                          color: Colors.black12,
                          child: const Center(
                            child: Icon(Icons.broken_image_rounded, size: 40, color: Colors.grey),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],

            // Caption or Text
            if (message.text.isNotEmpty)
              Padding(
                padding: EdgeInsets.fromLTRB(
                  hasMedia ? 8 : 0,
                  hasMedia ? 6 : 0,
                  hasMedia ? 8 : 0,
                  0,
                ),
                child: Text(
                  message.text,
                  style: TextStyle(
                    color: mine ? Colors.white : theme.colorScheme.onSurface,
                    fontSize: 15,
                    height: 1.3,
                  ),
                ),
              ),

            // Time & Ticks Row
            Padding(
              padding: EdgeInsets.fromLTRB(
                hasMedia ? 8 : 0,
                4,
                hasMedia ? 6 : 0,
                hasMedia ? 4 : 0,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.end,
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