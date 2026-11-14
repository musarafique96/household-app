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
/// Sent, in this order for categories and then expenses: new rows, edits, deletions.
/// The phone works offline first, so anything not accepted stays on the phone and is tried again on the next run.
/// The household is the first of your households that accepts the send. A family member who may only view
/// the budget gets refused and the next household is tried.
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
      for (final householdId in await _householdsToTry(uid)) {
        try {
          final sent = await _pushAll(householdId);
          if (sent > 0) await _remember(uid, householdId);
          return;
        } on ApiException catch (e) {
          // 403: this account may not edit that budget. 404: that household no longer exists. Try the next one.
          if (e.status == 403 || e.status == 404) continue;
          rethrow;
        }
      }
    } catch (e) {
      debugPrint('Budget sync stopped: $e');
    } finally {
      _running = false;
    }
  }

  static String _key(String uid) => 'sync_household_$uid';

  /// The household used last time comes first, then the rest of your households.
  static Future<List<String>> _householdsToTry(String uid) async {
    final ids = (await CloudFamily.myFamilies()).map((f) => f.id).toList();
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_key(uid));
    if (saved != null && ids.remove(saved)) ids.insert(0, saved);
    return ids;
  }

  static Future<void> _remember(String uid, String householdId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key(uid), householdId);
  }

  /// Returns how many rows were sent. Zero means nothing was waiting, so no request was made.
  static Future<int> _pushAll(String householdId) async {
    var sent = 0;
    sent += await _pushCategories(householdId);
    sent += await _pushExpenses(householdId);
    return sent;
  }

  static Future<int> _pushCategories(String h) async {
    var sent = 0;

    // New categories.
    await _drain(() => Db.instance.unsyncedCategories(_batch), (rows) async {
      final ids = [for (var i = 0; i < rows.length; i++) _newId()];
      final outcomes = await _send(h, [
        for (var i = 0; i < rows.length; i++)
          {
            'entity': 'budget_category',
            'entityId': ids[i],
            'operation': 'create',
            'data': {'name': rows[i]['name'], 'monthlyLimit': rows[i]['monthlyLimit']},
          },
      ]);
      sent += rows.length;
      var applied = 0;
      for (var i = 0; i < rows.length; i++) {
        if (outcomes[i] == 'applied') {
          await Db.instance.markCategorySynced(rows[i]['id'] as int, ids[i], 1);
          applied++;
        } else {
          debugPrint('Category not sent: ${rows[i]['name']} (${outcomes[i]})');
        }
      }
      return applied;
    });

    // Edited categories.
    await _drain(() => Db.instance.dirtyCategories(_batch), (rows) async {
      final outcomes = await _send(h, [
        for (final r in rows)
          {
            'entity': 'budget_category',
            'entityId': r['cloudId'],
            'operation': 'update',
            'baseVersion': r['cloudVersion'],
            'data': {'name': r['name'], 'monthlyLimit': r['monthlyLimit']},
          },
      ]);
      sent += rows.length;
      return _recordEdits(rows, outcomes, (id, cloudId, version) async {
        await Db.instance.markCategorySynced(id, cloudId, version);
      }, (id) => Db.instance.clearDirty('categories', id));
    });

    // Deleted categories.
    await _drain(() => Db.instance.pendingDeletes('budget_category', _batch), (rows) async {
      final outcomes = await _send(h, [
        for (final r in rows)
          {
            'entity': 'budget_category',
            'entityId': r['cloudId'],
            'operation': 'delete',
            'baseVersion': r['cloudVersion'],
          },
      ]);
      sent += rows.length;
      return _recordDeletes('budget_category', rows, outcomes);
    });

    return sent;
  }

  static Future<int> _pushExpenses(String h) async {
    var sent = 0;

    // New expenses.
    await _drain(() => Db.instance.unsyncedExpenses(_batch), (rows) async {
      final ids = [for (var i = 0; i < rows.length; i++) _newId()];
      final outcomes = await _send(h, [
        for (var i = 0; i < rows.length; i++)
          {
            'entity': 'expense',
            'entityId': ids[i],
            'operation': 'create',
            'data': _expenseData(rows[i]),
          },
      ]);
      sent += rows.length;
      var applied = 0;
      for (var i = 0; i < rows.length; i++) {
        if (outcomes[i] == 'applied') {
          await Db.instance.markExpenseSynced(rows[i]['id'] as int, ids[i], 1);
          applied++;
        } else {
          debugPrint('Expense not sent: ${rows[i]['id']} (${outcomes[i]})');
        }
      }
      return applied;
    });

    // Edited expenses.
    await _drain(() => Db.instance.dirtyExpenses(_batch), (rows) async {
      final outcomes = await _send(h, [
        for (final r in rows)
          {
            'entity': 'expense',
            'entityId': r['cloudId'],
            'operation': 'update',
            'baseVersion': r['cloudVersion'],
            'data': _expenseData(r),
          },
      ]);
      sent += rows.length;
      return _recordEdits(rows, outcomes, (id, cloudId, version) async {
        await Db.instance.markExpenseSynced(id, cloudId, version);
      }, (id) => Db.instance.clearDirty('expenses', id));
    });

    // Deleted expenses.
    await _drain(() => Db.instance.pendingDeletes('expense', _batch), (rows) async {
      final outcomes = await _send(h, [
        for (final r in rows)
          {
            'entity': 'expense',
            'entityId': r['cloudId'],
            'operation': 'delete',
            'baseVersion': r['cloudVersion'],
          },
      ]);
      sent += rows.length;
      return _recordDeletes('expense', rows, outcomes);
    });

    return sent;
  }

  static Map<String, Object?> _expenseData(Map<String, Object?> r) => {
        'categoryId': r['categoryCloudId'],
        'amount': r['amount'],
        'expenseDate': r['date'],
        'note': r['note'] ?? '',
      };

  /// An accepted edit goes up one version. A refused edit is kept on the server for review, so it is not sent again.
  static Future<int> _recordEdits(
    List<Map<String, Object?>> rows,
    List<String> outcomes,
    Future<void> Function(int id, String cloudId, int version) markAccepted,
    Future<void> Function(int id) clear,
  ) async {
    var done = 0;
    for (var i = 0; i < rows.length; i++) {
      final id = rows[i]['id'] as int;
      if (outcomes[i] == 'applied') {
        await markAccepted(id, rows[i]['cloudId'] as String, (rows[i]['cloudVersion'] as int) + 1);
        done++;
      } else if (outcomes[i] == 'conflict') {
        await clear(id);
        done++;
      } else {
        debugPrint('Edit not sent: $id (${outcomes[i]})');
      }
    }
    return done;
  }

  /// A deletion is finished when accepted, or when the cloud kept its own version (the conflict is on the server).
  static Future<int> _recordDeletes(String entity, List<Map<String, Object?>> rows, List<String> outcomes) async {
    var done = 0;
    for (var i = 0; i < rows.length; i++) {
      if (outcomes[i] == 'applied' || outcomes[i] == 'conflict') {
        await Db.instance.finishDelete(entity, rows[i]['cloudId'] as String);
        done++;
      } else {
        debugPrint('Deletion not sent: $entity (${outcomes[i]})');
      }
    }
    return done;
  }

  /// Runs [send] on batches until a batch makes no progress, so a row the cloud refuses cannot loop forever.
  static Future<void> _drain(
    Future<List<Map<String, Object?>>> Function() fetch,
    Future<int> Function(List<Map<String, Object?>> rows) send,
  ) async {
    while (true) {
      final rows = await fetch();
      if (rows.isEmpty) return;
      if (await send(rows) == 0) return;
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
