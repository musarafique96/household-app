import 'dart:math' as math;

import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

import '../util.dart';
import 'data_changes.dart';
import 'models.dart';

/// Offline local database. A future online backend can replace this class
/// while the screens keep calling the same methods.
class Db {
  Db._();
  static final Db instance = Db._();

  Database? _db;

  Future<Database> get _database async {
    final existing = _db;
    if (existing != null) return existing;

    final path = join(await getDatabasesPath(), 'household.db');
    final opened = await openDatabase(
      path,
      version: 4,
      onCreate: (db, version) async {
        await db.execute(
            'CREATE TABLE users (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL, currency TEXT NOT NULL)');
        await db.execute(
            'CREATE TABLE categories (id INTEGER PRIMARY KEY AUTOINCREMENT, userId INTEGER NOT NULL, name TEXT NOT NULL, monthlyLimit REAL NOT NULL)');
        await db.execute(
            'CREATE TABLE expenses (id INTEGER PRIMARY KEY AUTOINCREMENT, userId INTEGER NOT NULL, categoryId INTEGER NOT NULL, amount REAL NOT NULL, note TEXT, date TEXT NOT NULL, currency TEXT NOT NULL DEFAULT \'\', originalAmount REAL NOT NULL DEFAULT 0)');
        await db.execute(
            'CREATE TABLE shared (id INTEGER PRIMARY KEY AUTOINCREMENT, title TEXT NOT NULL, amount REAL NOT NULL, paidBy INTEGER NOT NULL, participants TEXT NOT NULL, date TEXT NOT NULL, groupId INTEGER NOT NULL DEFAULT 0, splitMethod TEXT NOT NULL DEFAULT \'equal\', shares TEXT NOT NULL DEFAULT \'\')');
        await db.execute(
            'CREATE TABLE groups (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL)');
        await db.execute(
            'CREATE TABLE group_members (groupId INTEGER NOT NULL, userId INTEGER NOT NULL)');
        await db.execute(
            'CREATE TABLE recurring (id INTEGER PRIMARY KEY AUTOINCREMENT, userId INTEGER NOT NULL, name TEXT NOT NULL, amount REAL NOT NULL, categoryId INTEGER NOT NULL, day INTEGER NOT NULL, lastApplied TEXT NOT NULL DEFAULT \'\')');
        await db.execute(
            'CREATE TABLE exchange_rates (userId INTEGER NOT NULL, currency TEXT NOT NULL, rate REAL NOT NULL, PRIMARY KEY (userId, currency))');
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await db.execute(
              'ALTER TABLE shared ADD COLUMN groupId INTEGER NOT NULL DEFAULT 0');
          await db.execute(
              'ALTER TABLE shared ADD COLUMN splitMethod TEXT NOT NULL DEFAULT \'equal\'');
          await db.execute(
              'ALTER TABLE shared ADD COLUMN shares TEXT NOT NULL DEFAULT \'\'');
          await db.execute(
              'CREATE TABLE groups (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL)');
          await db.execute(
              'CREATE TABLE group_members (groupId INTEGER NOT NULL, userId INTEGER NOT NULL)');
        }
        if (oldVersion < 4) {
          await db.execute(
              'ALTER TABLE expenses ADD COLUMN currency TEXT NOT NULL DEFAULT \'\'');
          await db.execute(
              'ALTER TABLE expenses ADD COLUMN originalAmount REAL NOT NULL DEFAULT 0');
          await db.execute(
              'CREATE TABLE exchange_rates (userId INTEGER NOT NULL, currency TEXT NOT NULL, rate REAL NOT NULL, PRIMARY KEY (userId, currency))');
        }
        if (oldVersion < 3) {
          await db.execute(
              'CREATE TABLE recurring (id INTEGER PRIMARY KEY AUTOINCREMENT, userId INTEGER NOT NULL, name TEXT NOT NULL, amount REAL NOT NULL, categoryId INTEGER NOT NULL, day INTEGER NOT NULL, lastApplied TEXT NOT NULL DEFAULT \'\')');
        }
      },
    );
    _db = opened;
    return opened;
  }

  // Users
  Future<List<AppUser>> users() async {
    final db = await _database;
    final rows = await db.query('users', orderBy: 'id');
    return rows.map(AppUser.fromMap).toList();
  }

  Future<void> addUser(String name, String currency) async {
    final db = await _database;
    await db.insert('users', {'name': name, 'currency': currency});
    DataChanges.bump();
  }

  // Budget categories
  Future<List<Category>> categories(int userId) async {
    final db = await _database;
    final rows = await db.query(
      'categories',
      where: 'userId = ?',
      whereArgs: [userId],
      orderBy: 'id',
    );
    return rows.map(Category.fromMap).toList();
  }

  Future<void> addCategory(int userId, String name, double monthlyLimit) async {
    final db = await _database;
    await db.insert('categories', {
      'userId': userId,
      'name': name,
      'monthlyLimit': monthlyLimit,
    });
    DataChanges.bump();
  }

  // Expenses
  Future<List<Expense>> expenses(int userId, DateTime month) async {
    final db = await _database;
    final start = DateTime(month.year, month.month, 1);
    final end = DateTime(month.year, month.month + 1, 1);
    final rows = await db.query(
      'expenses',
      where: 'userId = ? AND date >= ? AND date < ?',
      whereArgs: [userId, ymd(start), ymd(end)],
      orderBy: 'date DESC, id DESC',
    );
    return rows.map(Expense.fromMap).toList();
  }

  Future<List<Expense>> recentExpenses(int userId, {int limit = 5}) async {
    final db = await _database;
    final rows = await db.query(
      'expenses',
      where: 'userId = ?',
      whereArgs: [userId],
      orderBy: 'date DESC, id DESC',
      limit: limit,
    );
    return rows.map(Expense.fromMap).toList();
  }

  /// [amount] is in the account currency. [currency] and [originalAmount]
  /// record what was entered, if it was in another currency.
  Future<void> addExpense({
    required int userId,
    required int categoryId,
    required double amount,
    required String note,
    required DateTime date,
    String currency = '',
    double? originalAmount,
  }) async {
    final db = await _database;
    await db.insert('expenses', {
      'userId': userId,
      'categoryId': categoryId,
      'amount': amount,
      'note': note,
      'date': ymd(date),
      'currency': currency,
      'originalAmount': originalAmount ?? amount,
    });
    DataChanges.bump();
  }

  // Exchange rates: how much one unit of a currency is worth in the account currency.
  Future<Map<String, double>> exchangeRates(int userId) async {
    final db = await _database;
    final rows = await db.query(
      'exchange_rates',
      where: 'userId = ?',
      whereArgs: [userId],
      orderBy: 'currency',
    );
    final result = <String, double>{};
    for (final r in rows) {
      result[r['currency'] as String] = (r['rate'] as num).toDouble();
    }
    return result;
  }

  Future<void> setExchangeRate(int userId, String currency, double rate) async {
    final db = await _database;
    await db.insert(
      'exchange_rates',
      {'userId': userId, 'currency': currency, 'rate': rate},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    DataChanges.bump();
  }

  Future<void> deleteExchangeRate(int userId, String currency) async {
    final db = await _database;
    await db.delete(
      'exchange_rates',
      where: 'userId = ? AND currency = ?',
      whereArgs: [userId, currency],
    );
    DataChanges.bump();
  }

  // Groups
  Future<List<Group>> groups() async {
    final db = await _database;
    final rows = await db.query('groups', orderBy: 'id');
    final memberRows = await db.query('group_members');
    final result = <Group>[];
    for (final r in rows) {
      final id = r['id'] as int;
      final members = [
        for (final m in memberRows)
          if (m['groupId'] == id) m['userId'] as int,
      ];
      result.add(Group(id: id, name: r['name'] as String, members: members));
    }
    return result;
  }

  Future<void> addGroup(String name, List<int> memberIds) async {
    final db = await _database;
    final id = await db.insert('groups', {'name': name});
    for (final m in memberIds) {
      await db.insert('group_members', {'groupId': id, 'userId': m});
    }
    DataChanges.bump();
  }

  Future<void> updateUser(int id, String name, String currency) async {
    final db = await _database;
    await db.update(
      'users',
      {'name': name, 'currency': currency},
      where: 'id = ?',
      whereArgs: [id],
    );
    DataChanges.bump();
  }

  Future<void> updateGroupMembers(int groupId, List<int> memberIds) async {
    final db = await _database;
    await db.transaction((txn) async {
      await txn.delete('group_members', where: 'groupId = ?', whereArgs: [groupId]);
      for (final m in memberIds) {
        await txn.insert('group_members', {'groupId': groupId, 'userId': m});
      }
    });
    DataChanges.bump();
  }

  // Recurring expenses
  Future<List<RecurringExpense>> recurring(int userId) async {
    final db = await _database;
    final rows = await db.query(
      'recurring',
      where: 'userId = ?',
      whereArgs: [userId],
      orderBy: 'id',
    );
    return rows.map(RecurringExpense.fromMap).toList();
  }

  Future<void> addRecurring({
    required int userId,
    required String name,
    required double amount,
    required int categoryId,
    required int day,
  }) async {
    final db = await _database;
    await db.insert('recurring', {
      'userId': userId,
      'name': name,
      'amount': amount,
      'categoryId': categoryId,
      'day': day,
      'lastApplied': '',
    });
    DataChanges.bump();
  }

  Future<void> deleteRecurring(int id) async {
    final db = await _database;
    await db.delete('recurring', where: 'id = ?', whereArgs: [id]);
    DataChanges.bump();
  }

  /// Adds this month's recurring expenses that are due on or before [now].
  /// Each one is added once per month. Returns how many were added.
  Future<int> applyDueRecurring(int userId, DateTime now) async {
    final db = await _database;
    final thisMonth = '${now.year}-${now.month.toString().padLeft(2, '0')}';
    final lastDay = DateTime(now.year, now.month + 1, 0).day;
    final items = await recurring(userId);
    var added = 0;
    for (final r in items) {
      final dueDay = math.min(r.day, lastDay);
      if (r.lastApplied == thisMonth || now.day < dueDay) continue;
      await db.insert('expenses', {
        'userId': userId,
        'categoryId': r.categoryId,
        'amount': r.amount,
        'note': '${r.name} (recurring)',
        'date': ymd(DateTime(now.year, now.month, dueDay)),
      });
      await db.update(
        'recurring',
        {'lastApplied': thisMonth},
        where: 'id = ?',
        whereArgs: [r.id],
      );
      added++;
    }
    if (added > 0) DataChanges.bump();
    return added;
  }

  // Split / Qattah
  Future<List<SharedExpense>> sharedExpenses() async {
    final db = await _database;
    final rows = await db.query('shared', orderBy: 'date DESC, id DESC');
    return rows.map(SharedExpense.fromMap).toList();
  }

  /// [shares] is how much each person owes. Participants are the people in [shares].
  Future<void> addShared({
    required String title,
    required double amount,
    required int paidBy,
    required Map<int, double> shares,
    required DateTime date,
    int groupId = 0,
    String splitMethod = 'equal',
  }) async {
    final db = await _database;
    final ids = shares.keys.toList();
    final sharesText = shares.entries.map((e) => '${e.key}:${e.value}').join(';');
    await db.insert('shared', {
      'title': title,
      'amount': amount,
      'paidBy': paidBy,
      'participants': ids.join(','),
      'date': ymd(date),
      'groupId': groupId,
      'splitMethod': splitMethod,
      'shares': sharesText,
    });
    DataChanges.bump();
  }
}
