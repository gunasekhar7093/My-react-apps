import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../../../core/constants/api_constants.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/socket_service.dart';
import '../../../core/services/notification_service.dart';
import '../../../core/storage/secure_storage_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/models/message_model.dart';
import '../../../data/models/user_model.dart';
import '../../../data/repositories/message_repository.dart';
import '../../dashboard/bloc/dashboard_bloc.dart';
import '../../dashboard/bloc/dashboard_event.dart';
import '../bloc/chat_bloc.dart';
import '../bloc/chat_event.dart';
import '../bloc/chat_state.dart';
import '../widgets/cached_media_image.dart';
import '../widgets/media_viewers.dart';
import '../../../core/services/media_cache_service.dart';
import '../../../core/services/presence_connection_service.dart';
import '../../../data/repositories/user_repository.dart';

class ChatPage extends StatefulWidget {
  final UserModel user;
  final String currentUserId;
  /// Shared socket from DashboardPage — ChatPage MUST NOT disconnect it.
  final SocketService socket;
  /// Reference to DashboardBloc so user:status events update the user list too.
  final DashboardBloc dashboardBloc;

  const ChatPage({
    super.key,
    required this.user,
    required this.currentUserId,
    required this.socket,
    required this.dashboardBloc,
  });
  @override State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  // We use the shared socket from DashboardPage — never create a new one here
  late final SocketService _socket;
  late final ChatBloc _bloc;
  final _apiClient = ApiClient();
  final _picker = ImagePicker();
  final _controller = TextEditingController();
  final _inputFocusNode = FocusNode();
  final _scrollController = ScrollController();
  String? _token;
  String? _currentUserName;
  /// Live-updated version of the chat partner (status changes update this)
  late UserModel _chatUser;

  @override void initState() {
    super.initState();
    _chatUser = widget.user;
    _socket = widget.socket;
    // Dismiss any notifications from this chat partner right upon entering
    NotificationService().cancelSenderNotification(widget.user.id);
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
    _bloc = ChatBloc(
      repository: MessageRepository(),
      socket: _socket,
      userId: widget.currentUserId,
      otherUserId: widget.user.id,
    )..add(const ChatStarted());
    PresenceConnectionService().reconnectCounter.addListener(_onPresenceRestored);
    _scrollController.addListener(_onScroll);
    _registerSocketCallbacks();
  }

  void _onPresenceRestored() {
    _refreshChatUserStatus();
  }

  void _refreshChatUserStatus() {
    UserRepository().getUsers().then((users) {
      if (!mounted) return;
      for (final u in users) {
        if (u.id == widget.user.id) {
          setState(() {
            _chatUser = u;
          });
          break;
        }
      }
    }).catchError((_) {});
  }

