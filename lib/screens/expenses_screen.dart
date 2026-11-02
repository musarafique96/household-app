import 'package:flutter/material.dart';

import '../data/db.dart';
import '../data/models.dart';
import '../session.dart';
import '../theme.dart';
import '../util.dart';
import '../widgets/ui.dart';

class _ExpenseData {
  final List<Category> categories;
  final List<Expense> expenses;
  final Map<String, double> rates;

  const _ExpenseData(this.categories, this.expenses, this.rates);
}

/// Every personal expense this month, with an add button.
class ExpensesScreen extends StatefulWidget {
  const ExpensesScreen({super.key});

  @override
  State<ExpensesScreen> createState() => _ExpensesScreenState();
}

class _ExpensesScreenState extends State<ExpensesScreen> {
  final DateTime _month = DateTime(DateTime.now().year, DateTime.now().month, 1);
  late Future<_ExpenseData?> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<_ExpenseData?> _load() async {
    final user = Session.current.value;
    if (user == null) return null;
    final cats = await Db.instance.categories(user.id);
    final exps = await Db.instance.expenses(user.id, _month);
    final rates = await Db.instance.exchangeRates(user.id);
    return _ExpenseData(cats, exps, rates);
  }

  void _refresh() {
    setState(() {
      _future = _load();
    });
  }

  void _snack(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _add(AppUser user, _ExpenseData data) async {
    if (data.categories.isEmpty) {
      _snack('Add a budget category in the Budget tab first.');
      return;
    }

    final amountCtrl = TextEditingController();
    final noteCtrl = TextEditingController();
    var selected = data.categories.first;
    var currency = user.currency;
    final codes = [
      user.currency,
      ...data.rates.keys.where((c) => c != user.currency),
    ];

    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) {
          final rate = data.rates[currency];
          final foreign = currency != user.currency;
          final hint = !foreign
              ? ''
              : rate == null
                  ? 'No rate for $currency yet. Add it in More → Currency.'
                  : 'Rate: 1 $currency = ${rate.toStringAsFixed(4)} ${user.currency}';

          return Padding(
            padding: EdgeInsets.fromLTRB(
                20, 8, 20, MediaQuery.of(ctx).viewInsets.bottom + 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text('Add expense',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      flex: 2,
                      child: TextField(
                        controller: amountCtrl,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: InputDecoration(
                          labelText: 'Amount',
                          suffixText: currency,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        value: currency,
                        decoration: const InputDecoration(labelText: 'Currency'),
                        items: [
                          for (final c in codes) DropdownMenuItem(value: c, child: Text(c)),
                        ],
                        onChanged: (v) {
                          if (v != null) setSheet(() => currency = v);
                        },
                      ),
                    ),
                  ],
                ),
                if (hint.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      hint,
                      style: TextStyle(
                        fontSize: 12,
                        color: rate == null ? AppColors.red : AppColors.muted,
                      ),
                    ),
                  ),
                const SizedBox(height: 12),
                DropdownButtonFormField<Category>(
                  value: selected,
                  decoration: const InputDecoration(labelText: 'Category'),
                  items: [
                    for (final c in data.categories)
                      DropdownMenuItem(value: c, child: Text(c.name)),
                  ],
                  onChanged: (c) {
                    if (c != null) setSheet(() => selected = c);
                  },
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: noteCtrl,
                  decoration: const InputDecoration(labelText: 'What was it for? (optional)'),
                ),
                const SizedBox(height: 20),
                FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('Save expense'),
                ),
              ],
            ),
          );
        },
      ),
    );

    if (saved != true || !mounted) return;

    final amount = double.tryParse(amountCtrl.text.trim());
    if (amount == null || amount <= 0) {
      _snack('Enter an amount above zero.');
      return;
    }

    var base = amount;
    var stored = '';
    if (currency != user.currency) {
      final rate = data.rates[currency];
      if (rate == null) {
        _snack('Add the exchange rate for $currency in More → Currency first.');
        return;
      }
      base = amount * rate;
      stored = currency;
    }

    await Db.instance.addExpense(
      userId: user.id,
      categoryId: selected.id,
      amount: base,
      note: noteCtrl.text.trim(),
      date: DateTime.now(),
      currency: stored,
      originalAmount: amount,
    );
    _refresh();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AppUser?>(
      valueListenable: Session.current,
      builder: (context, user, _) {
        if (user == null) {
          return const Center(child: Text('Choose an account in the Accounts tab first.'));
        }
        return FutureBuilder<_ExpenseData?>(
          key: ValueKey('expenses-${user.id}'),
          future: _future,
          builder: (context, snap) {
            final data = snap.data;
            final names = {for (final c in data?.categories ?? const <Category>[]) c.id: c.name};
            final exps = data?.expenses ?? const <Expense>[];
            final total = exps.fold<double>(0.0, (s, e) => s + e.amount);

            return Scaffold(
              floatingActionButton: FloatingActionButton.extended(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                icon: const Icon(Icons.add_rounded),
                label: const Text('Add expense'),
                onPressed: () async {
                  final d = await _future;
                  if (d != null && mounted) await _add(user, d);
                },
              ),
              body: ListView(
                padding: const EdgeInsets.fromLTRB(16, 56, 16, 100),
                children: [
                  Text('Expenses',
                      style: Theme.of(context).textTheme.headlineSmall
                          ?.copyWith(fontWeight: FontWeight.w800)),
                  Text('${monthLabel(_month)} • ${money(total, user.currency)}',
                      style: const TextStyle(color: AppColors.muted)),
                  const SizedBox(height: 16),
                  if (!snap.hasData)
                    const Center(
                      child: Padding(
                        padding: EdgeInsets.all(24),
                        child: CircularProgressIndicator(),
                      ),
                    )
                  else if (exps.isEmpty)
                    const SoftCard(child: Text('No expenses this month yet.'))
                  else
                    SoftCard(
                      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 12),
                      child: Column(
                        children: [
                          for (final e in exps)
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 10),
                              child: Row(
                                children: [
                                  const IconBubble(
                                      icon: Icons.receipt_long_rounded, color: AppColors.green),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          e.note.isNotEmpty
                                              ? e.note
                                              : (names[e.categoryId] ?? 'Expense'),
                                          style: const TextStyle(fontWeight: FontWeight.w700),
                                        ),
                                        Text(
                                          _subtitle(e, names[e.categoryId] ?? ''),
                                          style: const TextStyle(
                                              color: AppColors.muted, fontSize: 12),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Text(money(e.amount, user.currency),
                                      style: const TextStyle(fontWeight: FontWeight.w800)),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  /// Category and date, plus the original amount if it was entered in another currency.
  String _subtitle(Expense e, String category) {
    final original = e.currency.isEmpty ? '' : '${money(e.originalAmount, e.currency)} • ';
    return '$original$category • ${ymd(e.date)}';
  }
}
