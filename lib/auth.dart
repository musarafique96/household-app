import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

/// Password helpers. Passwords are stored as a salted SHA-256 hash, never in plain text.
class Auth {
  Auth._();

  static String newSalt() {
    final rnd = Random.secure();
    final bytes = List<int>.generate(16, (_) => rnd.nextInt(256));
    return base64Url.encode(bytes);
  }

  static String hash(String salt, String password) {
    return sha256.convert(utf8.encode('$salt:$password')).toString();
  }

  static bool verify(String salt, String storedHash, String password) {
    return hash(salt, password) == storedHash;
  }
}
