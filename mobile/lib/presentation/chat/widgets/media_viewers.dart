import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:gal/gal.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:video_player/video_player.dart';

import '../../../core/services/media_cache_service.dart';
import '../../../core/theme/app_theme.dart';

/// Helper to download media file and save directly to device Gallery & Google Photos.
Future<void> _downloadMediaFile({
  required BuildContext context,
  required String url,
  String? filename,
  required bool isVideo,
}) async {
  try {
    // 1. Check or request gallery permissions using Gal
    final hasAccess = await Gal.hasAccess();
    if (!hasAccess) {
      final granted = await Gal.requestAccess();
      if (!granted) {
        throw Exception('Permission to access photo gallery was denied.');
      }
    }

    // 2. Fetch the file bytes (check local offline cache first!)
    final cached = await MediaCacheService().getCachedFile(url);
    final List<int> bytes;
    if (cached != null) {
      bytes = await cached.readAsBytes();
    } else {
      final uri = Uri.parse(url);
      final response = await http.get(uri);
      if (response.statusCode != 200) {
        throw Exception('Server returned status code ${response.statusCode}');
      }
      bytes = response.bodyBytes;
      await MediaCacheService().cacheBytes(url, bytes);
    }

    // 3. Determine clean filename
    final ext = isVideo ? 'mp4' : 'jpg';
    String cleanName = (filename != null && filename.trim().isNotEmpty)
        ? filename.trim().replaceAll(RegExp(r'[\\/:*?"<>|]'), '_')
        : '';
    if (cleanName.isEmpty) {
      cleanName = 'ChatSpace_${DateTime.now().millisecondsSinceEpoch}.$ext';
    } else if (!cleanName.contains('.')) {
      cleanName = '$cleanName.$ext';
    }

    // 4. Save to temporary directory first
    final tempDir = await getTemporaryDirectory();
    final tempFilePath = '${tempDir.path}/$cleanName';
    final tempFile = File(tempFilePath);
    await tempFile.writeAsBytes(bytes);

    // 5. Register with native Android/iOS MediaStore & save into device Gallery / Google Photos
    if (isVideo) {
      await Gal.putVideo(tempFilePath, album: 'ChatSpace');
    } else {
      await Gal.putImage(tempFilePath, album: 'ChatSpace');
    }

    // 6. Also keep a copy in system Downloads folder on Android for Files app access
    try {
      if (Platform.isAndroid) {
        final downloadDir = Directory('/storage/emulated/0/Download');
        if (await downloadDir.exists()) {
          final downloadFilePath = '${downloadDir.path}/$cleanName';
          final downloadFile = File(downloadFilePath);
          if (!await downloadFile.exists()) {
            await downloadFile.writeAsBytes(bytes);
          }
        }
      }
    } catch (_) {}

    // 7. Clean up temporary cache file
    try {
      if (await tempFile.exists()) {
        await tempFile.delete();
      }
    } catch (_) {}

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.check_circle_rounded, color: Colors.white, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  isVideo
                      ? 'Video saved to Gallery & Google Photos!'
                      : 'Photo saved to Gallery & Google Photos!',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          backgroundColor: const Color(0xFF10B981),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 3),
        ),
      );
    }
  } on GalException catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.error_outline_rounded, color: Colors.white, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Gallery error: ${e.type.message}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white),
                ),
              ),
            ],
          ),
          backgroundColor: const Color(0xFFEF4444),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.error_outline_rounded, color: Colors.white, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Download failed: $e',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white),
                ),
              ),
            ],
          ),
          backgroundColor: const Color(0xFFEF4444),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }
}

/// Full screen Instagram-style image preview with sender info, download button, caption bar, instant backdrop dismiss, and pinch-to-zoom.
class FullScreenImageViewer extends StatefulWidget {
  final String imageUrl;
  final String? title;
  final String heroTag;
  final String senderName;
  final String senderId;
  final String timestamp;
  final String? caption;
  final String? avatarInitial;

