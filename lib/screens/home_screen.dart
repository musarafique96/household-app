import 'package:flutter/material.dart';

import '../widgets/data_refresh.dart';
import '../budget_math.dart';
import '../data/db.dart';
import '../data/models.dart';
import '../session.dart';
import '../theme.dart';
import '../util.dart';
import '../widgets/ui.dart';
import 'more_screen.dart';

class _ActivityItem {
  final String title;
  final String subtitle;
  final double amount;
  final DateTime date;
  final bool shared;
  const _ActivityItem({
    required this.title,
    required this.subtitle,
    required this.amount,
    required this.date,
    required this.shared,
  });
}

class _HomeData {
  final double spent;
  final double budget;
  final List<_ActivityItem> activity;
  const _HomeData(this.spent, this.budget, this.activity);
}

class HomeScreen extends StatefulWidget {
  /// Switches the bottom tab: 0 Home, 1 Accounts, 2 Expenses, 3 Split, 4 Budget.
  final void Function(int tab) onOpenTab;

  const HomeScreen({super.key, required this.onOpenTab});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with DataRefreshState<HomeScreen> {
  @override
  void onDataChanged() {
    if (mounted) setState(() { _future = _load(); });
  }

  final DateTime _month = DateTime(DateTime.now().year, DateTime.now().month, 1);
  late Future<_HomeData?> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<_HomeData?> _load() async {
    final user = Session.current.value;
    if (user == null) return null;

    await Db.instance.applyDueRecurring(user.id, DateTime.now());
    final cats = await Db.instance.categories(user.id);
    final month = await Db.instance.expenses(user.id, _month);
    final recent = await Db.instance.recentExpenses(user.id, limit: 5);
    final shared = await Db.instance.sharedExpenses();
    final catNames = {for (final c in cats) c.id: c.name};
    final users = await Db.instance.users();
    final names = {for (final u in users) u.id: u.name};

    final activity = <_ActivityItem>[
      for (final e in recent)
        _ActivityItem(
          title: e.note.isNotEmpty ? e.note : (catNames[e.categoryId] ?? 'Expense'),
          subtitle: 'You paid',
          amount: e.amount,
          date: e.date,
          shared: false,
        ),
      for (final s in shared.take(5))
        _ActivityItem(
          title: s.title,
          subtitle: 'Shared • paid by ${names[s.paidBy] ?? 'Unknown'}',
          amount: s.amount,
          date: s.date,
          shared: true,
        ),
    ]..sort((a, b) => b.date.compareTo(a.date));

    return _HomeData(
      month.fold<double>(0.0, (sum, e) => sum + e.amount),
      cats.fold<double>(0.0, (sum, c) => sum + c.monthlyLimit),
      activity.take(5).toList(),
    );
  }

  String _greeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good morning';
    if (hour < 17) return 'Good afternoon';
    return 'Good evening';
  }

