// Plain data classes. Each user has their own currency and their own budget.

class AppUser {
  final int id;
  final String name;
  final String currency;

  final String phone;
  final String email;
  final String address;
  /// yyyy-MM-dd, or '' if not given.
  final String dateOfBirth;

  const AppUser({
    required this.id,
    required this.name,
    required this.currency,
    this.phone = '',
    this.email = '',
    this.address = '',
    this.dateOfBirth = '',
  });

  factory AppUser.fromMap(Map<String, Object?> m) => AppUser(
        id: m['id'] as int,
        name: m['name'] as String,
        currency: m['currency'] as String,
        phone: (m['phone'] as String?) ?? '',
        email: (m['email'] as String?) ?? '',
        address: (m['address'] as String?) ?? '',
        dateOfBirth: (m['dateOfBirth'] as String?) ?? '',
      );
}

class Category {
  final int id;
  final int userId;
  final String name;
  final double monthlyLimit;

  const Category({
    required this.id,
    required this.userId,
    required this.name,
    required this.monthlyLimit,
  });

  factory Category.fromMap(Map<String, Object?> m) => Category(
        id: m['id'] as int,
        userId: m['userId'] as int,
        name: m['name'] as String,
        monthlyLimit: (m['monthlyLimit'] as num).toDouble(),
      );
}

class Expense {
  final int id;
  final int userId;
  final int categoryId;
  final double amount;
  final String note;
  final DateTime date;

  /// Currency the expense was entered in. '' means the account currency.
  final String currency;

  /// Amount in [currency]. [amount] is always in the account currency.
  final double originalAmount;

  const Expense({
    required this.id,
    required this.userId,
    required this.categoryId,
    required this.amount,
    required this.note,
    required this.date,
    this.currency = '',
    this.originalAmount = 0.0,
  });

  factory Expense.fromMap(Map<String, Object?> m) => Expense(
        id: m['id'] as int,
        userId: m['userId'] as int,
        categoryId: m['categoryId'] as int,
        amount: (m['amount'] as num).toDouble(),
        note: (m['note'] as String?) ?? '',
        date: DateTime.parse(m['date'] as String),
        currency: (m['currency'] as String?) ?? '',
        originalAmount: ((m['originalAmount'] as num?) ?? 0).toDouble(),
      );
}

/// An expense that is added automatically each month on a set day.
/// [lastApplied] is the month it was last added, as yyyy-MM ('' if never).
class RecurringExpense {
  final int id;
  final int userId;
  final String name;
  final double amount;
  final int categoryId;
  final int day;
  final String lastApplied;

  const RecurringExpense({
    required this.id,
    required this.userId,
    required this.name,
    required this.amount,
    required this.categoryId,
    required this.day,
    required this.lastApplied,
  });

  factory RecurringExpense.fromMap(Map<String, Object?> m) => RecurringExpense(
        id: m['id'] as int,
        userId: m['userId'] as int,
        name: m['name'] as String,
        amount: (m['amount'] as num).toDouble(),
        categoryId: m['categoryId'] as int,
        day: m['day'] as int,
        lastApplied: (m['lastApplied'] as String?) ?? '',
      );
}

/// A group of people who share expenses, such as a family or a trip.
class Group {
  final int id;
  final String name;
  final List<int> members;

  const Group({required this.id, required this.name, required this.members});
}

/// A shared expense (Split / Qattah).
/// [splitMethod] is 'equal', 'amount', 'percent', or 'settlement'.
/// [shares] is how much each person owes. A settlement is a payment from the
/// person who paid to the person it was paid to.
class SharedExpense {
  final int id;
  final String title;
  final double amount;
  final int paidBy;
  final List<int> participants;
  final DateTime date;
  final int groupId;
  final String splitMethod;
  final Map<int, double> shares;

  const SharedExpense({
    required this.id,
    required this.title,
    required this.amount,
    required this.paidBy,
    required this.participants,
    required this.date,
    required this.groupId,
    required this.splitMethod,
    required this.shares,
  });

  bool get isSettlement => splitMethod == 'settlement';

  /// Amount each person owes. Rows saved before shares existed are split equally.
  Map<int, double> get owed {
    if (shares.isNotEmpty) return shares;
    if (participants.isEmpty) return const {};
    final each = amount / participants.length;
    return {for (final p in participants) p: each};
  }

  factory SharedExpense.fromMap(Map<String, Object?> m) {
    final participants = (m['participants'] as String)
        .split(',')
        .where((s) => s.isNotEmpty)
        .map(int.parse)
        .toList();

    final shares = <int, double>{};
    final raw = (m['shares'] as String?) ?? '';
    for (final pair in raw.split(';')) {
      final parts = pair.split(':');
      if (parts.length == 2) {
        shares[int.parse(parts[0])] = double.parse(parts[1]);
      }
    }

    return SharedExpense(
      id: m['id'] as int,
      title: m['title'] as String,
      amount: (m['amount'] as num).toDouble(),
      paidBy: m['paidBy'] as int,
      participants: participants,
      date: DateTime.parse(m['date'] as String),
      groupId: (m['groupId'] as int?) ?? 0,
      splitMethod: (m['splitMethod'] as String?) ?? 'equal',
      shares: shares,
    );
  }
}
