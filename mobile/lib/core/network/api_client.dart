import 'dart:convert';
import 'package:http/http.dart' as http;
import '../storage/secure_storage_service.dart';
import '../constants/api_constants.dart';

class ApiException implements Exception {
  final int statusCode;
  final String message;
  const ApiException(this.statusCode, this.message);
  @override
  String toString() => message;
}

class ApiClient {
  final SecureStorageService storage;
  final http.Client _client;

  ApiClient({SecureStorageService? storage, http.Client? client})
      : storage = storage ?? SecureStorageService(),
        _client = client ?? http.Client();

  Future<Map<String, dynamic>> post(String path, {Map<String, dynamic>? body, bool authenticated = false}) async {
    final response = await _client.post(
      Uri.parse('https://my-react-apps-aet5.onrender.com' + path),
      headers: await _headers(authenticated),
      body: jsonEncode(body ?? {}),
    );
    return _decode(response);
  }

  Future<Map<String, dynamic>> get(String path, {bool authenticated = false}) async {
    final response = await _client.get(
      Uri.parse('https://my-react-apps-aet5.onrender.com' + path),
      headers: await _headers(authenticated),
    );
    return _decode(response);
  }

  Future<Map<String, String>> _headers(bool authenticated) async {
    final headers = <String, String>{'Content-Type': 'application/json', 'Accept': 'application/json'};
    if (authenticated) {
      final token = await storage.getToken();
      if (token != null && token.isNotEmpty) headers['Authorization'] = 'Bearer ' + token;
    }
    return headers;
  }

  Map<String, dynamic> _decode(http.Response response) {
    Map<String, dynamic> data = {};
    if (response.body.isNotEmpty) {
      final decoded = jsonDecode(response.body);
      if (decoded is Map<String, dynamic>) data = decoded;
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiException(response.statusCode, data['error']?.toString() ?? 'Something went wrong. Please try again.');
    }
    return data;
  }
}
