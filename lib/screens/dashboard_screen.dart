import 'package:flutter/material.dart';

import '../widgets/data_refresh.dart';
import '../data/db.dart';
import '../session.dart';
import '../split_math.dart';
import '../theme.dart';
import '../util.dart';
import '../widgets/charts.dart';
import '../widgets/ui.dart';

enum _Period { m1, m3, m6, ytd }

const List<Color> _catColors = [
  AppColors.pink,
  AppColors.amber,
  Color(0xFFA78BFA),
  AppColors.blue,
  AppColors.deep,
];

class _DashData {
  final double periodSpent;
  final double monthSpent;
  final double lastMonthSpent;
  final double monthBudget;
  final double yourShare;
  final double youAreOwed;
  final List<double> trend;
  final List<String> trendLabels;
  final List<MapEntry<String, double>> topCategories;

  const _DashData({
    required this.periodSpent,
    required this.monthSpent,
    required this.lastMonthSpent,
    required this.monthBudget,
    required this.yourShare,
    required this.youAreOwed,
    required this.trend,
    required this.trendLabels,
    required this.topCategories,
  });
}

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> with DataRefreshState<DashboardScreen> {
  @override
  void onDataChanged() {
    if (mounted) setState(() { _future = _load(); });
  }

  _Period _period = _Period.m1;
  late Future<_DashData?> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  /// The months covered by the selected period, oldest first.
  List<DateTime> _periodMonths(_Period p) {
    final now = DateTime.now();
    final count = switch (p) {
      _Period.m1 => 1,
      _Period.m3 => 3,
      _Period.m6 => 6,
      _Period.ytd => now.month,
    };
    return [
      for (var i = count - 1; i >= 0; i--) DateTime(now.year, now.month - i, 1),
    ];
  }

  Future<_DashData?> _load() async {
    final user = Session.current.value;
    if (user == null) return null;

    final months = _periodMonths(_period);
    final cats = await Db.instance.categories(user.id);
    final catNames = {for (final c in cats) c.id: c.name};

    var periodSpent = 0.0;
    final byCat = <String, double>{};
    for (final m in months) {
      for (final e in await Db.instance.expenses(user.id, m)) {
        periodSpent += e.amount;
        final name = catNames[e.categoryId] ?? 'Other';
        byCat[name] = (byCat[name] ?? 0.0) + e.amount;
      }
    }

    // Trend always shows the last six months.
    final now = DateTime.now();
    final trend = <double>[];
    final labels = <String>[];
    for (var i = 5; i >= 0; i--) {
      final m = DateTime(now.year, now.month - i, 1);
      final list = await Db.instance.expenses(user.id, m);
      trend.add(list.fold<double>(0.0, (s, e) => s + e.amount));
      labels.add(monthShort(m));
    }

    final shared = await Db.instance.sharedExpenses();
    final start = months.first;
    final end = DateTime(now.year, now.month + 1, 1);
    final inPeriod = shared.where(
        (s) => !s.isSettlement && !s.date.isBefore(start) && s.date.isBefore(end));
    final yourShare =
        inPeriod.fold<double>(0.0, (sum, s) => sum + (s.owed[user.id] ?? 0.0));
    final youAreOwed = netBalances(shared)[user.id] ?? 0.0;

    final sorted = byCat.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    final top = sorted.take(4).toList();
    final rest = sorted.skip(4).fold<double>(0.0, (s, e) => s + e.value);
    if (rest > 0) top.add(MapEntry('Others', rest));

    final cats2 = cats.fold<double>(0.0, (s, c) => s + c.monthlyLimit);

    return _DashData(
      periodSpent: periodSpent,
      monthSpent: trend.last,
      lastMonthSpent: trend[trend.length - 2],
      monthBudget: cats2,
      yourShare: yourShare,
      youAreOwed: youAreOwed < 0 ? 0.0 : youAreOwed,
      trend: trend,
      trendLabels: labels,
      topCategories: top,
    );
  }

  void _setPeriod(_Period p) {
    setState(() {
      _period = p;
      _future = _load();
    });
  }

  String _periodLabel(_Period p) => switch (p) {
        _Period.m1 => '1M',
        _Period.m3 => '3M',
        _Period.m6 => '6M',
        _Period.ytd => 'YTD',
      };

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AppUser?>(
      valueListenable: Session.current,
      builder: (context, user, _) {
        return Scaffold(
          body: ListView(
            padding: EdgeInsets.zero,
            children: [
              GradientHeader(
                child: Column(
                  children: [
                    Row(
                      children: [
                        const Text('Dashboard',
                            style: TextStyle(
                                color: Colors.white,
                                fontSize: 22,
                                fontWeight: FontWeight.w800)),
                        const Spacer(),
                        IconButton(
                          tooltip: 'Filters',
                          onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('More filters are coming later.')),
                          ),
                          icon: const Icon(Icons.filter_alt_outlined, color: Colors.white),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Row(
                        children: [
                          for (final p in _Period.values)
                            Expanded(
                              child: GestureDetector(
                                onTap: () => _setPeriod(p),
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 200),
                                  alignment: Alignment.center,
                                  padding: const EdgeInsets.symmetric(vertical: 10),
                                  decoration: BoxDecoration(
                                    color: _period == p ? AppColors.primary : Colors.transparent,
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Text(
                                    _periodLabel(p),
                                    style: TextStyle(
                                      color: _period == p ? Colors.white : AppColors.deep,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              if (user == null)
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Text('Choose an account in the Accounts tab first.'),
                )
              else
                FutureBuilder<_DashData?>(
                  future: _future,
                  builder: (context, snap) {
                    if (!snap.hasData || snap.data == null) {
                      return const Padding(
                        padding: EdgeInsets.all(40),
                        child: Center(child: CircularProgressIndicator()),
                      );
                    }
                    return _content(snap.data!, user);
                  },
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _content(_DashData d, AppUser user) {
    final cur = user.currency;
    final used = d.monthBudget <= 0 ? 0.0 : d.monthSpent / d.monthBudget;
    final change = d.lastMonthSpent <= 0
        ? null
        : (d.monthSpent - d.lastMonthSpent) / d.lastMonthSpent * 100;

    final shareTotal = d.topCategories.fold<double>(0.0, (s, e) => s + e.value);

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: _Kpi(
                  icon: Icons.account_balance_wallet_rounded,
                  color: AppColors.primary,
                  label: 'Total Spent',
                  value: money(d.periodSpent, cur),
                  footer: change == null
                      ? const Text('No data last month',
                          style: TextStyle(color: AppColors.muted, fontSize: 12))
                      : Text(
                          '${change >= 0 ? '↑' : '↓'} ${change.abs().toStringAsFixed(0)}% vs last month',
                          style: TextStyle(
                            color: change >= 0 ? AppColors.red : AppColors.green,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _Kpi(
                  icon: Icons.donut_large_rounded,
                  color: AppColors.green,
                  label: 'vs Budget',
                  value: '${(used * 100).round()}% Used',
                  footer: Text(
                    '${money(d.monthSpent, cur)} of ${money(d.monthBudget, cur)}',
                    style: const TextStyle(color: AppColors.muted, fontSize: 12),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _Kpi(
                  icon: Icons.pie_chart_rounded,
                  color: AppColors.pink,
                  label: 'Your Share',
                  value: money(d.yourShare, cur),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _Kpi(
                  icon: Icons.handshake_rounded,
                  color: AppColors.amber,
                  label: "You're Owed",
                  value: money(d.youAreOwed, cur),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          const SectionTitle(title: 'Spending Trend'),
          const SizedBox(height: 8),
          SoftCard(
            child: LineTrendChart(
              values: d.trend,
              labels: d.trendLabels,
              color: AppColors.primary,
              format: (v) => money(v, cur),
            ),
          ),
          const SizedBox(height: 20),
          const SectionTitle(title: 'Top Categories'),
          const SizedBox(height: 8),
          if (d.topCategories.isEmpty)
            const SoftCard(child: Text('No expenses in this period yet.'))
          else
            SoftCard(
              child: Row(
                children: [
                  SegmentedDonut(
                    size: 130,
                    fractions: [for (final e in d.topCategories) e.value],
                    colors: _catColors,
                    center: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(d.periodSpent.toStringAsFixed(0),
                              style: const TextStyle(
                                  fontWeight: FontWeight.w900, fontSize: 18)),
                        ),
                        Text(cur, style: const TextStyle(color: AppColors.muted, fontSize: 12)),
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      children: [
                        for (var i = 0; i < d.topCategories.length; i++)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 5),
                            child: Row(
                              children: [
                                Container(
                                  width: 10,
                                  height: 10,
                                  decoration: BoxDecoration(
                                    color: _catColors[i % _catColors.length],
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(d.topCategories[i].key,
                                      overflow: TextOverflow.ellipsis),
                                ),
                                Text(
                                  shareTotal <= 0
                                      ? '0%'
                                      : '${(d.topCategories[i].value / shareTotal * 100).round()}%',
                                  style: const TextStyle(fontWeight: FontWeight.w700),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 40),
        ],
      ),
    );
  }
}

class _Kpi extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final String value;
  final Widget? footer;

  const _Kpi({
    required this.icon,
    required this.color,
    required this.label,
    required this.value,
    this.footer,
  });

  @override
  Widget build(BuildContext context) {
    return SoftCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          IconBubble(icon: icon, color: color, size: 36),
          const SizedBox(height: 10),
          Text(label, style: const TextStyle(color: AppColors.muted, fontSize: 12)),
          const SizedBox(height: 2),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(value,
                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
          ),
          if (footer != null) ...[
            const SizedBox(height: 6),
            footer!,
          ],
        ],
      ),
    );
  }
}
