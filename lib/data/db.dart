import 'dart:math' as math;

import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

import '../util.dart';
import '../auth.dart';
import 'data_changes.dart';
import 'models.dart';

/// Offline local database. A future online backend can replace this class
/// while the screens keep calling the same methods.
/// The one account that is the app admin (its Gmail, also its cloud sign-in).
const String kAdminEmail = 'rafique.musa96@gmail.com';

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
      version: 12,
      onCreate: (db, version) async {
        await db.execute(
            'CREATE TABLE users (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL, currency TEXT NOT NULL, phone TEXT NOT NULL DEFAULT \'\', email TEXT NOT NULL DEFAULT \'\', address TEXT NOT NULL DEFAULT \'\', dateOfBirth TEXT NOT NULL DEFAULT \'\', username TEXT NOT NULL DEFAULT \'\', passwordHash TEXT NOT NULL DEFAULT \'\', salt TEXT NOT NULL DEFAULT \'\', role TEXT NOT NULL DEFAULT \'member\', deleted INTEGER NOT NULL DEFAULT 0, passkeyHash TEXT NOT NULL DEFAULT \'\', passkeySalt TEXT NOT NULL DEFAULT \'\', passkeyEnabled INTEGER NOT NULL DEFAULT 0, cloudUid TEXT NOT NULL DEFAULT \'\')');
        await db.execute(
            'CREATE TABLE categories (id INTEGER PRIMARY KEY AUTOINCREMENT, userId INTEGER NOT NULL, name TEXT NOT NULL, monthlyLimit REAL NOT NULL, cloudId TEXT NOT NULL DEFAULT \'\', cloudVersion INTEGER NOT NULL DEFAULT 0)');
        await db.execute(
            'CREATE TABLE expenses (id INTEGER PRIMARY KEY AUTOINCREMENT, userId INTEGER NOT NULL, categoryId INTEGER NOT NULL, amount REAL NOT NULL, note TEXT, date TEXT NOT NULL, currency TEXT NOT NULL DEFAULT \'\', originalAmount REAL NOT NULL DEFAULT 0, cloudId TEXT NOT NULL DEFAULT \'\', cloudVersion INTEGER NOT NULL DEFAULT 0)');
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
        // Budget rows get a cloud ID once they are sent to the household on the API. '' means not sent yet.
        if (oldVersion < 12) {
          for (final table in ['categories', 'expenses']) {
            await db.execute("ALTER TABLE $table ADD COLUMN cloudId TEXT NOT NULL DEFAULT ''");
            await db.execute('ALTER TABLE $table ADD COLUMN cloudVersion INTEGER NOT NULL DEFAULT 0');
          }
        }
        // The cloud account ID moved from Firebase to the API, so the column is renamed to match.
        if (oldVersion < 11) {
          await db.execute('ALTER TABLE users RENAME COLUMN firebaseUid TO cloudUid');
        }
        if (oldVersion < 10) {
          await db.execute("ALTER TABLE users ADD COLUMN firebaseUid TEXT NOT NULL DEFAULT ''");
        }
        if (oldVersion < 9) {
          await db.execute("ALTER TABLE users ADD COLUMN passkeyHash TEXT NOT NULL DEFAULT ''");
          await db.execute("ALTER TABLE users ADD COLUMN passkeySalt TEXT NOT NULL DEFAULT ''");
          await db.execute('ALTER TABLE users ADD COLUMN passkeyEnabled INTEGER NOT NULL DEFAULT 0');
        }
        if (oldVersion < 8) {
          await db.execute('ALTER TABLE users ADD COLUMN deleted INTEGER NOT NULL DEFAULT 0');
        }
        if (oldVersion < 7) {
          await db.execute("ALTER TABLE users ADD COLUMN role TEXT NOT NULL DEFAULT 'member'");
        }
        if (oldVersion < 6) {
          for (final col in ['username', 'passwordHash', 'salt']) {
            await db.execute("ALTER TABLE users ADD COLUMN $col TEXT NOT NULL DEFAULT ''");
          }
          // Existing accounts get a username from their name, e.g. musa_1.
          await db.execute("UPDATE users SET username = lower(replace(name, ' ', '')) || '_' || id WHERE username = ''");
        }
        if (oldVersion < 5) {
          for (final col in ['phone', 'email', 'address', 'dateOfBirth']) {
            await db.execute("ALTER TABLE users ADD COLUMN $col TEXT NOT NULL DEFAULT ''");
          }
        }
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

  /// Adds a new account (when [AppUser.id] is 0) or updates an existing one.
  /// Pass [password] to set or change the password; it is stored hashed.
  /// Returns the saved account with its id.
  Future<AppUser> saveUser(AppUser user, {String? password}) async {
    final db = await _database;
    final values = <String, Object?>{
      'username': user.username,
      'role': user.role,
      'deleted': user.deleted ? 1 : 0,
      'name': user.name,
      'currency': user.currency,
      'phone': user.phone,
      'email': user.email,
      'address': user.address,
      'dateOfBirth': user.dateOfBirth,
    };
    if (password != null) {
      final salt = Auth.newSalt();
      values['salt'] = salt;
      values['passwordHash'] = Auth.hash(salt, password);
    }
    final int id;
    if (user.id == 0) {
      id = await db.insert('users', values);
    } else {
      await db.update('users', values, where: 'id = ?', whereArgs: [user.id]);
      id = user.id;
    }
    DataChanges.bump();
    return AppUser(
      id: id,
      username: user.username,
      role: user.role,
      deleted: user.deleted,
      name: user.name,
      currency: user.currency,
      phone: user.phone,
      email: user.email,
      address: user.address,
      dateOfBirth: user.dateOfBirth,
    );
  }

  /// Links this local account to its cloud account (the API user ID).
  Future<void> setCloudUid(int userId, String uid) async {
    final db = await _database;
    await db.update('users', {'cloudUid': uid}, where: 'id = ?', whereArgs: [userId]);
    DataChanges.bump();
  }

  /// Removes a member's personal details and login data. The row stays, named "Deleted member",
  /// so their past expenses and reports still make sense.
  Future<void> anonymizeUser(int userId) async {
    final db = await _database;
    await db.update(
      'users',
      {
        'name': 'Deleted member',
        'username': '',
        'passwordHash': '',
        'salt': '',
        'passkeyHash': '',
        'passkeySalt': '',
        'passkeyEnabled': 0,
        'phone': '',
        'email': '',
        'address': '',
        'dateOfBirth': '',
        'cloudUid': '',
        'deleted': 1,
      },
      where: 'id = ?',
      whereArgs: [userId],
    );
    await db.delete('recurring', where: 'userId = ?', whereArgs: [userId]);
    await db.delete('exchange_rates', where: 'userId = ?', whereArgs: [userId]);
    await db.delete('group_members', where: 'userId = ?', whereArgs: [userId]);
    DataChanges.bump();
  }

  /// Deletes an account. Its expenses, budgets and history are kept so monthly
  /// totals and reports stay correct, but it can no longer sign in or add anything.
  Future<void> deleteUser(int id) async {
    final db = await _database;
    await db.update('users', {'deleted': 1}, where: 'id = ?', whereArgs: [id]);
    DataChanges.bump();
  }

  /// Saves a new 6-digit passkey for the account and switches it on.
  Future<void> setPasskey(int userId, String pin) async {
    final db = await _database;
    final salt = Auth.newSalt();
    await db.update(
      'users',
      {'passkeySalt': salt, 'passkeyHash': Auth.hash(salt, pin), 'passkeyEnabled': 1},
      where: 'id = ?',
      whereArgs: [userId],
    );
    DataChanges.bump();
  }

  Future<void> setPasskeyEnabled(int userId, bool on) async {
    final db = await _database;
    await db.update('users', {'passkeyEnabled': on ? 1 : 0},
        where: 'id = ?', whereArgs: [userId]);
    DataChanges.bump();
  }

  /// True if [pin] matches the account's saved passkey.
  Future<bool> checkPasskey(int userId, String pin) async {
    final db = await _database;
    final rows = await db.query('users',
        columns: ['passkeyHash', 'passkeySalt'],
        where: 'id = ?',
        whereArgs: [userId],
        limit: 1);
    if (rows.isEmpty) return false;
    final hash = (rows.first['passkeyHash'] as String?) ?? '';
    if (hash.isEmpty) return false;
    return Auth.verify((rows.first['passkeySalt'] as String?) ?? '', hash, pin);
  }

  /// Accounts that can still be used. Deleted accounts are left out.
  Future<List<AppUser>> activeUsers() async {
    final db = await _database;
    final rows = await db.query('users', where: 'deleted = 0', orderBy: 'id');
    return rows.map(AppUser.fromMap).toList();
  }

  /// Admin is this Gmail account only. Every other account is a member.
  /// Runs at startup and after Google sign-in.
  Future<void> applyAdminEmail() async {
    final db = await _database;
    await db.update('users', {'role': 'member'},
        where: "role = 'admin' AND lower(email) != ?", whereArgs: [kAdminEmail]);
    await db.update('users', {'role': 'admin'},
        where: 'lower(email) = ?', whereArgs: [kAdminEmail]);
    DataChanges.bump();
  }

  /// Finds an account by username, ignoring case. Null if none.
  Future<AppUser?> findByUsername(String username) async {
    final db = await _database;
    final rows = await db.query(
      'users',
      where: 'username = ? COLLATE NOCASE',
      whereArgs: [username.trim()],
      limit: 1,
    );
    return rows.isEmpty ? null : AppUser.fromMap(rows.first);
  }

  /// The account plus its stored password hash and salt, for sign-in checks.
  Future<({AppUser user, String passwordHash, String salt})?> credentialsFor(
      String username) async {
    final db = await _database;
    final rows = await db.query(
      'users',
      where: 'username = ? COLLATE NOCASE AND deleted = 0',
      whereArgs: [username.trim()],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final r = rows.first;
    return (
      user: AppUser.fromMap(r),
      passwordHash: (r['passwordHash'] as String?) ?? '',
      salt: (r['salt'] as String?) ?? '',
    );
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

  // Budget sync (see budget_sync.dart): rows that have not been sent to the household yet.
  Future<List<Map<String, Object?>>> unsyncedCategories(int limit) async {
    final db = await _database;
    return db.query(
      'categories',
      where: "cloudId = ''",
      orderBy: 'id',
      limit: limit,
    );
  }

  /// Expenses not sent yet, with the cloud ID of their category. An expense waits until its category is in the cloud.
  Future<List<Map<String, Object?>>> unsyncedExpenses(int limit) async {
    final db = await _database;
    return db.rawQuery(
      '''
      SELECT e.id, e.amount, e.date, e.note, c.cloudId AS categoryCloudId
      FROM expenses e JOIN categories c ON c.id = e.categoryId
      WHERE e.cloudId = '' AND c.cloudId != ''
      ORDER BY e.id
      LIMIT ?
      ''',
      [limit],
    );
  }

  Future<void> markCategorySynced(int id, String cloudId, int version) async {
    final db = await _database;
    await db.update(
      'categories',
      {'cloudId': cloudId, 'cloudVersion': version},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> markExpenseSynced(int id, String cloudId, int version) async {
    final db = await _database;
    await db.update(
      'expenses',
      {'cloudId': cloudId, 'cloudVersion': version},
      where: 'id = ?',
      whereArgs: [id],
    );
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
