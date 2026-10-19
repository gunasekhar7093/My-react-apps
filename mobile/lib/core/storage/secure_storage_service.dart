import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SecureStorageService {
  static const _tokenKey = 'chatspace_token';
  static const _userKey = 'chatspace_user';
  static const activeUidPrefKey = 'chatspace_active_uid';

  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  // Network API token stays strictly inside hardware-backed encrypted storage
  Future<void> saveToken(String token) => _storage.write(key: _tokenKey, value: token);
  Future<String?> getToken() => _storage.read(key: _tokenKey);
  Future<void> clearToken() => _storage.delete(key: _tokenKey);

  // User profile stays in secure storage; only the active user ID is mirrored to SharedPreferences for headless background isolates
  Future<void> saveUser(String userJson) async {
    await _storage.write(key: _userKey, value: userJson);
    try {
      String uid = '';
      final dynamic decoded = jsonDecode(userJson);
      if (decoded is Map) {
        uid = decoded['id']?.toString() ?? decoded['_id']?.toString() ?? '';
      }
      if (uid.isNotEmpty) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(activeUidPrefKey, uid);
      }
    } catch (_) {}
  }

  Future<String?> getUser() => _storage.read(key: _userKey);

  Future<void> clearUser() async {
    await _storage.delete(key: _userKey);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(activeUidPrefKey);
    } catch (_) {}
  }

  Future<void> clearAll() async {
    await _storage.delete(key: _tokenKey);
    await _storage.delete(key: _userKey);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(activeUidPrefKey);
      // Clean up any legacy plaintext keys if present from earlier builds
      await prefs.remove(_tokenKey);
      await prefs.remove(_userKey);
    } catch (_) {}
  }
}
