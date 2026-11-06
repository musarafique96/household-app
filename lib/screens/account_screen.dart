import 'package:flutter/material.dart';

import '../currencies.dart';
import '../data/db.dart';
import '../data/models.dart';
import '../session.dart';
import '../theme.dart';
import '../widgets/fancy.dart';
import '../widgets/ui.dart';
import 'group_detail_screen.dart';

class _AccountsData {
  final List<AppUser> users;
  final List<Group> groups;
  const _AccountsData(this.users, this.groups);
}

class AccountScreen extends StatefulWidget {
  const AccountScreen({super.key});

  @override
  State<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends State<AccountScreen> {
  bool _showGroups = false;
  late Future<_AccountsData> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<_AccountsData> _load() async {
    final users = await Db.instance.users();
    final groups = await Db.instance.groups();
    return _AccountsData(users, groups);
  }

  void _refresh() {
    setState(() {
      _future = _load();
    });
  }

  /// Shows a name and currency dialog. Returns null if cancelled.
  Future<(String, String)?> _accountDialog({
    required String title,
    String name = '',
    String currency = 'SAR',
  }) async {
    final nameCtrl = TextEditingController(text: name);
    final choices = currencyChoices(extra: currency);
    var code = currency;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialog) => FancyAlert(
          title: Text(title),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtrl,
                decoration: const InputDecoration(labelText: 'Name'),
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                value: code,
                decoration: const InputDecoration(labelText: 'Currency'),
                items: [
                  for (final c in choices) DropdownMenuItem(value: c, child: Text(c)),
                ],
                onChanged: (v) {
                  if (v != null) setDialog(() => code = v);
                },
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Save')),
          ],
        ),
      ),
    );
    final n = nameCtrl.text.trim();
    if (ok != true || n.isEmpty || code.isEmpty) return null;
    return (n, code);
  }

  Future<void> _createAccount() async {
    final result = await _accountDialog(title: 'Create account', currency: 'SAR');
    if (result == null) return;
    await Db.instance.addUser(result.$1, result.$2);
    _refresh();
  }

  Future<void> _editAccount(AppUser u) async {
    final result = await _accountDialog(
      title: 'Edit account',
      name: u.name,
      currency: u.currency,
    );
    if (result == null) return;
    await Db.instance.updateUser(u.id, result.$1, result.$2);
    if (Session.current.value?.id == u.id) {
      await Session.select(AppUser(id: u.id, name: result.$1, currency: result.$2));
    }
    _refresh();
  }

  Future<void> _createGroup(List<AppUser> users) async {
    final nameCtrl = TextEditingController();
    final selected = <int>{for (final u in users) u.id};

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => FancyAlert(
        title: const Text('Create group'),
        content: StatefulBuilder(
          builder: (ctx, setDialog) => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtrl,
                decoration: const InputDecoration(labelText: 'Group name (e.g. Family)'),
              ),
              const SizedBox(height: 8),
              for (final u in users)
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
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Create')),
        ],
      ),
    );

    final name = nameCtrl.text.trim();
    if (ok == true && name.isNotEmpty && selected.isNotEmpty) {
      await Db.instance.addGroup(name, selected.toList());
      _refresh();
    }
  }

  void _openGroup(Group g) {
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => GroupDetailScreen(groupId: g.id)))
        .then((_) => _refresh());
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AppUser?>(
      valueListenable: Session.current,
      builder: (context, current, _) {
        return FutureBuilder<_AccountsData>(
          future: _future,
          builder: (context, snap) {
            final d = snap.data;
            final cur = current?.currency ?? '';

            return ListView(
              padding: EdgeInsets.zero,
              children: [
                GradientHeader(
                  child: Column(
                    children: [
                      Row(
                        children: [
                          const Text('Accounts',
                              style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 22,
                                  fontWeight: FontWeight.w800)),
                          const Spacer(),
                          IconButton(
                            tooltip: 'Create account',
                            onPressed: _createAccount,
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
                              label: 'My Accounts',
                              selected: !_showGroups,
                              onTap: () => setState(() => _showGroups = false),
                            ),
                            _ToggleOption(
                              label: 'Groups',
                              selected: _showGroups,
                              onTap: () => setState(() => _showGroups = true),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (d == null)
                        const Center(child: CircularProgressIndicator())
                      else if (!_showGroups) ...[
                        if (d.users.isEmpty)
                          const SoftCard(child: Text('No accounts yet. Tap + to create one.')),
                        for (var i = 0; i < d.users.length; i++)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: _AccountCard(
                              user: d.users[i],
                              primary: i == 0,
                              isCurrent: current?.id == d.users[i].id,
                              onEdit: () => _editAccount(d.users[i]),
                            ),
                          ),
                      ] else ...[
                        if (d.groups.isEmpty)
                          const SoftCard(child: Text('No groups yet. Create one for family or trips.')),
                        for (final g in d.groups)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: SoftCard(
                              onTap: () => _openGroup(g),
                              child: Row(
                                children: [
                                  const IconBubble(
                                      icon: Icons.groups_rounded,
                                      color: AppColors.primary,
                                      size: 48),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(g.name,
                                            style: const TextStyle(
                                                fontWeight: FontWeight.w800, fontSize: 16)),
                                        Text('${g.members.length} members • $cur',
                                            style: const TextStyle(
                                                color: AppColors.muted, fontSize: 12)),
                                      ],
                                    ),
                                  ),
                                  const Icon(Icons.chevron_right_rounded),
                                ],
                              ),
                            ),
                          ),
                        OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            foregroundColor: AppColors.primary,
                            side: const BorderSide(color: AppColors.primary),
                          ),
                          onPressed: () => _createGroup(d.users),
                          icon: const Icon(Icons.add_rounded),
                          label: const Text('Create New Group'),
                        ),
                      ],
                      const SizedBox(height: 24),
                      const Text('Quick Actions',
                          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: QuickTile(
                              icon: Icons.edit_rounded,
                              label: 'Edit Account',
                              color: AppColors.primary,
                              onTap: () {
                                if (current != null) {
                                  _editAccount(current);
                                } else {
                                  _snack('Choose an account first.');
                                }
                              },
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: QuickTile(
                              icon: Icons.people_alt_rounded,
                              label: 'Manage Members',
                              color: AppColors.pink,
                              onTap: () => setState(() => _showGroups = true),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: QuickTile(
                              icon: Icons.currency_exchange_rounded,
                              label: 'Change Currency',
                              color: AppColors.amber,
                              onTap: () {
                                if (current != null) {
                                  _editAccount(current);
                                } else {
                                  _snack('Choose an account first.');
                                }
                              },
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: QuickTile(
                              icon: Icons.archive_rounded,
                              label: 'Archive',
                              color: AppColors.blue,
                              onTap: () => _snack('Archiving is coming in a later update.'),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 40),
                    ],
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _snack(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
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

class _AccountCard extends StatelessWidget {
  final AppUser user;
  final bool primary;
  final bool isCurrent;
  final VoidCallback onEdit;

  const _AccountCard({
    required this.user,
    required this.primary,
    required this.isCurrent,
    required this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    return SoftCard(
      onTap: onEdit,
      child: Row(
        children: [
          const CircleAvatar(
            radius: 24,
            backgroundColor: AppColors.soft,
            child: Icon(Icons.person_rounded, color: AppColors.primary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(user.name,
                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                Text(primary ? 'Primary • ${user.currency}' : user.currency,
                    style: const TextStyle(color: AppColors.muted, fontSize: 12)),
              ],
            ),
          ),
          if (isCurrent)
            const Icon(Icons.check_circle_rounded, color: AppColors.green, size: 28)
          else
            OutlinedButton(
              onPressed: () => Session.select(user),
              child: const Text('Use'),
            ),
        ],
      ),
    );
  }
}
