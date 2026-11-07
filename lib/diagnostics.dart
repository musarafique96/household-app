import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/services.dart';

/// Reads the signing key this app was built with, so sign-in problems can be checked.
class Diagnostics {
  Diagnostics._();

  static const MethodChannel _channel = MethodChannel('gharbaar/diag');

  /// Saves a short note to the "diagnostics" collection, so it can be read in the Firebase console.
  static Future<void> saveNote(String text) async {
    try {
      await FirebaseFirestore.instance.collection('diagnostics').add({
        'text': text.length > 1900 ? text.substring(0, 1900) : text,
        'at': DateTime.now().toIso8601String(),
      });
    } catch (_) {}
  }

  static Future<String> appSigningKey() async {
    try {
      return await _channel.invokeMethod<String>('signingSha1') ?? 'unknown';
    } catch (e) {
      return 'unavailable ($e)';
    }
  }
}
