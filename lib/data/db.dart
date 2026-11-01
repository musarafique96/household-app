import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

import '../util.dart';
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
      version: 1,
      onCreate: (db, version) async {
        await db.execute(
            'CREATE TABLE users (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL, currency TEXT NOT NULL)');
        await db.execute(
            'CREATE TABLE categories (id INTEGER PRIMARY KEY AUTOINCREMENT, userId INTEGER NOT NULL, name TEXT NOT NULL, monthlyLimit REAL NOT NULL)');
        await db.execute(
            'CREATE TABLE expenses (id INTEGER PRIMARY KEY AUTOINCREMENT, userId INTEGER NOT NULL, categoryId INTEGER NOT NULL, amount REAL NOT NULL, note TEXT, date TEXT NOT NULL)');
        await db.execute(
            'CREATE TABLE shared (id INTEGER PRIMARY KEY AUTOINCREMENT, title TEXT NOT NULL, amount REAL NOT NULL, paidBy INTEGER NOT NULL, participants TEXT NOT NULL, date TEXT NOT NULL)');
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

  Future<void> addExpense({
    required int userId,
    required int categoryId,
    required double amount,
    required String note,
    required DateTime date,
  }) async {
    final db = await _database;
    await db.insert('expenses', {
      'userId': userId,
      'categoryId': categoryId,
      'amount': amount,
      'note': note,
      'date': ymd(date),
    });
  }

  // Split / Qattah
  Future<List<SharedExpense>> sharedExpenses() async {
    final db = await _database;
    final rows = await db.query('shared', orderBy: 'date DESC, id DESC');
    return rows.map(SharedExpense.fromMap).toList();
  }

  Future<void> addShared({
    required String title,
    required double amount,
    required int paidBy,
    required List<int> participants,
    required DateTime date,
  }) async {
    final db = await _database;
    await db.insert('shared', {
      'title': title,
      'amount': amount,
      'paidBy': paidBy,
      'participants': participants.join(','),
      'date': ymd(date),
    });
  }
}
