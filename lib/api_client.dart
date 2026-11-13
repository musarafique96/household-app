import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

/// An error the server reported, with the message to show the person.
class ApiException implements Exception {
  final int status;
  final String message;
  ApiException(this.status, this.message);
  @override
  String toString() => message;
}

/// Talks to the Gharbaar API. Keeps the sign-in tokens in the phone's secure storage,
/// and renews the short-lived access token when the server says it has expired.
class ApiClient {
  ApiClient._();

  static const String baseUrl = 'https://gharbaar.duckdns.org';
  static const Duration _timeout = Duration(seconds: 20);
  static const FlutterSecureStorage _storage = FlutterSecureStorage();
  static const String _accessKey = 'api_access_token';
  static const String _refreshKey = 'api_refresh_token';

  static String? _access;

  static Future<bool> get hasSession async => (await _storage.read(key: _refreshKey)) != null;

  static Future<void> saveTokens(String access, String refresh) async {
    _access = access;
    await _storage.write(key: _accessKey, value: access);
    await _storage.write(key: _refreshKey, value: refresh);
  }

  static Future<void> clearTokens() async {
    _access = null;
    await _storage.delete(key: _accessKey);
    await _storage.delete(key: _refreshKey);
  }

  /// Tells the server to end this session, then forgets the tokens on the phone.
  static Future<void> endSession() async {
    final refresh = await _storage.read(key: _refreshKey);
    if (refresh != null) {
      try {
        await post('/auth/signout', {'refreshToken': refresh});
      } catch (_) {}
    }
    await clearTokens();
  }

  static Future<dynamic> get(String path) => _send('GET', path);
  static Future<dynamic> post(String path, [Object? body]) => _send('POST', path, body);
  static Future<dynamic> put(String path, [Object? body]) => _send('PUT', path, body);
  static Future<dynamic> delete(String path) => _send('DELETE', path);

  static Future<dynamic> _send(String method, String path, [Object? body, bool retried = false]) async {
    _access ??= await _storage.read(key: _accessKey);
    final headers = <String, String>{
      'Content-Type': 'application/json',
      if (_access != null) 'Authorization': 'Bearer $_access',
    };
    final response = await _raw(method, Uri.parse('$baseUrl$path'), headers, body == null ? null : jsonEncode(body));

    // An expired access token is renewed once and the request is sent again. Sign-in and sign-out never retry.
    final isAuthCall = path.startsWith('/auth/');
    if (response.statusCode == 401 && !retried && !isAuthCall && await _refresh()) {
      return _send(method, path, body, true);
    }
    return _decode(response);
  }

  static Future<http.Response> _raw(String method, Uri uri, Map<String, String> headers, String? body) {
    switch (method) {
      case 'GET':
        return http.get(uri, headers: headers).timeout(_timeout);
      case 'POST':
        return http.post(uri, headers: headers, body: body).timeout(_timeout);
      case 'PUT':
        return http.put(uri, headers: headers, body: body).timeout(_timeout);
      default:
        return http.delete(uri, headers: headers).timeout(_timeout);
    }
  }

  static Future<bool> _refresh() async {
    final refresh = await _storage.read(key: _refreshKey);
    if (refresh == null) return false;
    final response = await http
        .post(
          Uri.parse('$baseUrl/auth/refresh'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'refreshToken': refresh}),
        )
        .timeout(_timeout);
    if (response.statusCode != 200) {
      // The refresh token is no longer valid, so the person has to sign in again.
      await clearTokens();
      return false;
    }
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    await saveTokens(data['accessToken'] as String, data['refreshToken'] as String);
    return true;
  }

  static dynamic _decode(http.Response response) {
    final text = utf8.decode(response.bodyBytes);
    final data = text.isEmpty ? null : jsonDecode(text);
    if (response.statusCode >= 200 && response.statusCode < 300) return data;

    final message = data is Map && data['error'] is String
        ? data['error'] as String
        : 'Something went wrong (${response.statusCode}).';
    throw ApiException(response.statusCode, message);
  }
}
