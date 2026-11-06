import 'package:flutter/material.dart';

import '../data/db.dart';
import '../data/models.dart';
import '../session.dart';
import '../theme.dart';
import '../util.dart';
import '../widgets/fancy.dart';
import '../widgets/ui.dart';

class _RecurringData {
  final List<RecurringExpense> items;
  final List<Category> cats;
  const _RecurringData(this.items, this.cats);
}

/// Bills and subscriptions that are added to expenses automatically each month.
class RecurringScreen extends StatefulWidget {
  const RecurringScreen({super.key});

  @override
  State<RecurringScreen> createState() => _RecurringScreenState();
}

class _RecurringScreenState extends State<RecurringScreen> {
  late Future<_RecurringData?> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<_RecurringData?> _load() async {
    final user = Session.current.value;
    if (user == null) return null;
    await Db.instance.applyDueRecurring(user.id, DateTime.now());
    final items = await Db.instance.recurring(user.id);
    final cats = await Db.instance.categories(user.id);
    return _RecurringData(items, cats);
  }

  void _refresh() {
    setState(() {
      _future = _load();
    });
  }

  void _snack(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _add(_RecurringData d) async {
    final user = Session.current.value;
    if (user == null) return;
    if (d.cats.isEmpty) {
      _snack('Add a budget category first.');
      return;
    }

    final nameCtrl = TextEditingController();
    final amountCtrl = TextEditingController();
    final dayCtrl = TextEditingController(text: '1');
    var selected = d.cats.first;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => FancyAlert(
        title: const Text('New recurring expense'),
        content: StatefulBuilder(
          builder: (ctx, setDialog) => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtrl,
                decoration: const InputDecoration(labelText: 'Name (e.g. Rent, Netflix)'),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: amountCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(labelText: 'Amount (${user.currency})'),
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<Category>(
                value: selected,
                decoration: const InputDecoration(labelText: 'Category'),
                items: [
                  for (final c in d.cats) DropdownMenuItem(value: c, child: Text(c.name)),
                ],
                onChanged: (c) {
                  if (c != null) setDialog(() => selected = c);
                },
              ),
              const SizedBox(height: 8),
              TextField(
                controller: dayCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Day of month (1-31)'),
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

    if (ok != true) return;
    final name = nameCtrl.text.trim();
    final amount = double.tryParse(amountCtrl.text.trim());
    final day = int.tryParse(dayCtrl.text.trim());
    if (name.isEmpty || amount == null || amount <= 0 || day == null || day < 1 || day > 31) {
      _snack('Enter a name, an amount above zero, and a day from 1 to 31.');
      return;
    }

    await Db.instance.addRecurring(
      userId: user.id,
      name: name,
      amount: amount,
      categoryId: selected.id,
      day: day,
    );
    _refresh();
  }

  Future<void> _delete(RecurringExpense r) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => FancyAlert(
        title: Text('Delete ${r.name}?'),
        content: const Text('Past expenses that were already added will stay.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete')),
        ],
      ),
    );
    if (ok != true) return;
    await Db.instance.deleteRecurring(r.id);
    _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final user = Session.current.value;

    return Scaffold(
      floatingActionButton: user == null
          ? null
          : FloatingActionButton.extended(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              icon: const Icon(Icons.add_rounded),
              label: const Text('Add'),
              onPressed: () async {
                final d = await _future;
                if (d != null && mounted) await _add(d);
              },
            ),
      body: user == null
          ? const Center(child: Text('Choose an account in the Accounts tab first.'))
          : FutureBuilder<_RecurringData?>(
              future: _future,
              builder: (context, snap) {
                final d = snap.data;
                final names = {for (final c in d?.cats ?? const <Category>[]) c.id: c.name};
                return ListView(
                  padding: EdgeInsets.zero,
                  children: [
                    GradientHeader(
                      child: Row(
                        children: [
                          IconButton(
                            onPressed: () => Navigator.pop(context),
                            icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
                          ),
                          const SizedBox(width: 4),
                          const Text('Recurring',
                              style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 22,
                                  fontWeight: FontWeight.w800)),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
                      child: !snap.hasData || d == null
                          ? const Center(child: CircularProgressIndicator())
                          : Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                const SoftCard(
                                  child: Text(
                                    'Recurring expenses are added automatically on their day each month, the next time you open the app.',
                                    style: TextStyle(color: AppColors.muted),
                                  ),
                                ),
                                const SizedBox(height: 16),
                                if (d.items.isEmpty)
                                  const SoftCard(
                                      child: Text('No recurring expenses yet. Tap Add to create one.')),
                                for (final r in d.items)
                                  Padding(
                                    padding: const EdgeInsets.only(bottom: 12),
                                    child: SoftCard(
                                      child: Row(
                                        children: [
                                          const IconBubble(
                                              icon: Icons.event_repeat_rounded,
                                              color: AppColors.pink),
                                          const SizedBox(width: 12),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Text(r.name,
                                                    style: const TextStyle(
                                                        fontWeight: FontWeight.w700)),
                                                Text(
                                                  'Day ${r.day} each month • ${names[r.categoryId] ?? ''}',
                                                  style: const TextStyle(
                                                      color: AppColors.muted, fontSize: 12),
                                                ),
                                                Text(
                                                  'Last added: ${r.lastApplied.isEmpty ? 'not yet' : r.lastApplied}',
                                                  style: const TextStyle(
                                                      color: AppColors.muted, fontSize: 12),
                                                ),
                                              ],
                                            ),
                                          ),
                                          Text(money(r.amount, user.currency),
                                              style: const TextStyle(fontWeight: FontWeight.w800)),
                                          IconButton(
                                            tooltip: 'Delete',
                                            onPressed: () => _delete(r),
                                            icon: const Icon(Icons.delete_outline_rounded,
                                                color: AppColors.muted),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                    ),
                  ],
                );
              },
            ),
    );
  }
}
