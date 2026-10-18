import 'dart:io';
import 'package:flutter/material.dart';

import '../../../core/services/media_cache_service.dart';

/// An image widget that loads from local offline storage if available,
/// or loads from network and automatically caches to local storage for offline viewing.
class CachedMediaImage extends StatefulWidget {
  final String imageUrl;
  final BoxFit fit;
  final double? width;
  final double? height;
  final String? heroTag;
  final BorderRadius? borderRadius;

  const CachedMediaImage({
    super.key,
    required this.imageUrl,
    this.fit = BoxFit.cover,
    this.width,
    this.height,
    this.heroTag,
    this.borderRadius,
  });

  @override
  State<CachedMediaImage> createState() => _CachedMediaImageState();
}

class _CachedMediaImageState extends State<CachedMediaImage> {
  File? _cachedFile;

  @override
  void initState() {
    super.initState();
    _checkAndCache();
  }

  @override
  void didUpdateWidget(covariant CachedMediaImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.imageUrl != widget.imageUrl) {
      _checkAndCache();
    }
  }

  Future<void> _checkAndCache() async {
    final existing = await MediaCacheService().getCachedFile(widget.imageUrl);
    if (!mounted) return;

    if (existing != null) {
      setState(() {
        _cachedFile = existing;
      });
      return;
    }

    // Download and cache in background
    final downloaded = await MediaCacheService().downloadAndCache(widget.imageUrl);
    if (mounted && downloaded != null) {
      setState(() => _cachedFile = downloaded);
    }
  }

  @override
  Widget build(BuildContext context) {
    Widget imageWidget;

    if (_cachedFile != null) {
      imageWidget = Image.file(
        _cachedFile!,
        fit: widget.fit,
        width: widget.width,
        height: widget.height,
        errorBuilder: (context, error, stackTrace) => _buildErrorWidget(),
      );
    } else {
      imageWidget = Image.network(
        widget.imageUrl,
        fit: widget.fit,
        width: widget.width,
        height: widget.height,
        loadingBuilder: (context, child, progress) {
          if (progress == null) return child;
          return Container(
            width: widget.width,
            height: widget.height ?? 180,
            color: Colors.black12,
            child: const Center(
              child: SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          );
        },
        errorBuilder: (context, error, stackTrace) => _buildErrorWidget(),
      );
    }

    if (widget.heroTag != null && widget.heroTag!.isNotEmpty) {
      imageWidget = Hero(tag: widget.heroTag!, child: imageWidget);
    }

    if (widget.borderRadius != null) {
      imageWidget = ClipRRect(borderRadius: widget.borderRadius!, child: imageWidget);
    }

    return imageWidget;
  }

  Widget _buildErrorWidget() {
    return Container(
      width: widget.width,
      height: widget.height ?? 140,
      color: Colors.black12,
      child: const Center(
        child: Icon(Icons.broken_image_rounded, size: 36, color: Colors.grey),
      ),
    );
  }
}