  const FullScreenImageViewer({
    super.key,
    required this.imageUrl,
    this.title,
    required this.heroTag,
    required this.senderName,
    required this.senderId,
    required this.timestamp,
    this.caption,
    this.avatarInitial,
  });

  /// Custom scale-in animation route matching Instagram DM photo preview.
  static Route<void> route({
    required String imageUrl,
    String? title,
    required String heroTag,
    required String senderName,
    required String senderId,
    required String timestamp,
    String? caption,
    String? avatarInitial,
  }) {
    return PageRouteBuilder<void>(
      opaque: false,
      barrierColor: Colors.black.withValues(alpha: 0.94),
      barrierDismissible: true,
      transitionDuration: const Duration(milliseconds: 220),
      reverseTransitionDuration: const Duration(milliseconds: 180),
      pageBuilder: (context, animation, secondaryAnimation) {
        return FullScreenImageViewer(
          imageUrl: imageUrl,
          title: title,
          heroTag: heroTag,
          senderName: senderName,
          senderId: senderId,
          timestamp: timestamp,
          caption: caption,
          avatarInitial: avatarInitial,
        );
      },
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: const Cubic(0.18, 0.89, 0.32, 1.15),
          reverseCurve: Curves.easeInCubic,
        );
        return FadeTransition(
          opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.92, end: 1.0).animate(curved),
            child: child,
          ),
        );
      },
    );
  }

  static String formatTimestamp(String? isoString) {
    if (isoString == null || isoString.isEmpty) return '';
    final dt = DateTime.tryParse(isoString)?.toLocal();
    if (dt == null) return isoString;
    return DateFormat('dd MMM • h:mm a').format(dt);
  }

  @override
  State<FullScreenImageViewer> createState() => _FullScreenImageViewerState();
}

class _FullScreenImageViewerState extends State<FullScreenImageViewer> {
  bool _downloading = false;
  File? _cachedFile;

  @override
  void initState() {
    super.initState();
    _checkCache();
  }

  Future<void> _checkCache() async {
    final file = await MediaCacheService().getCachedFile(widget.imageUrl);
    if (!mounted) return;
    if (file != null) {
      setState(() => _cachedFile = file);
    } else {
      final downloaded = await MediaCacheService().downloadAndCache(widget.imageUrl);
      if (mounted && downloaded != null) {
        setState(() => _cachedFile = downloaded);
      }
    }
  }

