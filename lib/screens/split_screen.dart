import 'package:flutter/material.dart';

import '../widgets/data_refresh.dart';
import '../data/db.dart';
import '../data/models.dart';
import '../session.dart';
import '../split_math.dart';
import '../theme.dart';
import '../util.dart';
import '../widgets/fancy.dart';
import '../widgets/ui.dart';

class _SplitData {
  final List<AppUser> users;
  final List<Group> groups;
  final List<SharedExpense> shared;
  const _SplitData(this.users, this.groups, this.shared);
}

/// Values collected by the Add shared expense sheet.
class _SharedDraft {
  final String title;
  final double amount;
  final int payer;
  final int groupId;
  final String method;
  final Map<int, double> shares;

  const _SharedDraft({
    required this.title,
    required this.amount,
    required this.payer,
    required this.groupId,
    required this.method,
    required this.shares,
  });
}

class SplitScreen extends StatefulWidget {
  const SplitScreen({super.key});

  @override
  State<SplitScreen> createState() => _SplitScreenState();
}

class _SplitScreenState extends State<SplitScreen> with DataRefreshState<SplitScreen> {
  @override
  void onDataChanged() {
    if (mounted) setState(() { _future = _load(); });
  }

  int? _groupId; // null means all groups together
  late Future<_SplitData> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<_SplitData> _load() async {
    final users = await Db.instance.users();
    final groups = await Db.instance.groups();
    final shared = await Db.instance.sharedExpenses();
    return _SplitData(users, groups, shared);
  }

  void _refresh() {
    setState(() {
      _future = _load();
    });
  }

  List<SharedExpense> _scope(_SplitData d) =>
      _groupId == null ? d.shared : d.shared.where((s) => s.groupId == _groupId).toList();

  /// People who can take part in an expense: a group's members, or everyone.
  List<AppUser> _candidates(_SplitData d, int groupId) {
    if (groupId == 0) return d.users;
    final group = d.groups.where((g) => g.id == groupId).toList();
    if (group.isEmpty) return const [];
    return d.users.where((u) => group.first.members.contains(u.id)).toList();
  }

