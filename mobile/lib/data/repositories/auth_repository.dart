import '../../core/constants/api_constants.dart';
import '../../core/network/api_client.dart';
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
    try {
      final data = await apiClient.get(ApiConstants.me, authenticated: true);
      return UserModel.fromJson(data['user'] as Map<String, dynamic>);
    } catch (_) {
      await storage.clearToken();
      return null;
    }
  }

  Future<void> logout() async {
    try {
      await apiClient.post(ApiConstants.logout, authenticated: true);
    } finally {
      await storage.clearToken();
    }
  }

  Future<AuthResult> _saveSession(Map<String, dynamic> data) async {
    final token = data['token']?.toString();
    final userJson = data['user'];
    if (token == null || token.isEmpty || userJson is! Map<String, dynamic>) {
      throw const ApiException(500, 'The server returned an invalid session.');
    }
    await storage.saveToken(token);
    return AuthResult(token: token, user: UserModel.fromJson(userJson));
  }
}
