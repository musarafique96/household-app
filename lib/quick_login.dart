import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Fingerprint / face sign-in for this phone.
/// Only one account per phone can use quick login at a time.
class QuickLogin {
  QuickLogin._();

  static const _userKey = 'quick_login_user_id';
  static const _promptedKey = 'quick_login_prompted';
  static final LocalAuthentication _auth = LocalAuthentication();

  /// True if the phone has a fingerprint or face unlock set up.
  static Future<bool> canUseBiometrics() async {
    try {
      final supported = await _auth.isDeviceSupported();
      final canCheck = await _auth.canCheckBiometrics;
      return supported && canCheck;
    } catch (_) {
      return false;
    }
  }

  /// Shows the system fingerprint prompt. Returns true if it was recognised.
  static Future<bool> authenticate(String reason) async {
    try {
      return await _auth.authenticate(
        localizedReason: reason,
        options: const AuthenticationOptions(
          biometricOnly: true,
          stickyAuth: true,
        ),
      );
    } catch (_) {
      return false;
    }
  }

  /// The account that has quick login on this phone, or null.
  static Future<int?> enabledUserId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_userKey);
  }

  static Future<void> enable(int userId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_userKey, userId);
  }

  static Future<void> disable() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_userKey);
  }

  /// Whether the first-login quick login offer has already been shown.
  static Future<bool> wasPrompted() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_promptedKey) ?? false;
  }

  static Future<void> markPrompted() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_promptedKey, true);
  }
}
