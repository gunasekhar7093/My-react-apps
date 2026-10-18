import 'dart:convert';

import '../../core/constants/api_constants.dart';
import '../../core/network/api_client.dart';
import '../../core/services/local_storage_service.dart';
import '../../core/storage/secure_storage_service.dart';
import '../models/user_model.dart';

class UserRepository {
  final ApiClient apiClient;
  final LocalStorageService localStorage;
  final SecureStorageService secureStorage;

  UserRepository({
    ApiClient? apiClient,
    LocalStorageService? localStorage,
    SecureStorageService? secureStorage,
  })  : apiClient = apiClient ?? ApiClient(),
        localStorage = localStorage ?? LocalStorageService(),
        secureStorage = secureStorage ?? SecureStorageService();

  Future<String?> _getCurrentUserId() async {
    try {
      final userStr = await secureStorage.getUser();
      if (userStr != null && userStr.isNotEmpty) {
        final data = jsonDecode(userStr);
        return data['id']?.toString() ?? data['_id']?.toString();
      }
    } catch (_) {}
    return null;
  }

  Future<List<UserModel>> getCachedUsers() async {
    final currentUserId = await _getCurrentUserId();
    if (currentUserId != null && currentUserId.isNotEmpty) {
      return localStorage.getUsers(currentUserId);
    }
    return const [];
  }

  Future<List<UserModel>> getUsers() async {
    final currentUserId = await _getCurrentUserId();
    try {
      final data = await apiClient.getList(ApiConstants.users, authenticated: true);
      final users = data
          .whereType<Map>()
          .map((m) => UserModel.fromJson(Map<String, dynamic>.from(m)))
          .toList();

      if (currentUserId != null && currentUserId.isNotEmpty) {
        await localStorage.saveUsers(currentUserId, users);
      }
      return users;
    } catch (e) {
      if (currentUserId != null && currentUserId.isNotEmpty) {
        final cached = await localStorage.getUsers(currentUserId);
        if (cached.isNotEmpty) {
          return cached;
        }
      }
      rethrow;
    }
  }

  Future<void> saveCachedUsers(List<UserModel> users) async {
    final currentUserId = await _getCurrentUserId();
    if (currentUserId != null && currentUserId.isNotEmpty) {
      await localStorage.saveUsers(currentUserId, users);
    }
  }

  Future<void> zeroUnreadCount(String partnerId) async {
    final currentUserId = await _getCurrentUserId();
    if (currentUserId != null && currentUserId.isNotEmpty) {
      await localStorage.zeroUnreadCount(currentUserId, partnerId);
    }
  }
}
