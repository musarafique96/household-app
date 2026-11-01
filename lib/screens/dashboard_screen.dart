import 'package:flutter/material.dart';

import '../budget_math.dart';
import '../data/db.dart';
import '../session.dart';
import '../util.dart';

class _DashData {
  final List<CategoryRow> rows;
  final double spent;
  final double budget;
  final List<MapEntry<String, double>> trend;
  final List<String> tips;

  const _DashData({
    required this.rows,
    required this.spent,
    required this.budget,
    required this.trend,
    required this.tips,
  });
}

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final DateTime _month = DateTime(DateTime.now().year, DateTime.now().month, 1);
  late Future<_DashData?> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<_DashData?> _load() async {
    final user = Session.current.value;
    if (user == null) return null;

    final cats = await Db.instance.categories(user.id);
    final exps = await Db.instance.expenses(user.id, _month);
    final rows = buildRows(cats, exps);

    final trend = <MapEntry<String, double>>[];
    for (var i = 5; i >= 0; i--) {
      final m = DateTime(_month.year, _month.month - i, 1);
      final list = await Db.instance.expenses(user.id, m);
      final total = list.fold<double>(0.0, (sum, e) => sum + e.amount);
      trend.add(MapEntry(monthShort(m), total));
    }

    return _DashData(
      rows: rows,
      spent: exps.fold<double>(0.0, (sum, e) => sum + e.amount),
      budget: cats.fold<double>(0.0, (sum, c) => sum + c.monthlyLimit),
      trend: trend,
      tips: buildTips(rows, user.currency),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = Session.current.value;
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Dashboard')),
      body: user == null
          ? const Center(child: Text('Choose an account in the Account tab first.'))
          : FutureBuilder<_DashData?>(
              future: _future,
              builder: (context, snap) {
                if (!snap.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final d = snap.data!;
                final cur = user.currency;
                final left = d.budget - d.spent;
                final maxTrend = d.trend.fold<double>(
                    0.0, (m, p) => p.value > m ? p.value : m);

                return ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(monthLabel(_month), style: theme.textTheme.labelLarge),
                            const SizedBox(height: 6),
                            Text(
                              'Spent ${money(d.spent, cur)} of ${money(d.budget, cur)}',
                              style: theme.textTheme.titleMedium,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              left >= 0
                                  ? '${money(left, cur)} left'
                                  : '${money(-left, cur)} over budget',
                              style: TextStyle(
                                color: left >= 0 ? Colors.green.shade700 : Colors.red,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text('By category', style: theme.textTheme.titleMedium),
                    const SizedBox(height: 8),
                    if (d.rows.isEmpty) const Text('No budget categories yet.'),
                    for (final r in d.rows)
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
                    Text('Where to save or cut', style: theme.textTheme.titleMedium),
                    const SizedBox(height: 8),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text(
                          d.tips.isEmpty
                              ? 'Nothing stands out yet. Add expenses to see suggestions.'
                              : d.tips.join('\n'),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text('Last 6 months', style: theme.textTheme.titleMedium),
                    const SizedBox(height: 8),
                    for (final p in d.trend)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(child: Text(p.key)),
                                Text(money(p.value, cur)),
                              ],
                            ),
                            const SizedBox(height: 4),
                            LinearProgressIndicator(
                              value: maxTrend <= 0 ? 0 : p.value / maxTrend,
                              minHeight: 10,
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
