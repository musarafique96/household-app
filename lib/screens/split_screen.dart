import 'package:flutter/material.dart';

import '../data/db.dart';
import '../data/models.dart';
import '../session.dart';
import '../util.dart';

class _SplitData {
  final List<AppUser> users;
  final List<SharedExpense> shared;
  const _SplitData(this.users, this.shared);
}

/// Works out who owes whom. Each shared expense is split equally among
/// everyone, and the payer's share is not owed to themselves.
List<String> computeBalances(
    List<AppUser> users, List<SharedExpense> shared, String currency) {
  final owes = <(int, int), double>{};

  for (final s in shared) {
    if (s.participants.isEmpty) continue;
    final share = s.amount / s.participants.length;
    for (final id in s.participants.where((id) => id != s.paidBy)) {
      final key = (id, s.paidBy);
      owes[key] = (owes[key] ?? 0.0) + share;
    }
  }

  final names = {for (final u in users) u.id: u.name};
  String nameOf(int id) => names[id] ?? 'Unknown';

  final lines = <String>[];
  owes.forEach((key, amount) {
    final back = owes[(key.$2, key.$1)] ?? 0.0;
    final net = amount - back;
    if (net > 0.005) {
      lines.add('${nameOf(key.$1)} owes ${nameOf(key.$2)} ${money(net, currency)}');
    }
  });
  return lines;
}

class SplitScreen extends StatefulWidget {
  const SplitScreen({super.key});

  @override
  State<SplitScreen> createState() => _SplitScreenState();
}

class _SplitScreenState extends State<SplitScreen> {
  late Future<_SplitData> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<_SplitData> _load() async {
    final users = await Db.instance.users();
    final shared = await Db.instance.sharedExpenses();
    return _SplitData(users, shared);
  }

  void _refresh() {
    setState(() {
      _future = _load();
    });
  }

  Future<void> _addShared() async {
    final user = Session.current.value;
    if (user == null) return;

    final users = await Db.instance.users();
    final titleCtrl = TextEditingController();
    final amountCtrl = TextEditingController();
    AppUser payer = users.firstWhere((u) => u.id == user.id, orElse: () => users.first);

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add shared expense'),
        content: StatefulBuilder(
          builder: (ctx, setDialog) => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: titleCtrl,
                decoration: const InputDecoration(labelText: 'What was it for?'),
              ),
              TextField(
                controller: amountCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(labelText: 'Amount (${user.currency})'),
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<AppUser>(
                value: payer,
                decoration: const InputDecoration(labelText: 'Who paid?'),
                items: [
                  for (final u in users) DropdownMenuItem(value: u, child: Text(u.name)),
                ],
                onChanged: (u) {
                  if (u != null) setDialog(() => payer = u);
                },
              ),
              const SizedBox(height: 8),
              const Text(
                'Split equally among everyone with an account.',
                style: TextStyle(fontSize: 12),
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

    final title = titleCtrl.text.trim();
    final amount = double.tryParse(amountCtrl.text.trim());
    if (saved == true && title.isNotEmpty && amount != null && amount > 0) {
      await Db.instance.addShared(
        title: title,
        amount: amount,
        paidBy: payer.id,
        participants: users.map((u) => u.id).toList(),
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
        appBar: AppBar(title: const Text('Split')),
        body: const Center(child: Text('Choose an account in the Account tab first.')),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Split and Qattah')),
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.add),
        label: const Text('Add'),
        onPressed: _addShared,
      ),
      body: FutureBuilder<_SplitData>(
        future: _future,
        builder: (context, snap) {
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final d = snap.data!;
          final names = {for (final u in d.users) u.id: u.name};
          final balances = computeBalances(d.users, d.shared, user.currency);

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
            children: [
              Text('Who owes whom', style: theme.textTheme.titleMedium),
              const SizedBox(height: 8),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    balances.isEmpty ? 'Everyone is square.' : balances.join('\n'),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text('Recent shared expenses', style: theme.textTheme.titleMedium),
              const SizedBox(height: 4),
              if (d.shared.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Text('No shared expenses yet.'),
                ),
              for (final s in d.shared)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(s.title),
                  subtitle: Text(
                      '${ymd(s.date)} · paid by ${names[s.paidBy] ?? 'Unknown'} · ${s.participants.length} people'),
                  trailing: Text(money(s.amount, user.currency)),
                ),
            ],
          );
        },
      ),
    );
  }
}
