import 'package:flutter/material.dart';

import '../budget_math.dart';
import '../data/db.dart';
import '../data/models.dart';
import '../session.dart';
import '../theme.dart';
import '../util.dart';
import '../widgets/donut.dart';
import '../widgets/fancy.dart';
import '../widgets/ui.dart';

class _BudgetData {
  final List<Category> categories;
  final List<Expense> expenses;
  const _BudgetData(this.categories, this.expenses);
}

const List<Color> _palette = [
  AppColors.primary,
  AppColors.amber,
  AppColors.green,
  AppColors.blue,
  AppColors.pink,
];

IconData _iconFor(String name) {
  final n = name.toLowerCase();
  if (n.contains('food') || n.contains('dining') || n.contains('restaurant')) {
    return Icons.restaurant_rounded;
  }
  if (n.contains('transport') || n.contains('car') || n.contains('fuel')) {
    return Icons.directions_car_rounded;
  }
  if (n.contains('grocer')) return Icons.shopping_cart_rounded;
  if (n.contains('bill') || n.contains('utilit')) return Icons.bolt_rounded;
  if (n.contains('health')) return Icons.favorite_rounded;
  return Icons.category_rounded;
}

class BudgetScreen extends StatefulWidget {
  const BudgetScreen({super.key});

  @override
  State<BudgetScreen> createState() => _BudgetScreenState();
}

class _BudgetScreenState extends State<BudgetScreen> {
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month, 1);
  late Future<_BudgetData?> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<_BudgetData?> _load() async {
    final user = Session.current.value;
    if (user == null) return null;
    final cats = await Db.instance.categories(user.id);
    final exps = await Db.instance.expenses(user.id, _month);
    return _BudgetData(cats, exps);
  }

  void _shiftMonth(int delta) {
    setState(() {
      _month = DateTime(_month.year, _month.month + delta, 1);
      _future = _load();
    });
  }

  void _refresh() {
    setState(() {
      _future = _load();
    });
  }

  Future<void> _addCategory() async {
    final user = Session.current.value;
    if (user == null) return;

    final nameCtrl = TextEditingController();
    final limitCtrl = TextEditingController();
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => FancyAlert(
        title: const Text('New budget category'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameCtrl,
              decoration: const InputDecoration(labelText: 'Name (e.g. Groceries)'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: limitCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(labelText: 'Monthly limit (${user.currency})'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Save')),
        ],
      ),
    );

    final name = nameCtrl.text.trim();
    final limit = double.tryParse(limitCtrl.text.trim());
    if (saved == true && name.isNotEmpty && limit != null && limit > 0) {
      await Db.instance.addCategory(user.id, name, limit);
      _refresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AppUser?>(
      valueListenable: Session.current,
      builder: (context, user, _) {
        if (user == null) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text('Choose an account in the Accounts tab first.'),
            ),
          );
        }

        return FutureBuilder<_BudgetData?>(
          future: _future,
          builder: (context, snap) {
            final cur = user.currency;
            final data = snap.data;
            final rows = data == null ? <CategoryRow>[] : buildRows(data.categories, data.expenses);
            final spent = data == null
                ? 0.0
                : data.expenses.fold<double>(0.0, (s, e) => s + e.amount);
            final budget = rows.fold<double>(0.0, (s, r) => s + r.limit);
            final used = budget <= 0 ? 0.0 : (spent / budget).clamp(0.0, 1.0).toDouble();
            final left = budget - spent;

            return ListView(
              padding: EdgeInsets.zero,
              children: [
                GradientHeader(
                  child: Column(
                    children: [
                      Row(
                        children: [
                          const Text('Budget',
                              style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 22,
                                  fontWeight: FontWeight.w800)),
                          const Spacer(),
                          IconButton(
                            tooltip: 'Add category',
                            onPressed: _addCategory,
                            icon: const Icon(Icons.add_rounded, color: Colors.white),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          IconButton(
                            onPressed: () => _shiftMonth(-1),
                            icon: const Icon(Icons.chevron_left_rounded, color: Colors.white),
                          ),
                          Text(monthLabel(_month),
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 18,
                                  fontWeight: FontWeight.w700)),
                          IconButton(
                            onPressed: () => _shiftMonth(1),
                            icon: const Icon(Icons.chevron_right_rounded, color: Colors.white),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SoftCard(
                        child: Row(
                          children: [
                            DonutChart(
                              value: used,
                              size: 124,
                              color: AppColors.primary,
                              track: AppColors.soft,
                              center: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text('${(used * 100).round()}%',
                                      style: const TextStyle(
                                          fontSize: 22, fontWeight: FontWeight.w800)),
                                  const Text('Used',
                                      style: TextStyle(color: AppColors.muted, fontSize: 12)),
                                ],
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                children: [
                                  _LegendRow(
                                      color: AppColors.primary,
                                      label: 'Spent',
                                      value: money(spent, cur)),
                                  _LegendRow(
                                      color: AppColors.blue,
                                      label: 'Budget',
                                      value: money(budget, cur)),
                                  _LegendRow(
                                      color: AppColors.green,
                                      label: 'Left',
                                      value: money(left, cur),
                                      valueColor: left >= 0 ? AppColors.green : AppColors.red),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),
                      const SectionTitle(title: 'Category Budget'),
                      const SizedBox(height: 8),
                      if (rows.isEmpty)
                        const SoftCard(
                          child: Text('No budget categories yet. Tap + to add one.'),
                        ),
                      for (var i = 0; i < rows.length; i++)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: _CategoryTile(
                            row: rows[i],
                            color: _palette[i % _palette.length],
                            currency: cur,
                          ),
                        ),
                      const SizedBox(height: 8),
                      FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        onPressed: _addCategory,
                        icon: const Icon(Icons.add_rounded),
                        label: const Text('Add Budget Category'),
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }
}

class _LegendRow extends StatelessWidget {
  final Color color;
  final String label;
  final String value;
  final Color? valueColor;

  const _LegendRow({
    required this.color,
    required this.label,
    required this.value,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(label, style: const TextStyle(color: AppColors.muted, fontSize: 13)),
          ),
          Flexible(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(value,
                  style: TextStyle(fontWeight: FontWeight.w800, color: valueColor)),
            ),
          ),
        ],
      ),
    );
  }
}

class _CategoryTile extends StatelessWidget {
  final CategoryRow row;
  final Color color;
  final String currency;

  const _CategoryTile({required this.row, required this.color, required this.currency});

  @override
  Widget build(BuildContext context) {
    final percent = row.limit <= 0 ? 0 : (row.spent / row.limit * 100).round();
    return SoftCard(
      child: Row(
        children: [
          IconBubble(icon: _iconFor(row.name), color: color),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(row.name,
                          style: const TextStyle(fontWeight: FontWeight.w700)),
                    ),
                    Text('${money(row.spent, currency)} / ${money(row.limit, currency)}',
                        style: const TextStyle(color: AppColors.muted, fontSize: 12)),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: LinearProgressIndicator(
                        value: row.progress,
                        minHeight: 8,
                        color: row.over ? AppColors.red : color,
                        backgroundColor: color.withValues(alpha: 0.15),
                      ),
                    ),
                    const SizedBox(width: 10),
                    SizedBox(
                      width: 44,
                      child: Text('$percent%',
                          textAlign: TextAlign.end,
                          style: TextStyle(
                              fontWeight: FontWeight.w700,
                              color: row.over ? AppColors.red : null)),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
