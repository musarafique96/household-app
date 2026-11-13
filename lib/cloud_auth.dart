import 'api_client.dart';

/// A message to show the person when sign-in or account changes fail.
class CloudAuthException implements Exception {
  final String message;
  CloudAuthException(this.message);
  @override
  String toString() => message;
}

/// The signed-in cloud account.
class CloudUser {
  final String uid;
  final String username;
  final String email;
  final String displayName;
  CloudUser({required this.uid, required this.username, this.email = '', this.displayName = ''});
}

/// Cloud sign-in with a username and password, through the Gharbaar API.
/// Gmail and phone sign-in are paused until the API supports them.
class CloudAuth {
  CloudAuth._();

  static CloudUser? _current;

  static CloudUser? get currentUser => _current;

  /// Matches the API's rule: 3-30 characters, letters, numbers, dot or underscore.
  static bool validUsername(String username) =>
      RegExp(r'^[a-z0-9_.]{3,30}$').hasMatch(username.toLowerCase());

  /// Phone numbers are stored as digits with an optional leading +.
  static String normalizePhone(String phone) => phone.replaceAll(RegExp(r'[^0-9+]'), '');

  static bool validPhone(String phone) {
    final p = normalizePhone(phone);
    return RegExp(r'^\+?[0-9]{8,15}$').hasMatch(p);
  }

  /// Creates a username account, then signs in to it.
  static Future<CloudUser> signUp(String username, String password) async {
    try {
      await ApiClient.post('/auth/signup', {'username': username.toLowerCase(), 'password': password});
    } on ApiException catch (e) {
      throw CloudAuthException(e.message);
    }
    return signIn(username, password);
  }

  static Future<CloudUser> signIn(String username, String password) async {
    try {
      final data = await ApiClient.post('/auth/signin', {
        'login': username.toLowerCase(),
        'password': password,
      }) as Map<String, dynamic>;
      await ApiClient.saveTokens(data['accessToken'] as String, data['refreshToken'] as String);
      return _loadMe();
    } on ApiException catch (e) {
      if (e.status == 401) throw CloudAuthException('Username or password is wrong.');
      throw CloudAuthException(e.message);
    }
  }

  /// Restores the saved session when the app starts. Returns null if there is no session or it has ended.
  static Future<CloudUser?> restore() async {
    if (!await ApiClient.hasSession) return null;
    try {
      return await _loadMe();
    } catch (_) {
      return null;
    }
  }

  static Future<CloudUser> _loadMe() async {
    final me = await ApiClient.get('/me') as Map<String, dynamic>;
    _current = CloudUser(
      uid: me['id'] as String,
      username: (me['username'] as String?) ?? '',
      email: (me['email'] as String?) ?? '',
      displayName: (me['displayName'] as String?) ?? '',
    );
    return _current!;
  }

  /// Changes the password. The server signs out every device, so this signs in again on this phone.
  static Future<void> changePassword(String currentPassword, String newPassword) async {
    final username = _current?.username ?? '';
    if (username.isEmpty) throw CloudAuthException('Sign in first.');
    try {
      await ApiClient.post('/me/password', {
        'currentPassword': currentPassword,
        'newPassword': newPassword,
      });
    } on ApiException catch (e) {
      if (e.status == 401) throw CloudAuthException('Current password is wrong.');
      throw CloudAuthException(e.message);
    }
    await signIn(username, newPassword);
  }

  /// Disables the cloud login and leaves every household. The username stays reserved and the history is kept.
  static Future<void> deleteAccount({required String password}) async {
    try {
      await ApiClient.post('/me/delete', {'password': password});
    } on ApiException catch (e) {
      if (e.status == 401) throw CloudAuthException('Current password is wrong.');
      throw CloudAuthException(e.message);
    }
    await ApiClient.clearTokens();
    _current = null;
  }

  static Future<void> signOut() async {
    await ApiClient.endSession();
    _current = null;
  }
}
