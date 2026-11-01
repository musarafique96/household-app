import 'package:flutter/material.dart';

import '../data/db.dart';
import '../data/models.dart';
import '../session.dart';

class AccountScreen extends StatefulWidget {
  const AccountScreen({super.key});

  @override
  State<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends State<AccountScreen> {
  final _nameCtrl = TextEditingController();
  final _currencyCtrl = TextEditingController(text: 'SAR');
  late Future<List<AppUser>> _future;
  String _status = '';

  @override
  void initState() {
    super.initState();
    _future = Db.instance.users();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _currencyCtrl.dispose();
    super.dispose();
  }

  void _reload() {
    setState(() {
      _future = Db.instance.users();
    });
  }

  Future<void> _create() async {
    final name = _nameCtrl.text.trim();
    final code = _currencyCtrl.text.trim().toUpperCase();
    if (name.isEmpty || code.isEmpty) {
      setState(() => _status = 'Enter a name and a currency code.');
      return;
    }
    await Db.instance.addUser(name, code);
    _nameCtrl.clear();
    setState(() => _status = 'Created $name ($code).');
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Accounts')),
      body: FutureBuilder<List<AppUser>>(
        future: _future,
        builder: (context, snap) {
          final users = snap.data ?? const <AppUser>[];
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text('Who is using this phone?', style: theme.textTheme.titleMedium),
              const SizedBox(height: 8),
              if (users.isEmpty) const Text('No accounts yet. Create one below.'),
              for (final u in users)
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.person),
                    title: Text(u.name),
                    subtitle: Text('Currency: ${u.currency}'),
                    trailing: ValueListenableBuilder<AppUser?>(
                      valueListenable: Session.current,
                      builder: (context, current, _) => current?.id == u.id
                          ? const Icon(Icons.check_circle, color: Colors.green)
                          : OutlinedButton(
                              onPressed: () => Session.select(u),
                              child: const Text('Use'),
                            ),
                    ),
                  ),
                ),
              const SizedBox(height: 24),
              Text('Create an account', style: theme.textTheme.titleMedium),
              const SizedBox(height: 8),
              TextField(
                controller: _nameCtrl,
                decoration: const InputDecoration(labelText: 'Name'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _currencyCtrl,
                decoration: const InputDecoration(
                  labelText: 'Currency code (SAR, PKR, USD)',
                ),
              ),
              const SizedBox(height: 12),
              FilledButton(onPressed: _create, child: const Text('Create account')),
              const SizedBox(height: 8),
              Text(_status),
            ],
          );
        },
      ),
    );
  }
}
