import 'package:flutter/material.dart';

import '../cloud_auth.dart';
import '../cloud_family.dart';
import '../session.dart';
import '../theme.dart';
import '../widgets/fancy.dart';
import '../widgets/ui.dart';

class _GroupsData {
  final List<FamilyInfo> groups;
  final Map<String, List<FamilyMember>> members;
  final List<FamilyInvite> received;
  final List<FamilyInvite> sent;
  const _GroupsData(this.groups, this.members, this.received, this.sent);
}

/// The Groups tab: your groups, and the Requests tab: requests you sent and received.
class FamilyScreen extends StatefulWidget {
  const FamilyScreen({super.key});

  @override
  State<FamilyScreen> createState() => _FamilyScreenState();
}

class _FamilyScreenState extends State<FamilyScreen> {
  late Future<_GroupsData> _future;
  bool _busy = false;
  bool _showRequests = false;

  String? get _me => CloudAuth.currentUser?.uid;
  String get _myName => Session.current.value?.name ?? 'Member';

  @override
  void initState() {
    super.initState();
    _future = _fetch();
  }

  // Gives up after 20 seconds, so a slow or offline connection shows an error instead of spinning forever.
  Future<_GroupsData> _fetch() => _load().timeout(const Duration(seconds: 20));

  void _reload() => setState(() => _future = _fetch());