  void _openMore() {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => const MoreScreen()));
  }

  @override
  Widget build(BuildContext context) {
    final user = Session.current.value;
    final firstOrLast = user == null || user.name.trim().isEmpty
        ? ''
        : user.name.trim().split(RegExp(r'\s+')).last;

    return ValueListenableBuilder<AppUser?>(
      valueListenable: Session.current,
      builder: (context, current, _) {
        return ListView(
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
                        tooltip: 'More features',
                        onPressed: _openMore,
                        icon: const Icon(Icons.apps_rounded, color: Colors.white),
                      ),
                    ],
                  ),
                  const SizedBox(height: 22),
                  Text(
                    current == null
                        ? 'Welcome'
                        : '${_greeting()}${firstOrLast.isEmpty ? '' : ', $firstOrLast'} 👋',
                    style: const TextStyle(
                        color: Colors.white, fontSize: 22, fontWeight: FontWeight.w700),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: current == null
                  ? const SoftCard(
                      child: Text('Choose an account in the Accounts tab to get started.'))
                  : FutureBuilder<_HomeData?>(
                      future: _future,
                      builder: (context, snap) {
                        final d = snap.data;
                        final cur = current.currency;
                        final spent = d?.spent ?? 0.0;
                        final budget = d?.budget ?? 0.0;
                        final left = budget - spent;
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: QuickTile(
                                    icon: Icons.add_rounded,
                                    label: 'Add Expense',
                                    color: AppColors.primary,
                                    onTap: () => widget.onOpenTab(1),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: QuickTile(
                                    icon: Icons.call_split_rounded,
                                    label: 'Split Bill',
                                    color: AppColors.pink,
                                    onTap: () => widget.onOpenTab(2),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: QuickTile(
                                    icon: Icons.swap_horiz_rounded,
                                    label: 'Settle Up',
                                    color: AppColors.amber,
                                    onTap: () => widget.onOpenTab(2),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: QuickTile(
                                    icon: Icons.group_add_rounded,
                                    label: 'Create Group',
                                    color: AppColors.blue,
                                    onTap: () => widget.onOpenTab(4),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 20),
                            SectionTitle(title: 'This Month (${monthLabel(_month)})'),
                            const SizedBox(height: 8),
                            SoftCard(
                              child: Row(
                                children: [
                                  _StatColumn(
                                    icon: Icons.swap_vert_rounded,
                                    color: AppColors.primary,
                                    label: 'Spent',
                                    value: money(spent, cur),
                                  ),
                                  _divider(),
                                  _StatColumn(
                                    icon: Icons.account_balance_wallet_rounded,
                                    color: AppColors.pink,
                                    label: 'Budget',
                                    value: money(budget, cur),
                                  ),
                                  _divider(),
                                  _StatColumn(
                                    icon: Icons.trending_up_rounded,
                                    color: AppColors.green,
                                    label: 'Left',
                                    value: money(left, cur),
                                    valueColor: left >= 0 ? AppColors.green : AppColors.red,
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 20),
                            SectionTitle(
                              title: 'Recent Activity',
                              actionLabel: 'View All',
                              onAction: () => widget.onOpenTab(1),
                            ),
                            const SizedBox(height: 8),
                            SoftCard(
                              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                              child: (d == null || d.activity.isEmpty)
                                  ? const Padding(
                                      padding: EdgeInsets.all(12),
                                      child: Text('No activity yet. Add an expense to start.'),
                                    )
                                  : Column(
                                      children: [
                                        for (final a in d.activity)
                                          Padding(
                                            padding: const EdgeInsets.symmetric(vertical: 8),
                                            child: Row(
                                              children: [
                                                IconBubble(
                                                  icon: a.shared
                                                      ? Icons.groups_rounded
                                                      : Icons.receipt_long_rounded,
                                                  color: a.shared
                                                      ? AppColors.primary
                                                      : AppColors.green,
                                                ),
                                                const SizedBox(width: 12),
                                                Expanded(
                                                  child: Column(
                                                    crossAxisAlignment:
                                                        CrossAxisAlignment.start,
                                                    children: [
                                                      Text(a.title,
                                                          style: const TextStyle(
                                                              fontWeight: FontWeight.w700)),
                                                      Text('${a.subtitle} • ${money(a.amount, cur)}',
                                                          style: const TextStyle(
                                                              color: AppColors.muted,
                                                              fontSize: 12)),
                                                    ],
                                                  ),
                                                ),
                                                Text(ymd(a.date),
                                                    style: const TextStyle(
                                                        color: AppColors.muted, fontSize: 12)),
                                              ],
                                            ),
                                          ),
                                      ],
                                    ),
                            ),
                          ],
                        );
                      },
                    ),
            ),
          ],
        );
      },
    );
  }

  Widget _divider() => Container(
        width: 1,
        height: 56,
        margin: const EdgeInsets.symmetric(horizontal: 8),
        color: AppColors.soft,
      );
}

class _StatColumn extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final String value;
  final Color? valueColor;

  const _StatColumn({
    required this.icon,
    required this.color,
    required this.label,
    required this.value,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          IconBubble(icon: icon, color: color, size: 36),
          const SizedBox(height: 6),
          Text(label, style: const TextStyle(color: AppColors.muted, fontSize: 12)),
          const SizedBox(height: 2),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(value,
                style: TextStyle(
                    fontWeight: FontWeight.w800, color: valueColor, fontSize: 14)),
          ),
        ],
      ),
    );
  }
}