  Future<void> _handleDownload() async {
    if (_downloading) return;
    setState(() => _downloading = true);
    try {
      await _downloadMediaFile(
        context: context,
        url: widget.imageUrl,
        filename: widget.title,
        isVideo: false,
      );
    } finally {
      if (mounted) setState(() => _downloading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final formattedTime = FullScreenImageViewer.formatTimestamp(widget.timestamp);
    final initial = (widget.avatarInitial != null && widget.avatarInitial!.isNotEmpty)
        ? widget.avatarInitial!
        : (widget.senderName.isNotEmpty ? widget.senderName[0].toUpperCase() : '?');
    final gradientColors = AppTheme.getAvatarGradient(
      widget.senderId.isNotEmpty ? widget.senderId : widget.senderName,
    );
    final hasCaption = widget.caption != null && widget.caption!.trim().isNotEmpty;

    return Shortcuts(
      shortcuts: <ShortcutActivator, Intent>{
        const SingleActivator(LogicalKeyboardKey.escape): const DismissIntent(),
      },
      child: Actions(
        actions: <Type, Action<Intent>>{
          DismissIntent: CallbackAction<DismissIntent>(
            onInvoke: (_) => Navigator.of(context).maybePop(),
          ),
        },
        child: Focus(
          autofocus: true,
          child: Scaffold(
            backgroundColor: Colors.transparent,
            body: Stack(
              fit: StackFit.expand,
              children: [
                // Instant Dismiss: Clicking anywhere outside the photo closes the preview immediately
                Positioned.fill(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => Navigator.of(context).maybePop(),
                    child: Container(
                      color: Colors.black.withValues(alpha: 0.94),
                    ),
                  ),
                ),

                // Centered Media Content Stage
                Center(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 76, bottom: 24, left: 16, right: 16),
                    child: GestureDetector(
                      // Prevent taps on the photo itself from triggering backdrop dismiss
                      onTap: () {},
                      behavior: HitTestBehavior.opaque,
                      child: Container(
                        constraints: BoxConstraints(
                          maxWidth: MediaQuery.sizeOf(context).width * 0.92,
                          maxHeight: MediaQuery.sizeOf(context).height * 0.82,
                        ),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.7),
                              blurRadius: 36,
                              spreadRadius: 2,
                              offset: const Offset(0, 8),
                            ),
                          ],
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: Stack(
                          alignment: Alignment.bottomCenter,
                          children: [
                            InteractiveViewer(
                              minScale: 0.8,
                              maxScale: 4.0,
                              child: Hero(
                                tag: widget.heroTag,
                                child: _cachedFile != null
                                    ? Image.file(
                                        _cachedFile!,
                                        fit: BoxFit.contain,
                                        errorBuilder: (context, error, stackTrace) => _buildErrorState(),
                                      )
                                    : Image.network(
                                        widget.imageUrl,
                                        fit: BoxFit.contain,
                                        loadingBuilder: (context, child, loadingProgress) {
                                          if (loadingProgress == null) return child;
                                          final total = loadingProgress.expectedTotalBytes;
                                          final loaded = loadingProgress.cumulativeBytesLoaded;
                                          final progress = total != null && total > 0 ? loaded / total : null;
                                          return SizedBox(
                                            width: 120,
                                            height: 120,
                                            child: Center(
                                              child: CircularProgressIndicator(
                                                value: progress,
                                                strokeWidth: 2.5,
                                                color: Colors.white70,
                                              ),
                                            ),
                                          );
                                        },
                                        errorBuilder: (context, error, stackTrace) => _buildErrorState(),
                                      ),
                              ),
                            ),

                            // Caption Bar: Displayed across the bottom of the photo just like on Instagram
                            if (hasCaption)
                              Positioned(
                                left: 0,
                                right: 0,
                                bottom: 0,
                                child: IgnorePointer(
                                  child: Container(
                                    width: double.infinity,
                                    padding: const EdgeInsets.fromLTRB(16, 28, 16, 14),
                                    decoration: BoxDecoration(
                                      borderRadius: const BorderRadius.vertical(bottom: Radius.circular(12)),
                                      gradient: LinearGradient(
                                        begin: Alignment.bottomCenter,
                                        end: Alignment.topCenter,
                                        colors: [
                                          Colors.black.withValues(alpha: 0.88),
                                          Colors.black.withValues(alpha: 0.45),
                                          Colors.transparent,
                                        ],
                                      ),
                                    ),
                                    child: Text(
                                      widget.caption!,
                                      maxLines: 4,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 14,
                                        fontWeight: FontWeight.w500,
                                        height: 1.35,
                                        shadows: [
                                          Shadow(
                                            color: Colors.black87,
                                            blurRadius: 4,
                                            offset: Offset(0, 1),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),

                // Top Bar: Sender gradient avatar, name, sent timestamp, download button, and ✕ close button
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.black.withValues(alpha: 0.85),
                          Colors.transparent,
                        ],
                      ),
                    ),
                    child: SafeArea(
                      bottom: false,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                        child: Row(
                          children: [
                            // Gradient Avatar Circle
                            Container(
                              width: 38,
                              height: 38,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                gradient: LinearGradient(
                                  colors: gradientColors,
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.4),
                                    blurRadius: 8,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                              ),
                              alignment: Alignment.center,
                              child: Text(
                                initial,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),

                            // Sender Name & Sent Timestamp
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    widget.senderName,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                      letterSpacing: 0.2,
                                    ),
                                  ),
                                  if (formattedTime.isNotEmpty) ...[
                                    const SizedBox(height: 1),
                                    Text(
                                      formattedTime,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: Colors.white.withValues(alpha: 0.65),
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            const SizedBox(width: 12),

                            // Download Button (at left side of X button)
                            GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTap: _downloading ? null : _handleDownload,
                              child: Container(
                                width: 38,
                                height: 38,
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.14),
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: Colors.white.withValues(alpha: 0.2),
                                    width: 1,
                                  ),
                                ),
                                alignment: Alignment.center,
                                child: _downloading
                                    ? const SizedBox(
                                        width: 18,
                                        height: 18,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: Colors.white,
                                        ),
                                      )
                                    : const Icon(
                                        Icons.download_rounded,
                                        color: Colors.white,
                                        size: 20,
                                      ),
                              ),
                            ),
                            const SizedBox(width: 10),

                            // Top-Right ✕ Dismiss Button
                            GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTap: () => Navigator.of(context).maybePop(),
                              child: Container(
                                width: 38,
                                height: 38,
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.14),
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: Colors.white.withValues(alpha: 0.2),
                                    width: 1,
                                  ),
                                ),
                                alignment: Alignment.center,
                                child: const Icon(
                                  Icons.close_rounded,
                                  color: Colors.white,
                                  size: 20,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildErrorState() {
    return const Padding(
      padding: EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.broken_image_rounded, color: Colors.white54, size: 54),
          SizedBox(height: 12),
          Text(
            'Could not load image',
            style: TextStyle(color: Colors.white70, fontSize: 14),
          ),
        ],
      ),
    );
  }
}

/// Compact in-bubble video preview card with play overlay.
class VideoPlayerBubble extends StatefulWidget {
  final String videoUrl;
  final String? filename;
  final int? fileSize;
  final VoidCallback onTap;

  const VideoPlayerBubble({
    super.key,
    required this.videoUrl,
    this.filename,
    this.fileSize,
    required this.onTap,
  });

  @override
  State<VideoPlayerBubble> createState() => _VideoPlayerBubbleState();
}

class _VideoPlayerBubbleState extends State<VideoPlayerBubble> {
  @override
  void initState() {
    super.initState();
    MediaCacheService().downloadAndCache(widget.videoUrl);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Container(
          width: double.infinity,
          height: 180,
          decoration: BoxDecoration(
            color: Colors.black87,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Subtle gradient background
              Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xFF1E1E2E), Color(0xFF121218)],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
                ),
              ),
              // Center Play Icon Button with pulse circle
              Center(
                child: Container(
                  width: 54,
                  height: 54,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.25),
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white70, width: 2),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.3),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: const Center(
                    child: Icon(
                      Icons.play_arrow_rounded,
                      color: Colors.white,
                      size: 34,
                    ),
                  ),
                ),
              ),
              // Top label with video icon
              Positioned(
                top: 8,
                left: 10,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.6),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.videocam_rounded, color: Colors.white, size: 14),
                      const SizedBox(width: 5),
                      Text(
                        widget.filename ?? 'Video',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              // Bottom size indicator if available
              if (widget.fileSize != null && widget.fileSize! > 0)
                Positioned(
                  bottom: 8,
                  right: 10,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.6),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      _formatBytes(widget.fileSize!),
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 10,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  static String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}

/// Full screen Instagram-style video player with playback controls, sender info, download button, caption bar, and instant dismiss.
class FullScreenVideoViewer extends StatefulWidget {
  final String videoUrl;
  final String? title;
  final String senderName;
  final String senderId;
  final String timestamp;
  final String? caption;
  final String? avatarInitial;

