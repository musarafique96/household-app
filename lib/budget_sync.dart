import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api_client.dart';
import 'cloud_auth.dart';
import 'cloud_family.dart';
import 'data/db.dart';

/// Sends budget categories and expenses from this phone to a household on the API.
///
/// This version only sends rows that have never been sent (cloudId is empty). The phone works offline first,
/// so a failed send is simply tried again on the next run. Edits and deletes are not sent yet.
/// The household is the first one this account heads. Its budget is shared by every phone in that household.
class BudgetSync {
  BudgetSync._();

  static const int _batch = 150;
  static bool _running = false;
  static Timer? _timer;
  static final Random _random = Random.secure();

  /// Waits a few seconds after a change, so several quick saves go out in one run.
  static void scheduleSoon() {
    _timer?.cancel();
    _timer = Timer(const Duration(seconds: 5), () => run());
  }

  /// Sends everything that is waiting. Does nothing when no one is signed in to the cloud.
  static Future<void> run() async {
    final uid = CloudAuth.currentUser?.uid;
    if (uid == null || uid.isEmpty || _running) return;
    _running = true;
    try {
      final householdId = await _householdFor(uid);
      if (householdId == null) return;
      await _pushCategories(householdId);
      await _pushExpenses(householdId);
    } on ApiException catch (e) {
      // 403 or 404: this account no longer manages that household, so forget it and choose again next time.
      if (e.status == 403 || e.status == 404) await _forgetHousehold(uid);
      debugPrint('Budget sync stopped: ${e.message}');
    } catch (e) {
      debugPrint('Budget sync stopped: $e');
    } finally {
      _running = false;
    }
  }

  static String _key(String uid) => 'sync_household_$uid';

  static Future<String?> _householdFor(String uid) async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_key(uid));
    if (saved != null && saved.isNotEmpty) return saved;

    final families = await CloudFamily.myFamilies();
    final heads = families.where((f) => f.isAdmin).toList();
    if (heads.isEmpty) return null;
    await prefs.setString(_key(uid), heads.first.id);
    return heads.first.id;
  }

  static Future<void> _forgetHousehold(String uid) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key(uid));
  }

  static Future<void> _pushCategories(String householdId) async {
    while (true) {
      final rows = await Db.instance.unsyncedCategories(_batch);
      if (rows.isEmpty) return;

      final ids = [for (var i = 0; i < rows.length; i++) _newId()];
      final items = [
        for (var i = 0; i < rows.length; i++)
          {
            'entity': 'budget_category',
            'entityId': ids[i],
            'operation': 'create',
            'data': {
              'name': rows[i]['name'],
              'monthlyLimit': rows[i]['monthlyLimit'],
            },
          },
      ];
      final outcomes = await _send(householdId, items);

      var applied = 0;
      for (var i = 0; i < rows.length; i++) {
        if (outcomes[i] == 'applied') {
          // A new row is version 1 on the server.
          await Db.instance.markCategorySynced(rows[i]['id'] as int, ids[i], 1);
          applied++;
        } else {
          debugPrint('Category not sent: ${rows[i]['name']} (${outcomes[i]})');
        }
      }
      // Stop when nothing was accepted, so a bad row cannot make this loop forever.
      if (applied == 0) return;
    }
  }

  static Future<void> _pushExpenses(String householdId) async {
    while (true) {
      final rows = await Db.instance.unsyncedExpenses(_batch);
      if (rows.isEmpty) return;

      final ids = [for (var i = 0; i < rows.length; i++) _newId()];
      final items = [
        for (var i = 0; i < rows.length; i++)
          {
            'entity': 'expense',
            'entityId': ids[i],
            'operation': 'create',
            'data': {
              'categoryId': rows[i]['categoryCloudId'],
              'amount': rows[i]['amount'],
              'expenseDate': rows[i]['date'],
              'note': rows[i]['note'] ?? '',
            },
          },
      ];
      final outcomes = await _send(householdId, items);

      var applied = 0;
      for (var i = 0; i < rows.length; i++) {
        if (outcomes[i] == 'applied') {
          await Db.instance.markExpenseSynced(rows[i]['id'] as int, ids[i], 1);
          applied++;
        } else {
          debugPrint('Expense not sent: ${rows[i]['id']} (${outcomes[i]})');
        }
      }
      if (applied == 0) return;
    }
  }

  /// Returns the outcome for each item in order: 'applied', 'conflict' or 'invalid'.
  static Future<List<String>> _send(String householdId, List<Map<String, Object?>> items) async {
    final response = await ApiClient.post('/households/$householdId/sync', items) as Map<String, dynamic>;
    final results = response['results'] as List<dynamic>;
    return [for (final r in results) (r as Map<String, dynamic>)['outcome'] as String];
  }

  /// A random version 4 ID, in the form the server expects for a new row.
  static String _newId() {
    final b = List<int>.generate(16, (_) => _random.nextInt(256));
    b[6] = (b[6] & 0x0f) | 0x40;
    b[8] = (b[8] & 0x3f) | 0x80;
    final h = b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
    return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-'
        '${h.substring(16, 20)}-${h.substring(20)}';
  }
}
