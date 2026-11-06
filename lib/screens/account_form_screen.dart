import 'package:flutter/material.dart';

import '../currencies.dart';
import '../data/db.dart';
import '../data/models.dart';
import '../session.dart';
import '../theme.dart';
import '../util.dart';
import '../widgets/ui.dart';

/// Full page to add a new account, or edit an existing one.
/// Pops with `true` when saved.
class AccountFormScreen extends StatefulWidget {
  final AppUser? user;

  const AccountFormScreen({super.key, this.user});

  @override
  State<AccountFormScreen> createState() => _AccountFormScreenState();
}

class _AccountFormScreenState extends State<AccountFormScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _phone;
  late final TextEditingController _email;
  late final TextEditingController _address;
  late String _currency;
  late String _dob;
  bool _saving = false;

  bool get _isNew => widget.user == null;

  @override
  void initState() {
    super.initState();
    final u = widget.user;
    _name = TextEditingController(text: u?.name ?? '');
    _phone = TextEditingController(text: u?.phone ?? '');
    _email = TextEditingController(text: u?.email ?? '');
    _address = TextEditingController(text: u?.address ?? '');
    _currency = u?.currency ?? 'SAR';
    _dob = u?.dateOfBirth ?? '';
  }

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _email.dispose();
    _address.dispose();
    super.dispose();
  }

  Future<void> _pickDob() async {
    final initial = DateTime.tryParse(_dob) ?? DateTime(2000, 1, 1);
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(1920),
      lastDate: DateTime.now(),
      helpText: 'Date of birth',
    );
    if (picked != null) {
      setState(() => _dob = ymd(picked));
    }
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _saving = true);

    final saved = await Db.instance.saveUser(AppUser(
      id: widget.user?.id ?? 0,
      name: _name.text.trim(),
      currency: _currency,
      phone: _phone.text.trim(),
      email: _email.text.trim(),
      address: _address.text.trim(),
      dateOfBirth: _dob,
    ));

    // Keep the signed-in account's details up to date when it is edited.
    if (!_isNew && Session.current.value?.id == saved.id) {
      await Session.select(saved);
    }
    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final muted = dark ? const Color(0xFFB7B0CC) : AppColors.muted;

    return Scaffold(
      body: Form(
        key: _formKey,
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            GradientHeader(
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.pop(context, false),
                    icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
                  ),
                  const SizedBox(width: 4),
                  Text(_isNew ? 'New account' : 'Edit account',
                      style: const TextStyle(
                          color: Colors.white, fontSize: 22, fontWeight: FontWeight.w800)),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: CircleAvatar(
                      radius: 42,
                      backgroundColor: AppColors.soft,
                      child: Text(
                        _name.text.trim().isEmpty ? '?' : _name.text.trim()[0].toUpperCase(),
                        style: const TextStyle(
                            fontSize: 32, fontWeight: FontWeight.w800, color: AppColors.primary),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  SoftCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        TextFormField(
                          controller: _name,
                          textCapitalization: TextCapitalization.words,
                          onChanged: (_) => setState(() {}),
                          decoration: const InputDecoration(
                            labelText: 'Full name *',
                            prefixIcon: Icon(Icons.person_rounded),
                          ),
                          validator: (v) =>
                              (v == null || v.trim().isEmpty) ? 'Please enter a name' : null,
                        ),
                        const SizedBox(height: 14),
                        DropdownButtonFormField<String>(
                          value: _currency,
                          decoration: const InputDecoration(
                            labelText: 'Currency *',
                            prefixIcon: Icon(Icons.currency_exchange_rounded),
                          ),
                          items: [
                            for (final c in currencyChoices(extra: _currency))
                              DropdownMenuItem(value: c, child: Text(c)),
                          ],
                          onChanged: (v) {
                            if (v != null) setState(() => _currency = v);
                          },
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  SoftCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        TextFormField(
                          controller: _phone,
                          keyboardType: TextInputType.phone,
                          decoration: const InputDecoration(
                            labelText: 'Phone',
                            prefixIcon: Icon(Icons.phone_rounded),
                          ),
                        ),
                        const SizedBox(height: 14),
                        TextFormField(
                          controller: _email,
                          keyboardType: TextInputType.emailAddress,
                          decoration: const InputDecoration(
                            labelText: 'Email',
                            prefixIcon: Icon(Icons.mail_rounded),
                          ),
                          validator: (v) {
                            final t = v?.trim() ?? '';
                            if (t.isEmpty) return null;
                            return RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(t)
                                ? null
                                : 'Enter a valid email address';
                          },
                        ),
                        const SizedBox(height: 14),
                        TextFormField(
                          controller: _address,
                          minLines: 2,
                          maxLines: 3,
                          textCapitalization: TextCapitalization.sentences,
                          decoration: const InputDecoration(
                            labelText: 'Address',
                            alignLabelWithHint: true,
                            prefixIcon: Padding(
                              padding: EdgeInsets.only(bottom: 30),
                              child: Icon(Icons.home_rounded),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  SoftCard(
                    child: InkWell(
                      borderRadius: BorderRadius.circular(16),
                      onTap: _pickDob,
                      child: InputDecorator(
                        decoration: InputDecoration(
                          labelText: 'Date of birth (optional)',
                          prefixIcon: const Icon(Icons.cake_rounded),
                          suffixIcon: _dob.isEmpty
                              ? const Icon(Icons.calendar_month_rounded)
                              : IconButton(
                                  tooltip: 'Clear date',
                                  icon: const Icon(Icons.clear_rounded),
                                  onPressed: () => setState(() => _dob = ''),
                                ),
                        ),
                        child: Text(
                          _dob.isEmpty ? 'Not set' : _dob,
                          style: TextStyle(color: _dob.isEmpty ? muted : null),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: FilledButton.icon(
            onPressed: _saving ? null : _save,
            icon: const Icon(Icons.check_rounded),
            label: Text(_isNew ? 'Create account' : 'Save changes'),
          ),
        ),
      ),
    );
  }
}
