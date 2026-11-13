import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Reads the signing key this app was built with, so sign-in problems can be checked.
class Diagnostics {
  Diagnostics._();

  static const MethodChannel _channel = MethodChannel('gharbaar/diag');

  /// Logs a short note on the phone (visible in the debug console). Nothing is sent to a server.
  static Future<void> saveNote(String text) async {
    debugPrint(text.length > 1900 ? text.substring(0, 1900) : text);
  }

  static Future<String> appSigningKey() async {
    try {
      return await _channel.invokeMethod<String>('signingSha1') ?? 'unknown';
    } catch (e) {
      return 'unavailable ($e)';
    }
  }
}
