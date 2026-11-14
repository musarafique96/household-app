import 'package:flutter/material.dart';

import '../cloud_family.dart';
import '../data/db.dart';
import '../group_currency.dart';
import '../session.dart';
import '../theme.dart';
import '../util.dart';
import '../widgets/ui.dart';

/// The group's budget for one month. Amounts are shown in the member's chosen currency (group or own).
class GroupBudgetScreen extends StatefulWidget {
  final FamilyInfo group;

  const GroupBudgetScreen({super.key, required this.group});

  @override
  State<GroupBudgetScreen> createState() => _GroupBudgetScreenState();
}

class _GroupBudget {
  final List<GroupCategory> categories;
  final List<GroupExpense> expenses;
  final String ownCurrency;
  final Map<String, double> rates;
  _GroupBudget(this.categories, this.expenses, this.ownCurrency, this.rates);
}

class _GroupBudgetState extends State<GroupBudgetScreen> {
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month, 1);
  late String _view = widget.group.viewCurrency;
  late Future<_GroupBudget> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<_GroupBudget> _load() async {
    final me = Session.current.value;
    final from = ymd(_month);
    final to = ymd(DateTime(_month.year, _month.month + 1, 0));
    final categories = await CloudFamily.groupCategories(widget.group.id);
    final expenses = await CloudFamily.groupExpenses(widget.group.id, from: from, to: to);
    final rates = me == null ? <String, double>{} : await Db.instance.exchangeRates(me.id);
    return _GroupBudget(categories, expenses, me?.currency ?? '', rates);
  }

  void _shiftMonth(int delta) {
    setState(() {
      _month = DateTime(_month.year, _month.month + delta, 1);
      _future = _load();
    });
  }

  Future<void> _setView(String view) async {
    final previous = _view;
    setState(() => _view = view);
    try {
      await CloudFamily.setViewCurrency(widget.group.id, view);
    } catch (e) {
      if (!mounted) return;
      setState(() => _view = previous);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not save. $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final group = widget.group.currency;
    return Scaffold(
      appBar: AppBar(title: Text(widget.group.name)),
      body: FutureBuilder<_GroupBudget>(
        future: _future,
        builder: (context, snap) {
          if (snap.hasError) {
            return Padding(
              padding: const EdgeInsets.all(16),
              child: Text('Could not load the group budget. Check the connection.\n${snap.error}'),
            );
          }
          final data = snap.data;
          if (data == null) {
            return const Center(child: CircularProgressIndicator());
          }
          final showOwn = _view == 'own' && data.ownCurrency.isNotEmpty && data.ownCurrency != group;
          final shownCurrency = showOwn ? data.ownCurrency : group;

          ShownAmount show(double groupAmount) => showInView(
                groupAmount: groupAmount,
                groupCurrency: group,
                ownCurrency: data.ownCurrency,
                rates: data.rates,
                showOwn: _view == 'own',
              );

          final missingRate = data.expenses.any((e) => show(e.amount).needsRate) ||
              (showOwn && data.categories.any((c) => show(c.monthlyLimit).needsRate));

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            children: [
              Row(
                children: [
                  IconButton(icon: const Icon(Icons.chevron_left_rounded), onPressed: () => _shiftMonth(-1)),
                  Expanded(
                    child: Text(monthLabel(_month),
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                  ),
                  IconButton(icon: const Icon(Icons.chevron_right_rounded), onPressed: () => _shiftMonth(1)),
                ],
              ),
              if (data.ownCurrency.isNotEmpty && data.ownCurrency != group) ...[
                SegmentedButton<String>(
                  segments: [
                    ButtonSegment(value: 'group', label: Text(group)),
                    ButtonSegment(value: 'own', label: Text(data.ownCurrency)),
                  ],
                  selected: {_view},
                  onSelectionChanged: (s) => _setView(s.first),
                ),
                const SizedBox(height: 12),
              ],
              if (missingRate)
                SoftCard(
                  child: Text(
                    'Some amounts are shown in $group because you have no $group rate. '
                    'Add it in More > Currency to see them in ${data.ownCurrency}.',
                    style: const TextStyle(color: AppColors.muted, fontSize: 12),
                  ),
                ),
              if (missingRate) const SizedBox(height: 12),
              for (final c in data.categories) _categoryCard(c, data, show, shownCurrency, showOwn),
              _categoryCard(
                GroupCategory('', 'No category', 0),
                data,
                show,
                shownCurrency,
                showOwn,
                uncategorised: true,
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _categoryCard(
    GroupCategory c,
    _GroupBudget data,
    ShownAmount Function(double) show,
    String shownCurrency,
    bool showOwn, {
    bool uncategorised = false,
  }) {
    final group = widget.group.currency;
    final items = data.expenses
        .where((e) => uncategorised ? e.categoryId == null : e.categoryId == c.id)
        .toList();
    if (uncategorised && items.isEmpty) return const SizedBox.shrink();

    // A total is shown only when every expense in it can be converted, so no mixed-currency number appears.
    final converted = [for (final e in items) show(e.amount)];
    final anyMissing = converted.any((s) => s.needsRate);
    final total = converted.fold<double>(0, (sum, s) => sum + s.amount);
    final limit = uncategorised ? null : show(c.monthlyLimit);
    final limitText = limit == null
        ? ''
        : limit.needsRate
            ? money(c.monthlyLimit, group)
            : money(limit.amount, limit.currency);

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: SoftCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(uncategorised ? 'No category' : c.name,
                      style: const TextStyle(fontWeight: FontWeight.w800)),
                ),
                if (!uncategorised) Text('limit $limitText', style: const TextStyle(color: AppColors.muted, fontSize: 12)),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              anyMissing ? 'Add the $group rate to see this total' : 'Spent ${money(total, shownCurrency)}',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            for (var i = 0; i < items.length; i++) ...[
              const Divider(height: 18),
              _expenseRow(items[i], converted[i], group),
            ],
          ],
        ),
      ),
    );
  }

  Widget _expenseRow(GroupExpense e, ShownAmount s, String group) {
    final shown = s.needsRate ? money(e.amount, group) : money(s.amount, s.currency);
    final entered = (e.originalAmount != null && e.originalCurrency != null && e.originalCurrency!.isNotEmpty)
        ? 'Entered as ${money(e.originalAmount!, e.originalCurrency!)}'
        : null;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(e.note.isEmpty ? 'Expense' : e.note),
              Text(e.date, style: const TextStyle(color: AppColors.muted, fontSize: 12)),
              if (entered != null)
                Text(entered, style: const TextStyle(color: AppColors.muted, fontSize: 12)),
            ],
          ),
        ),
        Text(s.needsRate ? '$shown\nadd rate' : shown, textAlign: TextAlign.end),
      ],
    );
  }
}
