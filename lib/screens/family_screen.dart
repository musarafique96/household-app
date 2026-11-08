import 'package:flutter/material.dart';

import '../cloud_auth.dart';
import '../cloud_family.dart';
import '../session.dart';
import '../theme.dart';
import '../widgets/fancy.dart';
import '../widgets/ui.dart';

class _FamilyData {
  final List<FamilyInfo> families;
  final List<FamilyInvite> invites;
  final Map<String, List<FamilyMember>> members;
  const _FamilyData(this.families, this.invites, this.members);
}

/// Create a family, invite people by Gmail, phone number or username, and accept or reject invites.
class FamilyScreen extends StatefulWidget {
  const FamilyScreen({super.key});

  @override
  State<FamilyScreen> createState() => _FamilyScreenState();
}

class _FamilyScreenState extends State<FamilyScreen> {
  late Future<_FamilyData> _future;
  bool _busy = false;

  String? get _me => CloudAuth.currentUser?.uid;
  String get _myName => Session.current.value?.name ?? 'Member';

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  void _reload() => setState(() => _future = _load());

  void _snack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<_FamilyData> _load() async {
    if (CloudAuth.currentUser == null) {
      return const _FamilyData([], [], {});
    }
    final invites = await CloudFamily.myInvites();
    final families = await CloudFamily.myFamilies();
    final members = <String, List<FamilyMember>>{};
    for (final f in families) {
      members[f.id] = await CloudFamily.members(f.id);
    }
    return _FamilyData(families, invites, members);
  }

  Future<void> _run(Future<void> Function() action, String doneText) async {
    setState(() => _busy = true);
    try {
      await action();
      _snack(doneText);
    } on CloudAuthException catch (e) {
      _snack(e.message);
    } catch (e) {
      _snack('Something went wrong. $e');
    } finally {
      if (mounted) setState(() => _busy = false);
      _reload();
    }
  }

  Future<String?> _askText(String title, String label) async {
    final c = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => FancyAlert(
        icon: Icons.groups_rounded,
        title: Text(title),
        content: TextField(
          controller: c,
          autofocus: true,
          decoration: InputDecoration(labelText: label),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Save')),
        ],
      ),
    );
    final text = c.text.trim();
    c.dispose();
    return ok == true && text.isNotEmpty ? text : null;
  }

  Future<void> _createFamily() async {
    final name = await _askText('Name your group', 'Group name');
    if (name == null) return;
    await _run(() async {
      await CloudFamily.createFamily(name, _myName);
    }, 'Group created.');
  }

  Future<void> _invite(FamilyInfo f) async {
    var kind = 'gmail';
    final c = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => FancyAlert(
          icon: Icons.person_add_alt_1_rounded,
          title: const Text('Add member'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                value: kind,
                decoration: const InputDecoration(labelText: 'Invite by'),
                items: const [
                  DropdownMenuItem(value: 'gmail', child: Text('Gmail')),
                  DropdownMenuItem(value: 'phone', child: Text('Phone number')),
                  DropdownMenuItem(value: 'user', child: Text('Username')),
                ],
                onChanged: (v) => setD(() => kind = v ?? kind),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: c,
                keyboardType: kind == 'phone'
                    ? TextInputType.phone
                    : TextInputType.emailAddress,
                decoration: InputDecoration(
                  labelText: kind == 'gmail'
                      ? 'Gmail address'
                      : kind == 'phone'
                          ? 'Phone number'
                          : 'Username',
                ),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Send invite')),
          ],
        ),
      ),
    );
    final value = c.text.trim();
    c.dispose();
    if (ok != true) return;
    await _run(() async {
      await CloudFamily.invite(
        familyId: f.id,
        familyName: f.name,
        kind: kind,
        value: value,
      );
    }, 'Invite sent. They will see it when they sign in.');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Groups')),
      body: CloudAuth.currentUser == null
          ? const Padding(
              padding: EdgeInsets.all(16),
              child: SoftCard(
                child: Text(
                    'Connect to the cloud first. Sign in with Google, or connect your username from your profile.'),
              ),
            )
          : FutureBuilder<_FamilyData>(
              future: _future,
              builder: (context, snap) {
                if (!snap.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final d = snap.data!;
                return ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    if (d.invites.isNotEmpty) ...[
                      const Text('Invites',
                          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 10),
                      for (final inv in d.invites)
                        SoftCard(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Join "${inv.familyName}"?',
                                  style: const TextStyle(fontWeight: FontWeight.w700)),
                              const SizedBox(height: 10),
                              Row(
                                children: [
                                  Expanded(
                                    child: OutlinedButton(
                                      onPressed: _busy
                                          ? null
                                          : () => _run(() => CloudFamily.rejectInvite(inv),
                                              'Invite rejected.'),
                                      child: const Text('Reject'),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: FilledButton(
                                      onPressed: _busy
                                          ? null
                                          : () => _run(
                                              () => CloudFamily.acceptInvite(inv, _myName),
                                              'Joined ${inv.familyName}.'),
                                      child: const Text('Accept'),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      const SizedBox(height: 20),
                    ],
                    for (final f in d.families) ...[
                      _familyCard(f, d.members[f.id] ?? const []),
                      const SizedBox(height: 14),
                    ],
                    if (d.families.isEmpty)
                      SoftCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('You are not in a group yet.',
                                style: TextStyle(fontWeight: FontWeight.w700)),
                            const SizedBox(height: 6),
                            const Text(
                                'Create a group and add members by Gmail, phone number or username.'),
                            const SizedBox(height: 12),
                            FilledButton.icon(
                              onPressed: _busy ? null : _createFamily,
                              icon: const Icon(Icons.groups_rounded),
                              label: const Text('Create a group'),
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

  Widget _familyCard(FamilyInfo f, List<FamilyMember> members) {
    return SoftCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(f.name, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          for (final m in members)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                m.isAdmin ? Icons.admin_panel_settings_rounded : Icons.person_rounded,
                color: AppColors.primary,
              ),
              title: Text(m.name),
              subtitle: Text(m.isAdmin ? 'Admin' : 'Member'),
              trailing: f.isAdmin && m.uid != _me
                  ? IconButton(
                      tooltip: 'Remove from family',
                      icon: const Icon(Icons.person_remove_rounded),
                      onPressed: _busy
                          ? null
                          : () => _run(() => CloudFamily.removeMember(f.id, m.uid),
                              '${m.name} removed.'),
                    )
                  : null,
            ),
          const SizedBox(height: 10),
          if (f.isAdmin)
            FilledButton.icon(
              onPressed: _busy ? null : () => _invite(f),
              icon: const Icon(Icons.person_add_alt_1_rounded),
              label: const Text('Add member'),
            )
        ],
      ),
    );
  }
}
