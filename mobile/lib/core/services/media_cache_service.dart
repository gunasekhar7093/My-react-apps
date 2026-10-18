import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

/// Service to cache media (images and videos) locally on device storage
/// so they can be viewed and played when mobile data is turned off.
class MediaCacheService {
  static final MediaCacheService _instance = MediaCacheService._internal();
  factory MediaCacheService() => _instance;
  MediaCacheService._internal();

  Directory? _mediaDir;
  final Set<String> _activeDownloads = {};

  Future<Directory> _getMediaDirectory() async {
    if (_mediaDir != null && await _mediaDir!.exists()) {
      return _mediaDir!;
    }
    final appDir = await getApplicationDocumentsDirectory();
    final dir = Directory('${appDir.path}/chatspace_media');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    _mediaDir = dir;
    return dir;
  }

  String _generateFilename(String url) {
    try {
      final uri = Uri.parse(url);
      final lastSegment = uri.pathSegments.isNotEmpty ? uri.pathSegments.last : 'media';
      final cleanSegment = lastSegment.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
      return '${url.hashCode.abs()}_$cleanSegment';
    } catch (_) {
      return '${url.hashCode.abs()}_media.bin';
    }
  }

  Future<File> getTargetFile(String url) async {
    final dir = await _getMediaDirectory();
    final filename = _generateFilename(url);
    return File('${dir.path}/$filename');
  }

  /// Returns the local cached file if it exists and is non-empty.
  Future<File?> getCachedFile(String url) async {
    if (url.trim().isEmpty) return null;
    try {
      final file = await getTargetFile(url);
      if (await file.exists() && await file.length() > 0) {
        return file;
      }
    } catch (_) {}
    return null;
  }

  /// Downloads the file from [url] and writes it to the local cache.
  /// If the file is already cached, returns the cached file immediately.
  Future<File?> downloadAndCache(String url) async {
    if (url.trim().isEmpty) return null;

    final cached = await getCachedFile(url);
    if (cached != null) return cached;

    // Prevent duplicate simultaneous downloads for the same URL
    if (_activeDownloads.contains(url)) {
      // Wait briefly for active download to complete
      for (int i = 0; i < 20; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 250));
        final file = await getCachedFile(url);
        if (file != null) return file;
        if (!_activeDownloads.contains(url)) break;
      }
      return getCachedFile(url);
    }

    _activeDownloads.add(url);
    try {
      final target = await getTargetFile(url);
      final uri = Uri.parse(url);
      final response = await http.get(uri);
      if (response.statusCode == 200 && response.bodyBytes.isNotEmpty) {
        await target.writeAsBytes(response.bodyBytes, flush: true);
        return target;
      }
    } catch (_) {
      // Network or write error (e.g., offline)
    } finally {
      _activeDownloads.remove(url);
    }
    return null;
  }

  /// Caches raw file bytes directly (used when sending local photos/videos).
  Future<File?> cacheBytes(String url, List<int> bytes) async {
    if (url.trim().isEmpty || bytes.isEmpty) return null;
    try {
      final target = await getTargetFile(url);
      await target.writeAsBytes(bytes, flush: true);
      return target;
    } catch (_) {
      return null;
    }
  }

  /// Copies an existing local file into the cache for a target URL.
  Future<File?> cacheFile(String url, File sourceFile) async {
    if (url.trim().isEmpty || !await sourceFile.exists()) return null;
    try {
      final target = await getTargetFile(url);
      await sourceFile.copy(target.path);
      return target;
    } catch (_) {
      return null;
    }
  }
}
