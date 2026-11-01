import 'data/models.dart';
import 'util.dart';

/// One budget category with what has been spent in the month.
class CategoryRow {
  final String name;
  final double spent;
  final double limit;

  const CategoryRow({required this.name, required this.spent, required this.limit});

  bool get over => limit > 0 && spent > limit;

  double get progress {
    if (limit <= 0) return 0;
    return (spent / limit).clamp(0.0, 1.0).toDouble();
  }
}

List<CategoryRow> buildRows(List<Category> categories, List<Expense> expenses) {
  return categories.map((c) {
    final spent = expenses
        .where((e) => e.categoryId == c.id)
        .fold<double>(0.0, (sum, e) => sum + e.amount);
    return CategoryRow(name: c.name, spent: spent, limit: c.monthlyLimit);
  }).toList();
}

/// Plain-language suggestions on where to save or cut.
List<String> buildTips(List<CategoryRow> rows, String currency) {
  final tips = <String>[];

  for (final r in rows.where((r) => r.over)) {
    tips.add('${r.name} is over its limit. Cutting it back would help most.');
  }

  for (final r in rows.where((r) => r.limit > 0 && !r.over && r.spent >= r.limit * 0.8)) {
    tips.add('${r.name} is above 80% of its limit. Watch it for the rest of the month.');
  }

  if (rows.isNotEmpty) {
    final biggest = rows.reduce((a, b) => a.spent >= b.spent ? a : b);
    if (biggest.spent > 0) {
      tips.add('${biggest.name} is your biggest spend this month (${money(biggest.spent, currency)}).');
    }
  }

  return tips;
}
