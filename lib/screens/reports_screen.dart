import 'package:flutter/material.dart';

import '../widgets/data_refresh.dart';import 'package:flutter/services.dart';

import '../budget_math.dart';
import '../data/db.dart';
import '../data/models.dart';
import '../session.dart';
import '../theme.dart';
import '../util.dart';
import '../widgets/ui.dart';

class _ReportData {
  final double spent;
  final double budget;
  final List<CategoryRow> rows;
  final List<MapEntry<DateTime, double>> history;

  const _ReportData({
    required this.spent,
    required this.budget,
    required this.rows,
    required this.history,
  });
}

/// Monthly report: summary, categories, and a 12-month history.
/// The report can be copied as text to share anywhere.
class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> with DataRefreshState<ReportsScreen> {
  @override
  void onDataChanged() {
    if (mounted) setState(() { _future = _load(); });
  }

  final DateTime _currentMonth = DateTime(DateTime.now().year, DateTime.now().month, 1);
  late DateTime _month = _currentMonth;
  late Future<_ReportData?> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<_ReportData?> _load() async {
    final user = Session.current.value;
    if (user == null) return null;

    final cats = await Db.instance.categories(user.id);
    final exps = await Db.instance.expenses(user.id, _month);
    final rows = buildRows(cats, exps);
    final spent = exps.fold<double>(0.0, (s, e) => s + e.amount);
    final budget = cats.fold<double>(0.0, (s, c) => s + c.monthlyLimit);

    final history = <MapEntry<DateTime, double>>[];
    for (var i = 11; i >= 0; i--) {
      final m = DateTime(_month.year, _month.month - i, 1);
      final list = await Db.instance.expenses(user.id, m);
      history.add(MapEntry(m, list.fold<double>(0.0, (s, e) => s + e.amount)));
    }

    return _ReportData(spent: spent, budget: budget, rows: rows, history: history);
  }

  void _shift(int delta) {
    final next = DateTime(_month.year, _month.month + delta, 1);
    if (next.isAfter(_currentMonth)) return;
    setState(() {
      _month = next;
      _future = _load();
    });
  }

  Future<void> _copyReport(_ReportData d, AppUser user) async {
    final cur = user.currency;
    final used = d.budget <= 0 ? 0 : (d.spent / d.budget * 100).round();
    final buffer = StringBuffer()
      ..writeln('Household report: ${monthLabel(_month)}')
      ..writeln('Spent: ${money(d.spent, cur)} of ${money(d.budget, cur)} ($used%)')
      ..writeln('Left: ${money(d.budget - d.spent, cur)}')
      ..writeln()
      ..writeln('By category:');
    for (final r in d.rows) {
      buffer.writeln('- ${r.name}: ${money(r.spent, cur)} of ${money(r.limit, cur)}');
    }
    await Clipboard.setData(ClipboardData(text: buffer.toString()));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Report copied. Paste it into any app to share.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = Session.current.value;

    return Scaffold(
      body: user == null
          ? const Center(child: Text('Choose an account in the Accounts tab first.'))
          : FutureBuilder<_ReportData?>(
              future: _future,
              builder: (context, snap) {
                final d = snap.data;
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
                          const Expanded(
                            child: Text('Reports',
                                style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 22,
                                    fontWeight: FontWeight.w800)),
                          ),
                          IconButton(
                            tooltip: 'Copy report',
                            onPressed: d == null ? null : () => _copyReport(d, user),
                            icon: const Icon(Icons.copy_rounded, color: Colors.white),
                          ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: !snap.hasData || d == null
                          ? const Center(child: CircularProgressIndicator())
                          : _body(d, user),
                    ),
                  ],
                );
              },
            ),
    );
  }

  Widget _body(_ReportData d, AppUser user) {
    final cur = user.currency;
    final used = d.budget <= 0 ? 0.0 : (d.spent / d.budget).clamp(0.0, 1.0).toDouble();
    final left = d.budget - d.spent;
    final maxMonth = d.history.fold<double>(0.0, (m, e) => e.value > m ? e.value : m);
    final isCurrent = _month == _currentMonth;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SoftCard(
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              IconButton(
                onPressed: () => _shift(-1),
                icon: const Icon(Icons.chevron_left_rounded),
              ),
              Text(monthLabel(_month),
                  style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
              IconButton(
                onPressed: isCurrent ? null : () => _shift(1),
                icon: const Icon(Icons.chevron_right_rounded),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        SoftCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Spent ${money(d.spent, cur)} of ${money(d.budget, cur)}',
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
              const SizedBox(height: 10),
              LinearProgressIndicator(
                value: used,
                minHeight: 10,
                color: d.spent > d.budget ? AppColors.red : AppColors.primary,
                backgroundColor: AppColors.soft,
              ),
              const SizedBox(height: 8),
              Text(
                left >= 0
                    ? '${(used * 100).round()}% used • ${money(left, cur)} left'
                    : '${money(-left, cur)} over budget',
                style: TextStyle(
                  color: left >= 0 ? AppColors.muted : AppColors.red,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        const SectionTitle(title: 'Categories'),
        const SizedBox(height: 8),
        if (d.rows.isEmpty)
          const SoftCard(child: Text('No budget categories for this month.'))
        else
          SoftCard(
            child: Column(
              children: [
                for (final r in d.rows)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(r.name,
                                  style: const TextStyle(fontWeight: FontWeight.w700)),
                            ),
                            Text(money(r.spent, cur),
                                style: const TextStyle(fontWeight: FontWeight.w700)),
                          ],
                        ),
                        const SizedBox(height: 6),
                        LinearProgressIndicator(
                          value: r.progress,
                          minHeight: 6,
                          color: r.over ? AppColors.red : AppColors.primary,
                          backgroundColor: AppColors.soft,
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        const SizedBox(height: 20),
        const SectionTitle(title: 'Last 12 months'),
        const SizedBox(height: 8),
        SoftCard(
          child: Column(
            children: [
              for (final h in d.history.reversed)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(child: Text(monthShort(h.key))),
                          Text(money(h.value, cur),
                              style: const TextStyle(fontWeight: FontWeight.w600)),
                        ],
                      ),
                      const SizedBox(height: 4),
                      LinearProgressIndicator(
                        value: maxMonth <= 0 ? 0 : h.value / maxMonth,
                        minHeight: 6,
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        FilledButton.icon(
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.primary,
            padding: const EdgeInsets.symmetric(vertical: 14),
          ),
          onPressed: () => _copyReport(d, user),
          icon: const Icon(Icons.copy_rounded),
          label: const Text('Copy report'),
        ),
        const SizedBox(height: 40),
      ],
    );
  }
}
