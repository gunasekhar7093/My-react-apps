import 'dart:convert';
import 'package:http/http.dart' as http;
import '../storage/secure_storage_service.dart';
import '../constants/api_constants.dart';

import 'package:http_parser/http_parser.dart';

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

  static const Duration _timeout = Duration(seconds: 25);

  Future<Map<String, dynamic>> post(String path, {Map<String, dynamic>? body, bool authenticated = false}) async {
    final response = await _client.post(
      Uri.parse(ApiConstants.baseUrl + path),
      headers: await _headers(authenticated),
      body: jsonEncode(body ?? {}),
    ).timeout(_timeout);
    return _decodeMap(response);
  }

  Future<Map<String, dynamic>> get(String path, {bool authenticated = false}) async {
    final response = await _client.get(
      Uri.parse(ApiConstants.baseUrl + path),
      headers: await _headers(authenticated),
    ).timeout(_timeout);
    return _decodeMap(response);
  }

  Future<Map<String, dynamic>> delete(String path, {bool authenticated = false}) async {
    final response = await _client.delete(
      Uri.parse(ApiConstants.baseUrl + path),
      headers: await _headers(authenticated),
    ).timeout(_timeout);
    return _decodeMap(response);
  }

  Future<List<dynamic>> getList(String path, {bool authenticated = false}) async {
    final response = await _client.get(
      Uri.parse(ApiConstants.baseUrl + path),
      headers: await _headers(authenticated),
    ).timeout(_timeout);
    return _decodeList(response);
  }

  Future<Map<String, dynamic>> uploadMedia({
    required List<int> bytes,
    required String filename,
    required String mimeType,
    String? filePath,
  }) async {
    final uri = Uri.parse('${ApiConstants.baseUrl}/api/upload');
    final request = http.MultipartRequest('POST', uri);

    final token = await storage.getToken();
    if (token != null && token.isNotEmpty) {
      request.headers['Authorization'] = 'Bearer $token';
    }

    MediaType? parsedContentType;
    try {
      final parts = mimeType.split('/');
      if (parts.length == 2) {
        parsedContentType = MediaType(parts[0].trim(), parts[1].trim());
      }
    } catch (_) {
      parsedContentType = MediaType(
        mimeType.startsWith('video') ? 'video' : 'image',
        mimeType.startsWith('video') ? 'mp4' : 'jpeg',
      );
    }

    if (filePath != null && filePath.isNotEmpty) {
      try {
        request.files.add(
          await http.MultipartFile.fromPath(
            'file',
            filePath,
            filename: filename,
            contentType: parsedContentType,
          ),
        );
      } catch (_) {
        request.files.add(
          http.MultipartFile.fromBytes(
            'file',
            bytes,
            filename: filename,
            contentType: parsedContentType,
          ),
        );
      }
    } else {
      request.files.add(
        http.MultipartFile.fromBytes(
          'file',
          bytes,
          filename: filename,
          contentType: parsedContentType,
        ),
      );
    }

    final streamedResponse = await request.send().timeout(const Duration(minutes: 3));
    final response = await http.Response.fromStream(streamedResponse);
    return _decodeMap(response);
  }

  Future<Map<String, String>> _headers(bool authenticated) async {
    final headers = <String, String>{'Content-Type': 'application/json', 'Accept': 'application/json'};
    if (authenticated) {
      final token = await storage.getToken();
      if (token != null && token.isNotEmpty) headers['Authorization'] = 'Bearer $token';
    }
    return headers;
  }

  Map<String, dynamic> _decodeMap(http.Response response) {
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

  List<dynamic> _decodeList(http.Response response) {
    dynamic decoded;
    if (response.body.isNotEmpty) decoded = jsonDecode(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final message = decoded is Map<String, dynamic>
          ? decoded['error']?.toString() ?? 'Something went wrong. Please try again.'
          : 'Something went wrong. Please try again.';
      throw ApiException(response.statusCode, message);
    }
    if (decoded is! List<dynamic>) {
      throw const ApiException(500, 'The server returned an invalid list response.');
    }
    return decoded;
  }
}
