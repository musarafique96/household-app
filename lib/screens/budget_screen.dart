import 'package:flutter/material.dart';

import '../budget_math.dart';
import '../data/db.dart';
import '../data/models.dart';
import '../session.dart';
import '../util.dart';

class _BudgetData {
  final List<Category> categories;
  final List<Expense> expenses;
  const _BudgetData(this.categories, this.expenses);
}

class BudgetScreen extends StatefulWidget {
  const BudgetScreen({super.key});

  @override
  State<BudgetScreen> createState() => _BudgetScreenState();
}

class _BudgetScreenState extends State<BudgetScreen> {
  final DateTime _month = DateTime(DateTime.now().year, DateTime.now().month, 1);
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
      builder: (ctx) => AlertDialog(
        title: const Text('New budget category'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameCtrl,
              decoration: const InputDecoration(labelText: 'Name (e.g. Groceries)'),
            ),
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

  Future<void> _addExpense(List<Category> cats) async {
    final user = Session.current.value;
    if (user == null) return;
    if (cats.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Add a budget category first.')),
      );
      return;
    }

    final amountCtrl = TextEditingController();
    final noteCtrl = TextEditingController();
    Category selected = cats.first;

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add expense'),
        content: StatefulBuilder(
          builder: (ctx, setDialog) => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<Category>(
                value: selected,
                decoration: const InputDecoration(labelText: 'Category'),
                items: [
                  for (final c in cats) DropdownMenuItem(value: c, child: Text(c.name)),
                ],
                onChanged: (c) {
                  if (c != null) setDialog(() => selected = c);
                },
              ),
              TextField(
                controller: amountCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(labelText: 'Amount (${user.currency})'),
              ),
              TextField(
                controller: noteCtrl,
                decoration: const InputDecoration(labelText: 'Note (optional)'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Save')),
        ],
      ),
    );

    final amount = double.tryParse(amountCtrl.text.trim());
    if (saved == true && amount != null && amount > 0) {
      await Db.instance.addExpense(
        userId: user.id,
        categoryId: selected.id,
        amount: amount,
        note: noteCtrl.text.trim(),
        date: DateTime.now(),
      );
      _refresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = Session.current.value;
    final theme = Theme.of(context);

    if (user == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Budget')),
        body: const Center(child: Text('Choose an account in the Account tab first.')),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Budget'),
        actions: [
          IconButton(
            tooltip: 'Add category',
            icon: const Icon(Icons.category_outlined),
            onPressed: _addCategory,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.add),
        label: const Text('Expense'),
        onPressed: () async {
          final data = await _future;
          if (!context.mounted) return;
          await _addExpense(data?.categories ?? const []);
        },
      ),
      body: FutureBuilder<_BudgetData?>(
        future: _future,
        builder: (context, snap) {
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final data = snap.data!;
          final cur = user.currency;
          final rows = buildRows(data.categories, data.expenses);
          final names = {for (final c in data.categories) c.id: c.name};

          if (rows.isEmpty) {
            return const Center(child: Text('Add a budget category to start.'));
          }

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
            children: [
              Text(monthLabel(_month), style: theme.textTheme.titleLarge),
              const SizedBox(height: 12),
              for (final r in rows)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(r.name,
                                  style: const TextStyle(fontWeight: FontWeight.bold)),
                            ),
                            Text('${money(r.spent, cur)} / ${money(r.limit, cur)}'),
                          ],
                        ),
                        const SizedBox(height: 10),
                        LinearProgressIndicator(
                          value: r.progress,
                          minHeight: 8,
                          color: r.over ? Colors.red : null,
                        ),
                      ],
                    ),
                  ),
                ),
              const SizedBox(height: 16),
              Text('Recent expenses', style: theme.textTheme.titleMedium),
              const SizedBox(height: 4),
              if (data.expenses.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Text('No expenses this month yet.'),
                ),
              for (final e in data.expenses.take(20))
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(names[e.categoryId] ?? ''),
                  subtitle: Text(e.note.isEmpty ? ymd(e.date) : '${e.note} · ${ymd(e.date)}'),
                  trailing: Text(money(e.amount, cur)),
                ),
            ],
          );
        },
      ),
    );
  }
}
