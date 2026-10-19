import 'dart:convert';
import '../../core/constants/api_constants.dart';
import '../../core/network/api_client.dart';
import '../../core/services/fcm_service.dart';
import '../../core/services/notification_service.dart';
import '../../core/storage/secure_storage_service.dart';
import '../models/user_model.dart';

class AuthResult {
  final String token;
  final UserModel user;
  const AuthResult({required this.token, required this.user});
}

class AuthRepository {
  final ApiClient apiClient;
  final SecureStorageService storage;

  AuthRepository({ApiClient? apiClient, SecureStorageService? storage})
      : storage = storage ?? SecureStorageService(),
        apiClient = apiClient ?? ApiClient();

  Future<AuthResult> login({required String username, required String password}) async {
    final data = await apiClient.post(ApiConstants.login, body: {'username': username, 'password': password});
    return _saveSession(data);
  }

  Future<AuthResult> register({required String name, required String username, required String password, String phone = ''}) async {
    final data = await apiClient.post(ApiConstants.register, body: {'name': name, 'username': username, 'password': password, 'phone': phone});
    return _saveSession(data);
  }

  Future<UserModel?> restoreSession() async {
    final token = await storage.getToken();
    if (token == null || token.isEmpty) return null;

    UserModel? cachedUser;
    final cachedUserString = await storage.getUser();
    if (cachedUserString != null && cachedUserString.isNotEmpty) {
      try {
        final decoded = jsonDecode(cachedUserString);
        if (decoded is Map<String, dynamic>) {
          cachedUser = UserModel.fromJson(decoded);
        }
      } catch (_) {}
    }

    // Fallback: If no profile was cached yet, extract the user id from the token payload
    if (cachedUser == null) {
      final userId = _extractUserIdFromToken(token);
      if (userId != null && userId.isNotEmpty) {
        cachedUser = UserModel(id: userId, name: 'User', username: '');
      }
    }

    try {
      final data = await apiClient.get(ApiConstants.me, authenticated: true);
      final userJson = data['user'];
      if (userJson is Map<String, dynamic>) {
        final freshUser = UserModel.fromJson(userJson);
        await storage.saveUser(jsonEncode(freshUser.toJson()));
        return freshUser;
      }
      return cachedUser;
    } on ApiException catch (error) {
      // ONLY clear session if server explicitly revoked or invalidated the token
      if (error.statusCode == 401 || error.statusCode == 403) {
        await storage.clearAll();
        return null;
      }
      return cachedUser;
    } catch (_) {
      // Offline, no internet connection, or timeout:
      // Never delete the token or cached user! Keep the user authenticated.
      return cachedUser;
    }
  }

  Future<void> logout() async {
    try {
      final token = await FcmService().getDeviceToken();
      // 1. Dismiss any notifications currently shown for this account
      await NotificationService().cancelAllNotifications();
      // 2. Unregister device token with server and delete locally
      await FcmService().unregisterDeviceToken();
      // 3. Inform server of logout to remove this specific device token and update status
      await apiClient.post(
        ApiConstants.logout,
        body: (token != null && token.isNotEmpty) ? {'token': token} : null,
        authenticated: true,
      );
    } catch (_) {
      // Ignore network failures on logout
    } finally {
      await storage.clearAll();
    }
  }

  String? _extractUserIdFromToken(String token) {
    try {
      final parts = token.split('.');
      if (parts.length < 2) return null;
      final normalized = base64Url.normalize(parts[1]);
      final payloadString = utf8.decode(base64Url.decode(normalized));
      final map = jsonDecode(payloadString);
      if (map is Map<String, dynamic>) {
        return map['sub']?.toString();
      }
    } catch (_) {}
    return null;
  }

  Future<AuthResult> _saveSession(Map<String, dynamic> data) async {
    final token = data['token']?.toString();
    final userJson = data['user'];
    if (token == null || token.isEmpty || userJson is! Map<String, dynamic>) {
      throw const ApiException(500, 'The server returned an invalid session.');
    }
    final user = UserModel.fromJson(userJson);
    await storage.saveToken(token);
    await storage.saveUser(jsonEncode(user.toJson()));
    return AuthResult(token: token, user: user);
  }
}
