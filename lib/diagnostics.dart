import 'package:flutter/services.dart';

/// Reads the signing key this app was built with, so sign-in problems can be checked.
class Diagnostics {
  Diagnostics._();

  static const MethodChannel _channel = MethodChannel('gharbaar/diag');

  static Future<String> appSigningKey() async {
    try {
      return await _channel.invokeMethod<String>('signingSha1') ?? 'unknown';
    } catch (e) {
      return 'unavailable ($e)';
    }
  }
}