  Future<void> _addShared(_SplitData d) async {
    final user = Session.current.value;
    if (user == null) return;

    final titleCtrl = TextEditingController();
    final amountCtrl = TextEditingController();
    final shareCtrls = <int, TextEditingController>{
      for (final u in d.users) u.id: TextEditingController(),
    };
    var groupId = _groupId ?? 0;
    var method = 'equal';
    var included = _candidates(d, groupId).map((u) => u.id).toSet();
    int? payerId = user.id;
    String? error;
    _SharedDraft? draft;

    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) {
          final candidates = _candidates(d, groupId);
          if (payerId == null || !candidates.any((u) => u.id == payerId)) {
            payerId = candidates.isEmpty ? null : candidates.first.id;
          }
          included = included.where((id) => candidates.any((u) => u.id == id)).toSet();

          return Padding(
            padding: EdgeInsets.fromLTRB(20, 4, 20, MediaQuery.of(ctx).viewInsets.bottom + 20),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text('Add shared expense',
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 14),
                  TextField(
                    controller: titleCtrl,
                    decoration: const InputDecoration(
                      labelText: 'What was it for?',
                      hintText: 'e.g. Dinner, Fuel, Groceries',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: amountCtrl,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(
                      labelText: 'Amount',
                      suffixText: user.currency,
                    ),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<int>(
                    value: groupId,
                    decoration: const InputDecoration(labelText: 'Group'),
                    items: [
                      const DropdownMenuItem(value: 0, child: Text('No group (everyone)')),
                      for (final g in d.groups)
                        DropdownMenuItem(value: g.id, child: Text(g.name)),
                    ],
                    onChanged: (v) {
                      if (v == null) return;
                      setSheet(() {
                        groupId = v;
                        included = _candidates(d, v).map((u) => u.id).toSet();
                      });
                    },
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<int>(
                    value: payerId,
                    decoration: const InputDecoration(labelText: 'Who paid?'),
                    items: [
                      for (final u in candidates)
                        DropdownMenuItem(value: u.id, child: Text(u.name)),
                    ],
                    onChanged: (v) => setSheet(() => payerId = v),
                  ),
                  const SizedBox(height: 16),
                  const Text('Split method', style: TextStyle(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 8),
                  SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(
                          value: 'equal',
                          label: Text('Equally'),
                          icon: Icon(Icons.groups_rounded)),
                      ButtonSegment(
                          value: 'amount',
                          label: Text('By Amount'),
                          icon: Icon(Icons.payments_rounded)),
                      ButtonSegment(
                          value: 'percent',
                          label: Text('%'),
                          icon: Icon(Icons.percent_rounded)),
                    ],
                    selected: {method},
                    onSelectionChanged: (s) => setSheet(() => method = s.first),
                  ),
                  const SizedBox(height: 16),
                  const Text('Split among', style: TextStyle(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final u in candidates)
                        FilterChip(
                          label: Text(u.name),
                          selected: included.contains(u.id),
                          onSelected: (v) => setSheet(() {
                            if (v) {
                              included.add(u.id);
                            } else {
                              included.remove(u.id);
                            }
                          }),
                        ),
                    ],
                  ),
                  if (method != 'equal') ...[
                    const SizedBox(height: 12),
                    for (final u in candidates.where((u) => included.contains(u.id)))
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: TextField(
                          controller: shareCtrls[u.id],
                          keyboardType:
                              const TextInputType.numberWithOptions(decimal: true),
                          decoration: InputDecoration(
                            labelText: method == 'percent'
                                ? '${u.name} (%)'
                                : '${u.name} (${user.currency})',
                          ),
                        ),
                      ),
                  ],
                  if (error != null) ...[
                    const SizedBox(height: 8),
                    Text(error!, style: const TextStyle(color: AppColors.red)),
                  ],
                  const SizedBox(height: 16),
                  FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    onPressed: () {
                      final title = titleCtrl.text.trim();
                      final amount = double.tryParse(amountCtrl.text.trim()) ?? 0.0;
                      final payer = payerId;
                      final who = included.toList();
                      String? err;
                      var shares = <int, double>{};

                      if (title.isEmpty) {
                        err = 'Enter what the expense was for.';
                      } else if (amount <= 0) {
                        err = 'Enter an amount above zero.';
                      } else if (payer == null) {
                        err = 'Choose who paid.';
                      } else if (who.isEmpty) {
                        err = 'Choose at least one person to split with.';
                      } else if (method == 'equal') {
                        final each = amount / who.length;
                        shares = {for (final id in who) id: each};
                      } else {
                        final values = {
                          for (final id in who)
                            id: double.tryParse(shareCtrls[id]!.text.trim()) ?? 0.0,
                        };
                        final total = values.values.fold<double>(0.0, (s, v) => s + v);
                        if (method == 'percent') {
                          if ((total - 100).abs() > 0.01) {
                            err = 'Percentages must add up to 100 (now ${total.toStringAsFixed(1)}).';
                          } else {
                            shares = {
                              for (final e in values.entries) e.key: amount * e.value / 100,
                            };
                          }
                        } else {
                          if ((total - amount).abs() > 0.01) {
                            err = 'Amounts must add up to ${amount.toStringAsFixed(2)} (now ${total.toStringAsFixed(2)}).';
                          } else {
                            shares = values;
                          }
                        }
                      }

                      if (err != null) {
                        setSheet(() => error = err);
                        return;
                      }
                      draft = _SharedDraft(
                        title: title,
                        amount: amount,
                        payer: payer!,
                        groupId: groupId,
                        method: method,
                        shares: shares,
                      );
                      Navigator.pop(ctx, true);
                    },
                    child: const Text('Save expense'),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );

    final d2 = draft;
    if (saved == true && d2 != null) {
      await Db.instance.addShared(
        title: d2.title,
        amount: d2.amount,
        paidBy: d2.payer,
        shares: d2.shares,
        date: DateTime.now(),
        groupId: d2.groupId,
        splitMethod: d2.method,
      );
      _refresh();
    }
  }

