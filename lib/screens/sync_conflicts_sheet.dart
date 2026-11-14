import 'package:flutter/material.dart';

import '../cloud_auth.dart';
import '../cloud_family.dart';
import '../session.dart';
import '../theme.dart';
import '../util.dart';
import '../widgets/ui.dart';

/// Lists budget changes the cloud kept back, and lets the family choose which version to keep.
class SyncConflictsSheet extends StatefulWidget {
  final String familyId;

  const SyncConflictsSheet({super.key, required this.familyId});

  @override
  State<SyncConflictsSheet> createState() => _SyncConflictsSheetState();
}

class _SyncConflictsSheetState extends State<SyncConflictsSheet> {
  late Future<List<SyncConflict>> _future;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _future = CloudFamily.conflicts(widget.familyId);
  }

  void _reload() => setState(() => _future = CloudFamily.conflicts(widget.familyId));

  void _snack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _resolve(SyncConflict c, {required bool keepMine}) async {
    setState(() => _busy = true);
    try {
      await CloudFamily.resolveConflict(widget.familyId, c, keepMine: keepMine);
    } on CloudAuthException catch (e) {
      _snack(e.message);
    } catch (e) {
      _snack('Something went wrong. $e');
    } finally {
      if (mounted) setState(() => _busy = false);
      _reload();
    }
  }

  String _title(SyncConflict c) => c.entity == 'expense' ? 'Expense' : 'Budget category';

  /// Describes what this phone wanted to save. Empty data means this phone wanted to delete the item.
  String _describe(SyncConflict c, String currency) {
    final d = c.clientData;
    if (d.isEmpty) return 'Deleted on this phone.';
    if (c.entity == 'expense') {
      final amount = (d['amount'] as num?)?.toDouble() ?? 0;
      final note = (d['note'] as String?) ?? '';
      final date = (d['expenseDate'] as String?) ?? '';
      final parts = [money(amount, currency), if (note.isNotEmpty) note, if (date.isNotEmpty) date];
      return parts.join(' · ');
    }
    final name = (d['name'] as String?) ?? '';
    final limit = (d['monthlyLimit'] as num?)?.toDouble() ?? 0;
    return '$name · monthly limit ${money(limit, currency)}';
  }

  @override
  Widget build(BuildContext context) {
    final currency = Session.current.value?.currency ?? '';
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
        child: FutureBuilder<List<SyncConflict>>(
          future: _future,
          builder: (context, snap) {
            if (snap.hasError) {
              return Padding(
                padding: const EdgeInsets.all(16),
                child: Text('Could not load conflicts: ${snap.error}'),
              );
            }
            final list = snap.data;
            if (list == null) {
              return const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              );
            }
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text('Sync conflicts',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
                const SizedBox(height: 4),
                const Text(
                  'A change from one phone clashed with a newer change. Choose which version to keep.',
                  style: TextStyle(color: AppColors.muted, fontSize: 12),
                ),
                const SizedBox(height: 12),
                if (list.isEmpty)
                  const SoftCard(child: Text('No conflicts. Everything is in sync.')),
                for (final c in list)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: SoftCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(_title(c), style: const TextStyle(fontWeight: FontWeight.w800)),
                          const SizedBox(height: 4),
                          Text(_describe(c, currency)),
                          const SizedBox(height: 4),
                          Text(
                            'This phone saw version ${c.clientVersion}. The cloud is at version ${c.serverVersion}.',
                            style: const TextStyle(color: AppColors.muted, fontSize: 12),
                          ),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              Expanded(
                                child: FilledButton(
                                  onPressed: _busy ? null : () => _resolve(c, keepMine: true),
                                  child: const Text("Keep phone's"),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: OutlinedButton(
                                  onPressed: _busy ? null : () => _resolve(c, keepMine: false),
                                  child: const Text("Keep cloud's"),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}
