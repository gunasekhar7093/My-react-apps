import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class SecureStorageService {
  static const _tokenKey = 'chatspace_token';
  static const _userKey = 'chatspace_user';
  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  Future<void> saveToken(String token) => _storage.write(key: _tokenKey, value: token);
  Future<String?> getToken() => _storage.read(key: _tokenKey);
  Future<void> clearToken() => _storage.delete(key: _tokenKey);

  Future<void> saveUser(String userJson) => _storage.write(key: _userKey, value: userJson);
  Future<String?> getUser() => _storage.read(key: _userKey);
  Future<void> clearUser() => _storage.delete(key: _userKey);

  Future<void> clearAll() async {
    await _storage.delete(key: _tokenKey);
    await _storage.delete(key: _userKey);
  }
}