  void _onScroll() {
    if (_scrollController.hasClients) {
      // In reverse: true ListView, maxScrollExtent is the top of the chat (oldest messages)
      if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 250) {
        _bloc.add(const ChatLoadOlderMessagesRequested());
      }
    }
  }

  /// Register this page's callbacks on the already-connected shared socket.
  /// The socket is shared with DashboardPage — we only ADD our callbacks here
  /// and never call connect() or disconnect().
  void _registerSocketCallbacks() {
    _socket.addOnMessage((json) {
      if (!mounted) return;
      final msg = MessageModel.fromJson(json);
      final isThisChat = (msg.senderId == widget.user.id && msg.receiverId == widget.currentUserId) ||
          (msg.senderId == widget.currentUserId && msg.receiverId == widget.user.id);
      if (isThisChat) {
        if (msg.senderId == widget.user.id) {
          NotificationService().cancelSenderNotification(widget.user.id);
        }
        _bloc.add(ChatMessageReceived(msg));
        // Forward to DashboardBloc so its user list / unread logic stays in sync
        final createdAt = json['createdAt']?.toString() ?? '';
        final senderId = json['senderId']?.toString() ?? '';
        final receiverId = json['receiverId']?.toString() ?? '';
        if (senderId.isNotEmpty && receiverId.isNotEmpty && createdAt.isNotEmpty) {
          widget.dashboardBloc.add(DashboardPrivateMessageReceived(
            senderId: senderId,
            receiverId: receiverId,
            createdAt: createdAt,
            isIncoming: receiverId == widget.currentUserId,
          ));
        }
        if (_scrollController.hasClients && _scrollController.offset < 80) {
          _scrollToBottom();
        }
      }
    });

    _socket.addOnUserStatus(({required String userId, required String status, String? lastSeenAt}) {
      if (!mounted) return;
      // Update the live chat header if this is about our chat partner
      if (userId == widget.user.id) {
        setState(() {
          _chatUser = UserModel(
            id: _chatUser.id,
            name: _chatUser.name,
            username: _chatUser.username,
            phone: _chatUser.phone,
            status: status,
            lastSeenAt: lastSeenAt ?? _chatUser.lastSeenAt,
            latestMessageAt: _chatUser.latestMessageAt,
            unreadCount: _chatUser.unreadCount,
          );
        });
      }
      // Always forward to DashboardBloc so the user list stays current
      widget.dashboardBloc.add(DashboardUserStatusChanged(
        userId: userId,
        status: status,
        lastSeenAt: lastSeenAt,
      ));
    });

    _socket.addOnMessagesRead(({required String readerId, required String readAt}) {
      if (!mounted) return;
      if (readerId == widget.user.id) {
        _bloc.add(ChatMessagesReadReceived(readerId: readerId, readAt: readAt));
      }
    });

    _socket.addOnMessagesDelivered(({required String receiverId, required List<String> messageIds, required String deliveredAt}) {
      if (!mounted) return;
      if (receiverId == widget.user.id) {
        _bloc.add(ChatMessagesDeliveredReceived(
          receiverId: receiverId,
          messageIds: messageIds,
          deliveredAt: deliveredAt,
        ));
      }
    });

    _socket.addOnMessageDeleted((messageId) {
      if (!mounted) return;
      _bloc.add(ChatMessageDeletedReceived(messageId));
    });

    _socket.addOnConnect(_onSocketConnect);
  }

  void _onSocketConnect() {
    if (!mounted) return;
    _bloc.add(const ChatFlushPendingRequested());
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
    _scrollController.removeListener(_onScroll);
    PresenceConnectionService().reconnectCounter.removeListener(_onPresenceRestored);
    _controller.dispose();
    _inputFocusNode.dispose();
    _scrollController.dispose();
    // Remove our callbacks from the shared socket but DO NOT disconnect it —
    // the socket belongs to DashboardPage and must remain alive.
    _socket.removeOnMessage();
    _socket.removeOnUserStatus();
    _socket.removeOnMessagesRead();
    _socket.removeOnMessagesDelivered();
    _socket.removeOnMessageDeleted();
    _socket.removeOnConnect(_onSocketConnect);
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

  Future<void> _showMessageActionMenu(MessageModel message) async {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final canCopy = message.text.isNotEmpty || (message.mediaUrl != null && message.mediaUrl!.isNotEmpty);
    final isMine = message.senderId == widget.currentUserId;

    if (!canCopy && !isMine) return;

    // Immediately dismiss soft keyboard and disable focus requesting
    // to prevent keyboard from popping up after copying or unsending
    _inputFocusNode.unfocus();
    FocusManager.instance.primaryFocus?.unfocus();
    _inputFocusNode.canRequestFocus = false;

    String? selectedAction;
    try {
      selectedAction = await showModalBottomSheet<String>(
        context: context,
        backgroundColor: isDark ? const Color(0xFF1E2433) : Colors.white,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        builder: (sheetCtx) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 36,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                if (canCopy)
                  ListTile(
                    leading: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: AppTheme.primaryColor.withValues(alpha: 0.12),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.copy_rounded, color: AppTheme.primaryColor, size: 20),
                    ),
                    title: Text(
                      'Copy',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                        color: theme.colorScheme.onSurface,
                      ),
                    ),
                    onTap: () async {
                      Navigator.of(sheetCtx).pop('copy');
                      final textToCopy = message.text.isNotEmpty ? message.text : (message.mediaUrl ?? '');
                      if (textToCopy.isNotEmpty) {
                        await Clipboard.setData(ClipboardData(text: textToCopy));
                        HapticFeedback.lightImpact();
                      }
                    },
                  ),
                if (isMine)
                  ListTile(
                    leading: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.redAccent.withValues(alpha: 0.12),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.undo_rounded, color: Colors.redAccent, size: 20),
                    ),
                    title: const Text(
                      'Unsend',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                        color: Colors.redAccent,
                      ),
                    ),
                    onTap: () {
                      Navigator.of(sheetCtx).pop('unsend');
                    },
                  ),
              ],
            ),
          ),
        ),
      );
    } finally {
      if (selectedAction == 'unsend') {
        await _showUnsendConfirmationDialog(message);
      } else {
        _inputFocusNode.unfocus();
        FocusManager.instance.primaryFocus?.unfocus();
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            _inputFocusNode.unfocus();
            _inputFocusNode.canRequestFocus = true;
          }
        });
      }
    }
  }

  Future<void> _showUnsendConfirmationDialog(MessageModel message) async {
    final theme = Theme.of(context);

    // Keep keyboard dismissed and prevent auto-refocus
    _inputFocusNode.unfocus();
    FocusManager.instance.primaryFocus?.unfocus();
    _inputFocusNode.canRequestFocus = false;

    try {
      await showDialog<void>(
        context: context,
        builder: (dialogCtx) => AlertDialog(
          backgroundColor: theme.brightness == Brightness.dark
              ? theme.colorScheme.surfaceContainerHigh
              : Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Text(
            'Unsend this message?',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: theme.colorScheme.onSurface,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                _inputFocusNode.unfocus();
                Navigator.of(dialogCtx).pop();
              },
              child: Text(
                'Cancel',
                style: TextStyle(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            TextButton(
              onPressed: () {
                _inputFocusNode.unfocus();
                Navigator.of(dialogCtx).pop();
                _bloc.add(ChatMessageDeleteRequested(message.id));
              },
              child: const Text(
                'Unsend',
                style: TextStyle(
                  color: Colors.redAccent,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      );
    } finally {
      _inputFocusNode.unfocus();
      FocusManager.instance.primaryFocus?.unfocus();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _inputFocusNode.unfocus();
          _inputFocusNode.canRequestFocus = true;
        }
      });
    }
  }

  Future<void> _openAttachmentPicker() async {
    final theme = Theme.of(context);
    _inputFocusNode.unfocus();
    FocusManager.instance.primaryFocus?.unfocus();
    _inputFocusNode.canRequestFocus = false;

    try {
      await showModalBottomSheet<void>(
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
  } finally {
    _inputFocusNode.unfocus();
    FocusManager.instance.primaryFocus?.unfocus();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _inputFocusNode.unfocus();
        _inputFocusNode.canRequestFocus = true;
      }
    });
  }
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
    _inputFocusNode.unfocus();
    FocusManager.instance.primaryFocus?.unfocus();
    _inputFocusNode.canRequestFocus = false;

    try {
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

                                      final mediaUrl = uploadRes['mediaUrl']?.toString();
                                      if (mediaUrl != null && mediaUrl.isNotEmpty) {
                                        final fullUrl = mediaUrl.startsWith('http')
                                            ? mediaUrl
                                            : '${ApiConstants.baseUrl}$mediaUrl';
                                        MediaCacheService().cacheBytes(fullUrl, bytes);
                                      }

                                      _bloc.add(
                                        ChatMessageSendRequested(
                                          captionController.text.trim(),
                                          mediaUrl: mediaUrl,
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
  } finally {
    _inputFocusNode.unfocus();
    FocusManager.instance.primaryFocus?.unfocus();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _inputFocusNode.unfocus();
        _inputFocusNode.canRequestFocus = true;
      }
    });
  }
}

  @override Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final initial = _chatUser.name.isNotEmpty ? _chatUser.name[0].toUpperCase() : '?';
    final gradient = AppTheme.getAvatarGradient(_chatUser.id.isNotEmpty ? _chatUser.id : _chatUser.name);

    return BlocProvider.value(
      value: _bloc,
      child: Scaffold(
        appBar: AppBar(
          titleSpacing: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_rounded),
            onPressed: () => Navigator.of(context).pop(),
          ),
          title: ValueListenableBuilder<bool>(
            valueListenable: PresenceConnectionService().isPresenceLiveNotifier,
            builder: (context, isPresenceLive, _) {
              final isOnline = isPresenceLive && _chatUser.status == 'online';

              return Row(
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
                      if (isPresenceLive)
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
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _chatUser.name.isNotEmpty ? _chatUser.name : widget.user.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                        ),
                        if (isPresenceLive)
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
                                  _lastSeen(_chatUser.lastSeenAt),
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
              );
            },
          ),
        ),
        body: BlocConsumer<ChatBloc, ChatState>(
          listener: (context, state) {
            if (state.errorMessage != null && state.errorMessage!.isNotEmpty) {
              final msg = state.errorMessage!;
              final isTechnicalNetworkError = msg.contains('SocketException') ||
                  msg.contains('Failed host lookup') ||
                  msg.contains('ClientException') ||
                  msg.contains('HandshakeException') ||
                  msg.contains('OS Error');
              if (!isTechnicalNetworkError) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(msg),
                    backgroundColor: theme.colorScheme.error,
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              }
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

            return Column(
              children: [
                // Messages List View (reverse: true so latest messages appear at bottom without scrolling)
                Expanded(
                  child: GestureDetector(
                    behavior: HitTestBehavior.translucent,
                    onTap: () {
                      if (_inputFocusNode.hasFocus) {
                        _inputFocusNode.unfocus();
                      }
                    },
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
                          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                          padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
                          itemCount: state.messages.length + (state.loadingOlder ? 1 : 0),
                          itemBuilder: (context, index) {
                            if (index == state.messages.length) {
                              return const Padding(
                                padding: EdgeInsets.symmetric(vertical: 14),
                                child: Center(
                                  child: SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(strokeWidth: 2),
                                  ),
                                ),
                              );
                            }
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
                                  onLongPress: () => _showMessageActionMenu(current),
                                ),
                              ],
                            );
                          },
                        ),
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
                              focusNode: _inputFocusNode,
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

    final now = DateTime.now();
    final today    = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final dDate    = DateTime(d.year, d.month, d.day);

    final timeStr = DateFormat('hh:mm a').format(d);  // e.g. 09:36 PM

    if (dDate == today) {
      return 'Last seen today at $timeStr';
    } else if (dDate == yesterday) {
      return 'Last seen yesterday at $timeStr';
    } else {
      final dateStr = DateFormat('dd/MM/yyyy').format(d);  // e.g. 15/10/2026
      return 'Last seen $dateStr at $timeStr';
    }
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
            : DateFormat('dd/MM/yyyy').format(date);

    return Center(
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 12),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: theme.brightness == Brightness.dark
              ? theme.colorScheme.surfaceContainerHigh.withValues(alpha: 0.6)
              : const Color(0xFFEEF0F5),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: theme.brightness == Brightness.dark
                ? theme.colorScheme.onSurfaceVariant
                : const Color(0xFF7B8494),
            fontSize: 10,
            fontWeight: FontWeight.w700,
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
  final VoidCallback? onLongPress;

  const _Bubble({
    required this.message,
    required this.time,
    required this.mine,
    this.token,
    required this.senderName,
    this.avatarInitial,
    this.onLongPress,
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
    final fullMediaUrl = baseMediaUrl.isNotEmpty &&
            token != null &&
            token!.isNotEmpty &&
            !baseMediaUrl.contains('token=')
        ? (baseMediaUrl.contains('?') ? '$baseMediaUrl&token=$token' : '$baseMediaUrl?token=$token')
        : baseMediaUrl;

    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: GestureDetector(
        onLongPress: onLongPress,
        child: Container(
          constraints: BoxConstraints(maxWidth: maxWidth),
          margin: const EdgeInsets.only(bottom: 6),
        padding: hasMedia
            ? const EdgeInsets.all(5)
            : const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          gradient: mine
              ? const LinearGradient(
                  colors: [AppTheme.primaryColor, AppTheme.accentColor],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                )
              : null,
          color: mine
              ? null
              : (theme.brightness == Brightness.dark
                  ? theme.colorScheme.surfaceContainerHigh.withValues(alpha: 0.8)
                  : Colors.white),
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(mine ? 16 : 4),
            bottomRight: Radius.circular(mine ? 4 : 16),
          ),
          border: mine
              ? null
              : Border.all(
                  color: theme.brightness == Brightness.dark
                      ? Colors.white.withValues(alpha: 0.08)
                      : const Color(0xFFE6E8EE),
                  width: 1,
                ),
          boxShadow: [
            BoxShadow(
              color: mine
                  ? AppTheme.primaryColor.withValues(alpha: 0.16)
                  : Colors.black.withValues(alpha: 0.03),
              blurRadius: 4,
              offset: const Offset(0, 1.5),
            ),
          ],
        ),
        child: hasMedia
            ? _buildMediaBubble(context, theme, fullMediaUrl)
            : _buildTextBubble(context, theme, maxWidth - 24),
      ),
    ),
  );
  }

  Widget _buildTextBubble(BuildContext context, ThemeData theme, double contentMaxWidth) {
    final textColor = mine ? Colors.white : theme.colorScheme.onSurface;
    final textStyle = TextStyle(
      color: textColor,
      fontSize: 14,
      height: 1.35,
      letterSpacing: 0.1,
    );

    final timeWidget = Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        if (time.isNotEmpty)
          Text(
            time,
            style: TextStyle(
              color: mine
                  ? Colors.white.withValues(alpha: 0.72)
                  : (theme.brightness == Brightness.dark
                      ? Colors.white54
                      : const Color(0xFF9AA2B1)),
              fontSize: 10,
              fontWeight: FontWeight.w500,
            ),
          ),
        if (mine) ...[
          const SizedBox(width: 3.5),
          _StatusTicks(status: message.status),
        ],
      ],
    );

    // Measure text to decide whether it fits inline with time (compact pill matching web)
    final direction = Directionality.of(context);
    final textSpan = TextSpan(text: message.text, style: textStyle);
    final textPainter = TextPainter(
      text: textSpan,
      textDirection: direction,
    )..layout(maxWidth: contentMaxWidth);

    final timeSpan = TextSpan(
      text: '$time ${mine ? "   " : ""}',
      style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w500),
    );
    final timePainter = TextPainter(
      text: timeSpan,
      textDirection: direction,
    )..layout();
    final timeWidth = timePainter.width + (mine ? 18 : 6);

    final lineMetrics = textPainter.computeLineMetrics();
    final longestLineWidth = textPainter.width;
    final lastLineWidth = lineMetrics.isNotEmpty ? lineMetrics.last.width : textPainter.width;
    final lineCount = lineMetrics.length;
    final fitsOnLastLine = (lastLineWidth + 8 + timeWidth) <= contentMaxWidth;

    if (lineCount <= 1) {
      if (fitsOnLastLine) {
        // Single-line message: inline timestamp hugs the text snugly
        return Text.rich(
          TextSpan(
            children: [
              TextSpan(text: message.text, style: textStyle),
              WidgetSpan(
                alignment: PlaceholderAlignment.middle,
                child: Padding(
                  padding: const EdgeInsets.only(left: 7, bottom: 1),
                  child: timeWidget,
                ),
              ),
            ],
          ),
        );
      }
    } else {
      if (fitsOnLastLine) {
        // Multi-line message where last line has room:
        // Position timestamp at the bottom-right of the bubble on the last line,
        // so it doesn't float awkwardly in the middle next to a short word.
        final targetWidth = (longestLineWidth > (lastLineWidth + 8 + timeWidth)
                ? longestLineWidth
                : (lastLineWidth + 8 + timeWidth))
            .clamp(0.0, contentMaxWidth);

        return SizedBox(
          width: targetWidth,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Text(
                message.text,
                style: textStyle,
                textAlign: TextAlign.start,
              ),
              Positioned(
                right: 0,
                bottom: 0,
                child: timeWidget,
              ),
            ],
          ),
        );
      }
    }

    // When the last line is full (no room for timestamp on the last line),
    // drop the timestamp to a dedicated line below, aligned to the bottom-right.
    final bubbleWidth = (longestLineWidth > timeWidth ? longestLineWidth : timeWidth).clamp(0.0, contentMaxWidth);
    return SizedBox(
      width: bubbleWidth,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            message.text,
            style: textStyle,
            textAlign: TextAlign.start,
          ),
          const SizedBox(height: 2),
          Align(
            alignment: Alignment.bottomRight,
            child: timeWidget,
          ),
        ],
      ),
    );
  }

  Widget _buildMediaBubble(BuildContext context, ThemeData theme, String fullMediaUrl) {
    final textColor = mine ? Colors.white : theme.colorScheme.onSurface;
    final textStyle = TextStyle(
      color: textColor,
      fontSize: 14,
      height: 1.35,
      letterSpacing: 0.1,
    );

    final timeWidget = Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        if (time.isNotEmpty)
          Text(
            time,
            style: TextStyle(
              color: mine
                  ? Colors.white.withValues(alpha: 0.72)
                  : (theme.brightness == Brightness.dark
                      ? Colors.white54
                      : const Color(0xFF9AA2B1)),
              fontSize: 10,
              fontWeight: FontWeight.w500,
            ),
          ),
        if (mine) ...[
          const SizedBox(width: 3.5),
          _StatusTicks(status: message.status),
        ],
      ],
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
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
            child: CachedMediaImage(
              imageUrl: fullMediaUrl,
              fit: BoxFit.cover,
              width: double.infinity,
              height: 200,
              heroTag: 'media_${message.id}',
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        if (message.text.isNotEmpty)
          Align(
            alignment: Alignment.centerLeft,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 6, 8, 2),
              child: Text(
                message.text,
                style: textStyle,
                textAlign: TextAlign.start,
              ),
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 3, 6, 4),
          child: timeWidget,
        ),
      ],
    );
  }
}

/// WhatsApp-style message delivery & read status ticks
class _StatusTicks extends StatelessWidget {
  final MessageStatus status;

  const _StatusTicks({required this.status});

  @override
  Widget build(BuildContext context) {
    switch (status) {
      case MessageStatus.pending:
        // Clock Icon (🕒): Queued locally, waiting for internet connection
        return const Icon(
          Icons.access_time_rounded,
          size: 13,
          color: Color(0xFFB0B7C3),
        );
      case MessageStatus.sent:
        // One Gray Tick (✓): Sent to server, not yet reached recipient's device
        return const Icon(
          Icons.check_rounded,
          size: 13.5,
          color: Color(0xFFB0B7C3),
        );
      case MessageStatus.delivered:
        // Two Gray Ticks (✓✓): Delivered to recipient's device
        return const Icon(
          Icons.done_all_rounded,
          size: 14.5,
          color: Color(0xFFB0B7C3),
        );
      case MessageStatus.read:
        // Two White Ticks (✓✓): Recipient has opened and read the message
        return const Icon(
          Icons.done_all_rounded,
          size: 14.5,
          color: Colors.white,
        );
    }
  }
}