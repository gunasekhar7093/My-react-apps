import '../../core/constants/api_constants.dart';
import '../../core/network/api_client.dart';
import '../models/user_model.dart';

class UserRepository {
  final ApiClient apiClient;

  UserRepository({ApiClient? apiClient}) : apiClient = apiClient ?? ApiClient();

  Future<List<UserModel>> getUsers() async {
    final data = await apiClient.getList(ApiConstants.users, authenticated: true);
    return data
        .whereType<Map<String, dynamic>>()
        .map(UserModel.fromJson)
        .toList();
  }
}