  const FullScreenVideoViewer({
    super.key,
    required this.videoUrl,
    this.title,
    required this.senderName,
    required this.senderId,
    required this.timestamp,
    this.caption,
    this.avatarInitial,
  });

  /// Custom scale-in animation route matching Instagram DM preview.
  static Route<void> route({
    required String videoUrl,
    String? title,
    required String senderName,
    required String senderId,
    required String timestamp,
    String? caption,
    String? avatarInitial,
  }) {
    return PageRouteBuilder<void>(
      opaque: false,
      barrierColor: Colors.black.withValues(alpha: 0.94),
      barrierDismissible: true,
      transitionDuration: const Duration(milliseconds: 220),
      reverseTransitionDuration: const Duration(milliseconds: 180),
      pageBuilder: (context, animation, secondaryAnimation) {
        return FullScreenVideoViewer(
          videoUrl: videoUrl,
          title: title,
          senderName: senderName,
          senderId: senderId,
          timestamp: timestamp,
          caption: caption,
          avatarInitial: avatarInitial,
        );
      },
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: const Cubic(0.18, 0.89, 0.32, 1.15),
          reverseCurve: Curves.easeInCubic,
        );
        return FadeTransition(
          opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.92, end: 1.0).animate(curved),
            child: child,
          ),
        );
      },
    );
  }

  static String formatTimestamp(String? isoString) {
    if (isoString == null || isoString.isEmpty) return '';
    final dt = DateTime.tryParse(isoString)?.toLocal();
    if (dt == null) return isoString;
    return DateFormat('dd MMM • h:mm a').format(dt);
  }

  @override
  State<FullScreenVideoViewer> createState() => _FullScreenVideoViewerState();
}