  void _snack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<_GroupsData> _load() async {
    if (CloudAuth.currentUser == null) {
      return const _GroupsData([], {}, [], []);
    }
    final groups = await CloudFamily.myFamilies();
    final members = <String, List<FamilyMember>>{};
    for (final g in groups) {
      members[g.id] = await CloudFamily.members(g.id);
    }
    final received = await CloudFamily.receivedInvites();
    final sent = await CloudFamily.sentInvites();
    return _GroupsData(groups, members, received, sent);
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

  Future<String?> _askText(String title, String label, {String initial = ''}) async {
    final c = TextEditingController(text: initial);
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

  Future<void> _createGroup() async {
    final name = await _askText('Name your group', 'Group name');
    if (name == null) return;
    await _run(() async {
      await CloudFamily.createFamily(name, _myName);
    }, 'Group created.');
  }

  Future<void> _rename(FamilyInfo g) async {
    final name = await _askText('Change group name', 'Group name', initial: g.name);
    if (name == null) return;
    await _run(() => CloudFamily.renameFamily(g.id, name), 'Name changed.');
  }

  Future<void> _addMember(FamilyInfo g) async {
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
                decoration: const InputDecoration(labelText: 'Add by'),
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
                keyboardType: kind == 'phone' ? TextInputType.phone : TextInputType.emailAddress,
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
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Send request')),
          ],
        ),
      ),
    );
    final value = c.text.trim();
    c.dispose();
    if (ok != true) return;
    await _run(() => CloudFamily.addMember(
          familyId: g.id,
          familyName: g.name,
          myName: _myName,
          kind: kind,
          value: value,
        ), 'Request sent. Check the Requests tab for its status.');
  }

  String _statusText(String status) {
    switch (status) {
      case 'approved':
        return 'Approved';
      case 'rejected':
        return 'Rejected';
      default:
        return 'Pending';
    }
  }

  @override
  Widget build(BuildContext context) {
    final signedIn = CloudAuth.currentUser != null;
    return Scaffold(
      body: Column(
        children: [
          GradientHeader(
            child: Column(
              children: [
                Row(
                  children: [
                    const Text('Groups',
                        style: TextStyle(
                            color: Colors.white, fontSize: 22, fontWeight: FontWeight.w800)),
                    const Spacer(),
                    if (signedIn)
                      IconButton(
                        tooltip: 'Create group',
                        onPressed: _busy ? null : _createGroup,
                        icon: const Icon(Icons.add_rounded, color: Colors.white),
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
                      _ToggleOption(
                        label: 'Groups',
                        selected: !_showRequests,
                        onTap: () => setState(() => _showRequests = false),
                      ),
                      _ToggleOption(
                        label: 'Requests',
                        selected: _showRequests,
                        onTap: () => setState(() => _showRequests = true),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Expanded(child: _content()),
        ],
      ),
    );
  }

  Widget _content() {
    if (CloudAuth.currentUser == null) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: SoftCard(
          child: Text(
              'Connect to the cloud first. Sign in with Google, or sign in with your username and password.'),
        ),
      );
    }
    return FutureBuilder<_GroupsData>(
      future: _future,
      builder: (context, snap) {
        if (snap.hasError) {
          return Padding(
            padding: const EdgeInsets.all(16),
            child: SoftCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text("Couldn't load groups and requests.",
                      style: TextStyle(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 6),
                  Text('${snap.error}', style: const TextStyle(color: AppColors.muted)),
                  const SizedBox(height: 12),
                  FilledButton(onPressed: _reload, child: const Text('Try again')),
                ],
              ),
            ),
          );
        }
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final d = snap.data!;
        return _showRequests ? _requestsTab(d) : _groupsTab(d);
      },
    );
  }

  Widget _groupsTab(_GroupsData d) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        for (final g in d.groups) ...[
          _groupCard(g, d.members[g.id] ?? const []),
          const SizedBox(height: 14),
        ],
        if (d.groups.isEmpty)
          SoftCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('You are not in a group yet.',
                    style: TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 6),
                const Text('Create a group, then add members by Gmail, phone number or username.'),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: _busy ? null : _createGroup,
                  icon: const Icon(Icons.groups_rounded),
                  label: const Text('Create a group'),
                ),
              ],
            ),
          ),
        if (d.groups.isNotEmpty)
          OutlinedButton.icon(
            onPressed: _busy ? null : _createGroup,
            icon: const Icon(Icons.add_rounded),
            label: const Text('Create another group'),
          ),
      ],
    );
  }

  Widget _groupCard(FamilyInfo g, List<FamilyMember> members) {
    return SoftCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(g.name,
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
              ),
              IconButton(
                tooltip: 'Change name',
                icon: const Icon(Icons.edit_rounded),
                onPressed: _busy ? null : () => _rename(g),
              ),
            ],
          ),
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
              trailing: g.isAdmin && m.uid != _me
                  ? IconButton(
                      tooltip: 'Remove from group',
                      icon: const Icon(Icons.person_remove_rounded),
                      onPressed: _busy
                          ? null
                          : () => _run(() => CloudFamily.removeMember(g.id, m.uid),
                              '${m.name} removed.'),
                    )
                  : null,
            ),
          const SizedBox(height: 10),
          FilledButton.icon(
            onPressed: _busy ? null : () => _addMember(g),
            icon: const Icon(Icons.person_add_alt_1_rounded),
            label: const Text('Add member'),
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: _busy
                ? null
                : () => _run(() => CloudFamily.leaveFamily(g.id), 'You left ${g.name}.'),
            child: const Text('Exit group'),
          ),
        ],
      ),
    );
  }

  Widget _requestsTab(_GroupsData d) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text('Received',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
        const SizedBox(height: 10),
        if (d.received.isEmpty)
          const SoftCard(child: Text('No requests received.')),
        for (final r in d.received)
          SoftCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${r.invitedByName} wants you to join',
                    style: const TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                Text('Group: ${r.familyName}'),
                const SizedBox(height: 4),
                Text('Status: ${_statusText(r.status)}',
                    style: const TextStyle(color: AppColors.muted)),
                if (r.isPending) ...[
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: _busy
                              ? null
                              : () => _run(() => CloudFamily.rejectInvite(r), 'Request rejected.'),
                          child: const Text('Reject'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: FilledButton(
                          onPressed: _busy
                              ? null
                              : () => _run(() => CloudFamily.acceptInvite(r, _myName),
                                  'You joined ${r.familyName}.'),
                          child: const Text('Accept'),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        const SizedBox(height: 20),
        const Text('Sent',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
        const SizedBox(height: 10),
        if (d.sent.isEmpty)
          const SoftCard(child: Text('No requests sent.')),
        for (final s in d.sent)
          SoftCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(s.targetLabel, style: const TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                Text('Group: ${s.familyName}'),
                const SizedBox(height: 4),
                Text('Status: ${_statusText(s.status)}',
                    style: TextStyle(
                        color: s.status == 'approved'
                            ? AppColors.green
                            : s.status == 'rejected'
                                ? AppColors.red
                                : AppColors.muted)),
              ],
            ),
          ),
      ],
    );
  }
}

class _ToggleOption extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _ToggleOption({required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: selected ? AppColors.primary : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: TextStyle(
              color: selected ? Colors.white : AppColors.deep,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }
}