  Future<void> _createGroup(_SplitData d) async {
    final nameCtrl = TextEditingController();
    final selected = <int>{for (final u in d.users) u.id};

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => FancyAlert(
        title: const Text('Create group'),
        content: StatefulBuilder(
          builder: (ctx, setDialog) => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtrl,
                decoration: const InputDecoration(labelText: 'Group name (e.g. Trip to Dubai)'),
              ),
              const SizedBox(height: 8),
              for (final u in d.users)
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: selected.contains(u.id),
                  title: Text(u.name),
                  onChanged: (v) => setDialog(() {
                    if (v == true) {
                      selected.add(u.id);
                    } else {
                      selected.remove(u.id);
                    }
                  }),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Create')),
        ],
      ),
    );

    final name = nameCtrl.text.trim();
    if (ok == true && name.isNotEmpty && selected.isNotEmpty) {
      await Db.instance.addGroup(name, selected.toList());
      _refresh();
    }
  }

  Future<void> _settle(Transfer t, int groupId) async {
    await Db.instance.addShared(
      title: 'Settled up',
      amount: t.amount,
      paidBy: t.from,
      shares: {t.to: t.amount},
      date: DateTime.now(),
      groupId: groupId,
      splitMethod: 'settlement',
    );
    _refresh();
  }

  Future<void> _settleAll(List<Transfer> transfers, int groupId) async {
    if (transfers.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nothing to settle.')),
      );
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => FancyAlert(
        title: const Text('Settle up?'),
        content: Text('Record ${transfers.length} payment(s) as settled.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Settle')),
        ],
      ),
    );
    if (ok != true) return;
    for (final t in transfers) {
      await Db.instance.addShared(
        title: 'Settled up',
        amount: t.amount,
        paidBy: t.from,
        shares: {t.to: t.amount},
        date: DateTime.now(),
        groupId: groupId,
        splitMethod: 'settlement',
      );
    }
    _refresh();
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

        return FutureBuilder<_SplitData>(
          future: _future,
          builder: (context, snap) {
            if (!snap.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final d = snap.data!;
            final cur = user.currency;
            final groupId = _groupId ?? 0;
            final shared = _scope(d);
            final names = {for (final u in d.users) u.id: u.name};
            String nameOf(int id) => names[id] ?? 'Unknown';
            final transfers = computeTransfers(netBalances(shared));

            return Scaffold(
              floatingActionButton: FloatingActionButton.extended(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                icon: const Icon(Icons.add_rounded),
                label: const Text('Add expense'),
                onPressed: () => _addShared(d),
              ),
              body: ListView(
                padding: EdgeInsets.zero,
                children: [
                  GradientHeader(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 44,
                              height: 44,
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.18),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.groups_rounded, color: Colors.white),
                            ),
                            const SizedBox(width: 12),
                            const Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('Split & Qattah',
                                      style: TextStyle(
                                          color: Colors.white,
                                          fontSize: 22,
                                          fontWeight: FontWeight.w800)),
                                  Text('Track • Split • Budget • Settle',
                                      style: TextStyle(color: Colors.white70, fontSize: 12)),
                                ],
                              ),
                            ),
                            IconButton(
                              tooltip: 'Create group',
                              onPressed: () => _createGroup(d),
                              icon: const Icon(Icons.group_add_rounded, color: Colors.white),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        SizedBox(
                          height: 38,
                          child: ListView(
                            scrollDirection: Axis.horizontal,
                            children: [
                              _GroupChip(
                                label: 'All',
                                selected: _groupId == null,
                                onTap: () => setState(() => _groupId = null),
                              ),
                              for (final g in d.groups)
                                _GroupChip(
                                  label: g.name,
                                  selected: _groupId == g.id,
                                  onTap: () => setState(() => _groupId = g.id),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: QuickTile(
                                icon: Icons.add_rounded,
                                label: 'Add Expense',
                                color: AppColors.primary,
                                onTap: () => _addShared(d),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: QuickTile(
                                icon: Icons.call_split_rounded,
                                label: 'Split Bill',
                                color: AppColors.pink,
                                onTap: () => _addShared(d),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: QuickTile(
                                icon: Icons.swap_horiz_rounded,
                                label: 'Settle Up',
                                color: AppColors.amber,
                                onTap: () => _settleAll(transfers, groupId),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: QuickTile(
                                icon: Icons.group_add_rounded,
                                label: 'Create Group',
                                color: AppColors.blue,
                                onTap: () => _createGroup(d),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 20),
                        const SectionTitle(title: 'Who owes whom'),
                        const SizedBox(height: 8),
                        if (transfers.isEmpty)
                          const SoftCard(
                            child: Column(
                              children: [
                                Icon(Icons.emoji_events_rounded,
                                    color: AppColors.amber, size: 56),
                                SizedBox(height: 8),
                                Text('Everyone is square!',
                                    style: TextStyle(
                                        fontSize: 18, fontWeight: FontWeight.w800)),
                                Text('No pending balances',
                                    style: TextStyle(color: AppColors.muted)),
                              ],
                            ),
                          )
                        else
                          SoftCard(
                            child: Column(
                              children: [
                                for (final t in transfers)
                                  Padding(
                                    padding: const EdgeInsets.symmetric(vertical: 6),
                                    child: Row(
                                      children: [
                                        CircleAvatar(
                                          radius: 18,
                                          backgroundColor: AppColors.soft,
                                          child: Text(
                                            nameOf(t.from).isEmpty
                                                ? '?'
                                                : nameOf(t.from)[0].toUpperCase(),
                                            style: const TextStyle(
                                                color: AppColors.primary,
                                                fontWeight: FontWeight.w800),
                                          ),
                                        ),
                                        const SizedBox(width: 10),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text('${nameOf(t.from)} → ${nameOf(t.to)}',
                                                  style: const TextStyle(
                                                      fontWeight: FontWeight.w700)),
                                              Text(money(t.amount, cur),
                                                  style: const TextStyle(
                                                      color: AppColors.red,
                                                      fontWeight: FontWeight.w800)),
                                            ],
                                          ),
                                        ),
                                        TextButton(
                                          onPressed: () => _settle(t, groupId),
                                          child: const Text('Settle',
                                              style: TextStyle(
                                                  color: AppColors.primary,
                                                  fontWeight: FontWeight.w700)),
                                        ),
                                      ],
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        const SizedBox(height: 20),
                        const SectionTitle(title: 'Recent shared expenses'),
                        const SizedBox(height: 8),
                        if (shared.isEmpty)
                          const SoftCard(child: Text('No shared expenses yet.'))
                        else
                          SoftCard(
                            padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 12),
                            child: Column(
                              children: [
                                for (final s in shared.take(10))
                                  Padding(
                                    padding: const EdgeInsets.symmetric(vertical: 10),
                                    child: Row(
                                      children: [
                                        IconBubble(
                                          icon: s.isSettlement
                                              ? Icons.swap_horiz_rounded
                                              : Icons.receipt_long_rounded,
                                          color: s.isSettlement
                                              ? AppColors.amber
                                              : AppColors.primary,
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(s.title,
                                                  style: const TextStyle(
                                                      fontWeight: FontWeight.w700)),
                                              Text(
                                                s.isSettlement
                                                    ? '${nameOf(s.paidBy)} paid ${s.owed.isEmpty ? '' : nameOf(s.owed.keys.first)}'
                                                    : '${money(s.amount, cur)} • split between ${s.owed.length} • paid by ${nameOf(s.paidBy)}',
                                                style: const TextStyle(
                                                    color: AppColors.muted, fontSize: 12),
                                              ),
                                            ],
                                          ),
                                        ),
                                        Text(ymd(s.date),
                                            style: const TextStyle(
                                                color: AppColors.muted, fontSize: 12)),
                                      ],
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        const SizedBox(height: 80),
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
}

class _GroupChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _GroupChip({required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: selected ? Colors.white : Colors.white.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: selected ? AppColors.deep : Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }
}
