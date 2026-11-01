import 'package:flutter/material.dart';

import '../data/db.dart';
import '../data/models.dart';
import '../session.dart';
import '../split_math.dart';
import '../theme.dart';
import '../util.dart';
import '../widgets/ui.dart';

class _GroupData {
  final Group? group;
  final List<AppUser> users;
  final List<SharedExpense> shared;
  const _GroupData(this.group, this.users, this.shared);
}

/// One group: its balance, who owes whom, recent expenses, and members.
class GroupDetailScreen extends StatefulWidget {
  final int groupId;
  const GroupDetailScreen({super.key, required this.groupId});

  @override
  State<GroupDetailScreen> createState() => _GroupDetailScreenState();
}

class _GroupDetailScreenState extends State<GroupDetailScreen> {
  late Future<_GroupData> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<_GroupData> _load() async {
    final groups = await Db.instance.groups();
    final matches = groups.where((g) => g.id == widget.groupId).toList();
    final users = await Db.instance.users();
    final all = await Db.instance.sharedExpenses();
    final shared = all.where((s) => s.groupId == widget.groupId).toList();
    return _GroupData(matches.isEmpty ? null : matches.first, users, shared);
  }

  void _refresh() {
    setState(() {
      _future = _load();
    });
  }

  Future<void> _manageMembers(_GroupData d) async {
    final group = d.group;
    if (group == null) return;
    final selected = {...group.members};

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Members of ${group.name}'),
        content: StatefulBuilder(
          builder: (ctx, setDialog) => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
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
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Save')),
        ],
      ),
    );

    if (ok == true && selected.isNotEmpty) {
      await Db.instance.updateGroupMembers(group.id, selected.toList());
      _refresh();
    }
  }

  Future<void> _settle(Transfer t) async {
    await Db.instance.addShared(
      title: 'Settled up',
      amount: t.amount,
      paidBy: t.from,
      shares: {t.to: t.amount},
      date: DateTime.now(),
      groupId: widget.groupId,
      splitMethod: 'settlement',
    );
    _refresh();
  }

  Future<void> _settleAll(List<Transfer> transfers) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Settle all?'),
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
        groupId: widget.groupId,
        splitMethod: 'settlement',
      );
    }
    _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final user = Session.current.value;
    final cur = user?.currency ?? '';

    return Scaffold(
      body: FutureBuilder<_GroupData>(
        future: _future,
        builder: (context, snap) {
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final d = snap.data!;
          final group = d.group;
          if (group == null) {
            return const Center(child: Text('This group no longer exists.'));
          }

          final names = {for (final u in d.users) u.id: u.name};
          String nameOf(int id) => names[id] ?? 'Unknown';
          final transfers = computeTransfers(netBalances(d.shared));
          final total = transfers.fold<double>(0.0, (s, t) => s + t.amount);
          final debtors = transfers.map((t) => t.from).toSet().length;

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
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(group.name,
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 22,
                                  fontWeight: FontWeight.w800)),
                          Text('${group.members.length} members • $cur',
                              style: const TextStyle(color: Colors.white70, fontSize: 12)),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: 'Manage members',
                      onPressed: () => _manageMembers(d),
                      icon: const Icon(Icons.group_rounded, color: Colors.white),
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
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('Group balance',
                                    style: TextStyle(color: AppColors.muted)),
                                const SizedBox(height: 4),
                                Text(
                                  transfers.isEmpty
                                      ? 'Everyone is square'
                                      : '$debtors ${debtors == 1 ? 'person owes' : 'people owe'}',
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w700, fontSize: 15),
                                ),
                                if (transfers.isNotEmpty)
                                  Text(money(total, cur),
                                      style: const TextStyle(
                                          fontSize: 24,
                                          fontWeight: FontWeight.w900,
                                          color: AppColors.red)),
                              ],
                            ),
                          ),
                          if (transfers.isNotEmpty)
                            FilledButton(
                              style: FilledButton.styleFrom(
                                backgroundColor: AppColors.primary,
                              ),
                              onPressed: () => _settleAll(transfers),
                              child: const Text('Settle All'),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                    const SectionTitle(title: 'Who owes whom'),
                    const SizedBox(height: 8),
                    if (transfers.isEmpty)
                      const SoftCard(
                        child: Column(
                          children: [
                            Icon(Icons.emoji_events_rounded,
                                color: AppColors.amber, size: 48),
                            SizedBox(height: 6),
                            Text('No pending balances',
                                style: TextStyle(color: AppColors.muted)),
                          ],
                        ),
                      )
                    else
                      for (final t in transfers)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: SoftCard(
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text('${nameOf(t.from)} → ${nameOf(t.to)}',
                                      style: const TextStyle(fontWeight: FontWeight.w700)),
                                ),
                                Text(money(t.amount, cur),
                                    style: const TextStyle(
                                        color: AppColors.red, fontWeight: FontWeight.w800)),
                                TextButton(
                                  onPressed: () => _settle(t),
                                  child: const Text('Settle',
                                      style: TextStyle(
                                          color: AppColors.primary,
                                          fontWeight: FontWeight.w700)),
                                ),
                              ],
                            ),
                          ),
                        ),
                    const SizedBox(height: 20),
                    const SectionTitle(title: 'Recent group expenses'),
                    const SizedBox(height: 8),
                    if (d.shared.isEmpty)
                      const SoftCard(child: Text('No expenses in this group yet.'))
                    else
                      SoftCard(
                        padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 12),
                        child: Column(
                          children: [
                            for (final s in d.shared.take(15))
                              Padding(
                                padding: const EdgeInsets.symmetric(vertical: 10),
                                child: Row(
                                  children: [
                                    IconBubble(
                                      icon: s.isSettlement
                                          ? Icons.swap_horiz_rounded
                                          : Icons.receipt_long_rounded,
                                      color: s.isSettlement ? AppColors.amber : AppColors.primary,
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
                                              '${money(s.amount, cur)} • paid by ${nameOf(s.paidBy)}',
                                              style: const TextStyle(
                                                  color: AppColors.muted, fontSize: 12)),
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
                    const SizedBox(height: 40),
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
