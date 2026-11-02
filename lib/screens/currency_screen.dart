import 'package:flutter/material.dart';

import '../data/db.dart';
import '../data/models.dart';
import '../session.dart';
import '../theme.dart';
import '../widgets/ui.dart';

/// Exchange rates for other currencies, in the account currency.
class CurrencyScreen extends StatefulWidget {
  const CurrencyScreen({super.key});

  @override
  State<CurrencyScreen> createState() => _CurrencyScreenState();
}

class _CurrencyScreenState extends State<CurrencyScreen> {
  late Future<Map<String, double>?> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<Map<String, double>?> _load() async {
    final user = Session.current.value;
    if (user == null) return null;
    return Db.instance.exchangeRates(user.id);
  }

  void _refresh() {
    setState(() {
      _future = _load();
    });
  }

  void _snack(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _addRate(AppUser user) async {
    final codeCtrl = TextEditingController();
    final rateCtrl = TextEditingController();

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add exchange rate'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: codeCtrl,
              decoration: const InputDecoration(labelText: 'Currency code (e.g. USD)'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: rateCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: '1 unit of that currency = ? ${user.currency}',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Save')),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    final code = codeCtrl.text.trim().toUpperCase();
    final rate = double.tryParse(rateCtrl.text.trim());
    if (!RegExp(r'^[A-Z]{3}$').hasMatch(code)) {
      _snack('Enter a 3-letter currency code, such as USD.');
      return;
    }
    if (code == user.currency) {
      _snack('${user.currency} is already your account currency.');
      return;
    }
    if (rate == null || rate <= 0) {
      _snack('Enter a rate above zero.');
      return;
    }

    await Db.instance.setExchangeRate(user.id, code, rate);
    _refresh();
  }

  Future<void> _deleteRate(AppUser user, String code) async {
    await Db.instance.deleteExchangeRate(user.id, code);
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
              label: const Text('Add rate'),
              onPressed: () => _addRate(user),
            ),
      body: user == null
          ? const Center(child: Text('Choose an account in the Accounts tab first.'))
          : FutureBuilder<Map<String, double>?>(
              future: _future,
              builder: (context, snap) {
                final rates = snap.data;
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
                          const Text('Currency',
                              style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 22,
                                  fontWeight: FontWeight.w800)),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
                      child: rates == null
                          ? const Center(child: CircularProgressIndicator())
                          : Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                SoftCard(
                                  child: Text(
                                    'Your account currency is ${user.currency}. Add how much one unit of another currency is worth in ${user.currency}. Each expense keeps the rate from the day it was added, so old totals do not change.',
                                    style: const TextStyle(color: AppColors.muted),
                                  ),
                                ),
                                const SizedBox(height: 16),
                                if (rates.isEmpty)
                                  const SoftCard(
                                      child: Text('No other currencies yet. Tap Add rate.')),
                                for (final entry in rates.entries)
                                  Padding(
                                    padding: const EdgeInsets.only(bottom: 12),
                                    child: SoftCard(
                                      child: Row(
                                        children: [
                                          const IconBubble(
                                              icon: Icons.currency_exchange_rounded,
                                              color: AppColors.amber),
                                          const SizedBox(width: 12),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Text(entry.key,
                                                    style: const TextStyle(
                                                        fontWeight: FontWeight.w800,
                                                        fontSize: 16)),
                                                Text(
                                                  '1 ${entry.key} = ${entry.value.toStringAsFixed(4)} ${user.currency}',
                                                  style: const TextStyle(
                                                      color: AppColors.muted, fontSize: 12),
                                                ),
                                              ],
                                            ),
                                          ),
                                          IconButton(
                                            tooltip: 'Delete rate',
                                            onPressed: () => _deleteRate(user, entry.key),
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