class _FullScreenVideoViewerState extends State<FullScreenVideoViewer> {
  VideoPlayerController? _controller;
  bool _initialized = false;
  bool _hasError = false;
  String _errorMessage = '';
  bool _showControls = true;
  bool _downloading = false;

  @override
  void initState() {
    super.initState();
    _initializePlayer();
  }

  Future<void> _initializePlayer() async {
    try {
      final cachedFile = await MediaCacheService().getCachedFile(widget.videoUrl);
      final VideoPlayerController controller;
      if (cachedFile != null) {
        controller = VideoPlayerController.file(cachedFile);
      } else {
        controller = VideoPlayerController.networkUrl(
          Uri.parse(widget.videoUrl),
        );
        // Pre-cache video for offline playback
        MediaCacheService().downloadAndCache(widget.videoUrl);
      }
      _controller = controller;
      await controller.initialize();
      controller.addListener(() {
        if (mounted) setState(() {});
      });
      await controller.play();
      if (mounted) {
        setState(() {
          _initialized = true;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _hasError = true;
          _errorMessage = e.toString();
        });
      }
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  void _togglePlayPause() {
    final controller = _controller;
    if (controller == null || !_initialized) return;
    setState(() {
      if (controller.value.isPlaying) {
        controller.pause();
      } else {
        controller.play();
      }
    });
  }

  Future<void> _handleDownload() async {
    if (_downloading) return;
    setState(() => _downloading = true);
    try {
      await _downloadMediaFile(
        context: context,
        url: widget.videoUrl,
        filename: widget.title,
        isVideo: true,
      );
    } finally {
      if (mounted) setState(() => _downloading = false);
    }
  }

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    final formattedTime = FullScreenVideoViewer.formatTimestamp(widget.timestamp);
    final initial = (widget.avatarInitial != null && widget.avatarInitial!.isNotEmpty)
        ? widget.avatarInitial!
        : (widget.senderName.isNotEmpty ? widget.senderName[0].toUpperCase() : '?');
    final gradientColors = AppTheme.getAvatarGradient(
      widget.senderId.isNotEmpty ? widget.senderId : widget.senderName,
    );
    final hasCaption = widget.caption != null && widget.caption!.trim().isNotEmpty;

    return Shortcuts(
      shortcuts: <ShortcutActivator, Intent>{
        const SingleActivator(LogicalKeyboardKey.escape): const DismissIntent(),
      },
      child: Actions(
        actions: <Type, Action<Intent>>{
          DismissIntent: CallbackAction<DismissIntent>(
            onInvoke: (_) => Navigator.of(context).maybePop(),
          ),
        },
        child: Focus(
          autofocus: true,
          child: Scaffold(
            backgroundColor: Colors.transparent,
            body: Stack(
              fit: StackFit.expand,
              children: [
                // Instant Dismiss Backdrop: Tapping anywhere outside the video closes the preview
                Positioned.fill(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => Navigator.of(context).maybePop(),
                    child: Container(
                      color: Colors.black.withValues(alpha: 0.94),
                    ),
                  ),
                ),

                // Centered Media Container Stage
                Center(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 76, bottom: 24, left: 16, right: 16),
                    child: GestureDetector(
                      // Tapping video toggles playback controls visibility
                      onTap: () {
                        setState(() {
                          _showControls = !_showControls;
                        });
                      },
                      behavior: HitTestBehavior.opaque,
                      child: Container(
                        constraints: BoxConstraints(
                          maxWidth: MediaQuery.sizeOf(context).width * 0.92,
                          maxHeight: MediaQuery.sizeOf(context).height * 0.82,
                        ),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.7),
                              blurRadius: 36,
                              spreadRadius: 2,
                              offset: const Offset(0, 8),
                            ),
                          ],
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            // Video player or loading/error
                            if (_hasError)
                              Container(
                                color: Colors.black87,
                                padding: const EdgeInsets.all(24),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(Icons.error_outline_rounded, color: Colors.redAccent, size: 48),
                                    const SizedBox(height: 12),
                                    const Text(
                                      'Unable to play video',
                                      style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600),
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      _errorMessage,
                                      textAlign: TextAlign.center,
                                      style: const TextStyle(color: Colors.white54, fontSize: 12),
                                    ),
                                  ],
                                ),
                              )
                            else if (_initialized && _controller != null)
                              AspectRatio(
                                aspectRatio: _controller!.value.aspectRatio,
                                child: VideoPlayer(_controller!),
                              )
                            else
                              Container(
                                height: 220,
                                color: Colors.black54,
                                child: const Center(
                                  child: SizedBox(
                                    width: 48,
                                    height: 48,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 3,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                              ),

                            // Center Play / Pause button overlay
                            if (_initialized && _controller != null && _showControls)
                              Center(
                                child: GestureDetector(
                                  onTap: _togglePlayPause,
                                  child: Container(
                                    width: 64,
                                    height: 64,
                                    decoration: BoxDecoration(
                                      color: Colors.black.withValues(alpha: 0.5),
                                      shape: BoxShape.circle,
                                      border: Border.all(color: Colors.white70, width: 1.5),
                                    ),
                                    child: Icon(
                                      _controller!.value.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                                      color: Colors.white,
                                      size: 40,
                                    ),
                                  ),
                                ),
                              ),

                            // Caption Bar: Displayed across the bottom of the video if present
                            if (hasCaption)
                              Positioned(
                                left: 0,
                                right: 0,
                                bottom: (_initialized && _showControls) ? 72 : 0,
                                child: IgnorePointer(
                                  child: Container(
                                    padding: const EdgeInsets.fromLTRB(16, 20, 16, 12),
                                    decoration: BoxDecoration(
                                      gradient: LinearGradient(
                                        begin: Alignment.bottomCenter,
                                        end: Alignment.topCenter,
                                        colors: [
                                          Colors.black.withValues(alpha: 0.88),
                                          Colors.black.withValues(alpha: 0.4),
                                          Colors.transparent,
                                        ],
                                      ),
                                    ),
                                    child: Text(
                                      widget.caption!,
                                      maxLines: 4,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 14,
                                        fontWeight: FontWeight.w500,
                                        height: 1.35,
                                        shadows: [
                                          Shadow(
                                            color: Colors.black87,
                                            blurRadius: 4,
                                            offset: Offset(0, 1),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ),

                            // Bottom Controls: Scrub bar & time row
                            if (_initialized && _controller != null)
                              Positioned(
                                left: 0,
                                right: 0,
                                bottom: 0,
                                child: AnimatedOpacity(
                                  opacity: _showControls ? 1.0 : 0.0,
                                  duration: const Duration(milliseconds: 200),
                                  child: Container(
                                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
                                    decoration: BoxDecoration(
                                      gradient: LinearGradient(
                                        colors: [Colors.transparent, Colors.black.withValues(alpha: 0.9)],
                                        begin: Alignment.topCenter,
                                        end: Alignment.bottomCenter,
                                      ),
                                    ),
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        VideoProgressIndicator(
                                          _controller!,
                                          allowScrubbing: true,
                                          colors: const VideoProgressColors(
                                            playedColor: Color(0xFF6366F1),
                                            bufferedColor: Colors.white24,
                                            backgroundColor: Colors.white10,
                                          ),
                                        ),
                                        const SizedBox(height: 6),
                                        Row(
                                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                          children: [
                                            Text(
                                              '${_formatDuration(_controller!.value.position)} / ${_formatDuration(_controller!.value.duration)}',
                                              style: const TextStyle(color: Colors.white70, fontSize: 12),
                                            ),
                                            Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                IconButton(
                                                  icon: Icon(
                                                    _controller!.value.volume > 0 ? Icons.volume_up_rounded : Icons.volume_off_rounded,
                                                    color: Colors.white,
                                                    size: 20,
                                                  ),
                                                  onPressed: () {
                                                    setState(() {
                                                      _controller!.setVolume(_controller!.value.volume > 0 ? 0 : 1);
                                                    });
                                                  },
                                                ),
                                                IconButton(
                                                  icon: const Icon(Icons.replay_10_rounded, color: Colors.white, size: 20),
                                                  onPressed: () {
                                                    final current = _controller!.value.position;
                                                    _controller!.seekTo(current - const Duration(seconds: 10));
                                                  },
                                                ),
                                                IconButton(
                                                  icon: const Icon(Icons.forward_10_rounded, color: Colors.white, size: 20),
                                                  onPressed: () {
                                                    final current = _controller!.value.position;
                                                    _controller!.seekTo(current + const Duration(seconds: 10));
                                                  },
                                                ),
                                              ],
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),

                // Top Bar: Sender gradient avatar, name, sent timestamp, download button, and ✕ close button
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.black.withValues(alpha: 0.85),
                          Colors.transparent,
                        ],
                      ),
                    ),
                    child: SafeArea(
                      bottom: false,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                        child: Row(
                          children: [
                            // Gradient Avatar Circle
                            Container(
                              width: 38,
                              height: 38,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                gradient: LinearGradient(
                                  colors: gradientColors,
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.4),
                                    blurRadius: 8,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                              ),
                              alignment: Alignment.center,
                              child: Text(
                                initial,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),

                            // Sender Name & Sent Timestamp
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    widget.senderName,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                      letterSpacing: 0.2,
                                    ),
                                  ),
                                  if (formattedTime.isNotEmpty) ...[
                                    const SizedBox(height: 1),
                                    Text(
                                      formattedTime,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: Colors.white.withValues(alpha: 0.65),
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            const SizedBox(width: 12),

                            // Download Button (at left side of X button)
                            GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTap: _downloading ? null : _handleDownload,
                              child: Container(
                                width: 38,
                                height: 38,
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.14),
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: Colors.white.withValues(alpha: 0.2),
                                    width: 1,
                                  ),
                                ),
                                alignment: Alignment.center,
                                child: _downloading
                                    ? const SizedBox(
                                        width: 18,
                                        height: 18,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: Colors.white,
                                        ),
                                      )
                                    : const Icon(
                                        Icons.download_rounded,
                                        color: Colors.white,
                                        size: 20,
                                      ),
                              ),
                            ),
                            const SizedBox(width: 10),

                            // Top-Right ✕ Dismiss Button
                            GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTap: () => Navigator.of(context).maybePop(),
                              child: Container(
                                width: 38,
                                height: 38,
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.14),
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: Colors.white.withValues(alpha: 0.2),
                                    width: 1,
                                  ),
                                ),
                                alignment: Alignment.center,
                                child: const Icon(
                                  Icons.close_rounded,
                                  color: Colors.white,
                                  size: 20,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
