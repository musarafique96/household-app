// Plain data classes. Each user has their own currency and their own budget.

class AppUser {
  final int id;
  final String name;
  final String currency;

  const AppUser({required this.id, required this.name, required this.currency});

  factory AppUser.fromMap(Map<String, Object?> m) => AppUser(
        id: m['id'] as int,
        name: m['name'] as String,
        currency: m['currency'] as String,
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

  const Expense({
    required this.id,
    required this.userId,
    required this.categoryId,
    required this.amount,
    required this.note,
    required this.date,
  });

  factory Expense.fromMap(Map<String, Object?> m) => Expense(
        id: m['id'] as int,
        userId: m['userId'] as int,
        categoryId: m['categoryId'] as int,
        amount: (m['amount'] as num).toDouble(),
        note: (m['note'] as String?) ?? '',
        date: DateTime.parse(m['date'] as String),
      );
}

// A shared expense (Split / Qattah): one person paid, and the cost is split equally.
class SharedExpense {
  final int id;
  final String title;
  final double amount;
  final int paidBy;
  final List<int> participants;
  final DateTime date;

  const SharedExpense({
    required this.id,
    required this.title,
    required this.amount,
    required this.paidBy,
    required this.participants,
    required this.date,
  });

  factory SharedExpense.fromMap(Map<String, Object?> m) => SharedExpense(
        id: m['id'] as int,
        title: m['title'] as String,
        amount: (m['amount'] as num).toDouble(),
        paidBy: m['paidBy'] as int,
        participants: (m['participants'] as String)
            .split(',')
            .where((s) => s.isNotEmpty)
            .map(int.parse)
            .toList(),
        date: DateTime.parse(m['date'] as String),
      );
}
