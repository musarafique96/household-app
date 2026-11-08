import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../auth.dart';
import '../cloud_auth.dart';
import '../build_info.dart';
import '../cloud_family.dart';
import '../widgets/fancy.dart';

import '../currencies.dart';
import '../dial_codes.dart';
import '../quick_login.dart';
import 'passkey_screen.dart';
import '../data/db.dart';
import '../data/models.dart';
import '../session.dart';
import '../theme.dart';
import '../util.dart';
import '../widgets/ui.dart';

/// Full page to add an account (or register), or edit an existing one.
/// Pops with `true` when saved.
///
/// With [signUp] the new account is signed in straight away, which is what
/// happens when someone registers from the login page.
class AccountFormScreen extends StatefulWidget {
  final AppUser? user;
  final bool signUp;

  const AccountFormScreen({super.key, this.user, this.signUp = false});

  @override
  State<AccountFormScreen> createState() => _AccountFormScreenState();
}

class _AccountFormScreenState extends State<AccountFormScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _username;
  late final TextEditingController _password;
  late final TextEditingController _confirm;
  late final TextEditingController _currentPassword;
  late final TextEditingController _name;
  late final TextEditingController _phone;
  String _dial = kDefaultDial;
  late final TextEditingController _email;
  late final TextEditingController _address;
  late String _currency;
  late String _dob;
  bool _saving = false;
  bool _obscure = true;
  String? _error;
  bool _usernameTaken = false;
  bool _quickOn = false;
  bool _hasPasskey = false;
  bool _passkeyOn = false;
  final _scroll = ScrollController();

  bool get _isNew => widget.user == null;

  String get _fullPhone => fullPhone(_dial, _phone.text);

  bool get _isSignedInUser =>
      !_isNew && Session.current.value?.id == widget.user!.id;

  @override
  void initState() {
    super.initState();
    final u = widget.user;
    _username = TextEditingController(text: u?.username ?? '');
    _password = TextEditingController();
    _confirm = TextEditingController();
    _currentPassword = TextEditingController();
    _name = TextEditingController(text: u?.name ?? '');
    final split = splitPhone(u?.phone ?? '');
    _dial = split.code;
    _phone = TextEditingController(text: split.number);
    _email = TextEditingController(text: u?.email ?? '');
    _address = TextEditingController(text: u?.address ?? '');
    _currency = u?.currency ?? 'SAR';
    _dob = u?.dateOfBirth ?? '';
    _hasPasskey = u?.hasPasskey ?? false;
    _passkeyOn = u?.passkeyEnabled ?? false;
    if (_isSignedInUser) _loadQuick();
  }

  Future<void> _loadQuick() async {
    final id = await QuickLogin.enabledUserId();
    if (mounted) setState(() => _quickOn = id == widget.user?.id);
  }

  @override
  void dispose() {
    _scroll.dispose();
    _username.dispose();
    _password.dispose();
    _confirm.dispose();
    _currentPassword.dispose();
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

  void _showError(String message) {
    setState(() => _error = message);
    if (_scroll.hasClients) {
      _scroll.animateTo(0,
          duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
    }
  }

  Future<void> _save() async {
    setState(() {
      _error = null;
      _usernameTaken = false;
    });
    if (!(_formKey.currentState?.validate() ?? false)) {
      _showError('Please fix the highlighted fields.');
      return;
    }

    final username = _username.text.trim();
    final existing = await Db.instance.findByUsername(username);
    if (existing != null && existing.id != (widget.user?.id ?? -1)) {
      setState(() => _usernameTaken = true);
      _formKey.currentState?.validate();
      _showError('That username is already taken. Choose another.');
      return;
    }

    setState(() => _saving = true);
    try {
      final password = _password.text;

      // Changing your own password: check the current one, then change it in the cloud too.
      if (_isSignedInUser && password.isNotEmpty && widget.user != null) {
        final creds = await Db.instance.credentialsFor(widget.user!.username);
        if (creds != null &&
            creds.passwordHash.isNotEmpty &&
            !Auth.verify(creds.salt, creds.passwordHash, _currentPassword.text)) {
          throw CloudAuthException('Current password is wrong.');
        }
        await CloudAuth.changePassword(_currentPassword.text, password);
      }
      final phone = _fullPhone;
      String cloudUid = '';

      // New username accounts also get a cloud account, so they can sync.
      if (widget.signUp && password.isNotEmpty) {
        User? cloudUser;
        try {
          cloudUser = await CloudAuth.signUp(username, password);
        } on CloudAuthException catch (e) {
          if (e.message.contains('taken') || e.message.contains('Password')) rethrow;
          // Otherwise (for example, no internet): saved on this phone, and joins the cloud later.
        } catch (_) {}
        if (cloudUser != null) {
          cloudUid = cloudUser.uid;
          if (phone.isNotEmpty) {
            try {
              await CloudAuth.setPhone(phone);
            } catch (e) {
              await cloudUser.delete();
              rethrow;
            }
          }
        }
      } else if (_isSignedInUser && CloudAuth.currentUser != null &&
          phone.isNotEmpty && phone != (widget.user?.phone ?? '')) {
        await CloudAuth.setPhone(phone, oldPhone: widget.user?.phone);
      }

      final saved = await Db.instance.saveUser(
        AppUser(
          id: widget.user?.id ?? 0,
          username: username,
          name: _name.text.trim(),
          currency: _currency,
          phone: _fullPhone,
          email: _email.text.trim(),
          address: _address.text.trim(),
          dateOfBirth: _dob,
          role: widget.user?.role ?? 'member',
        ),
        password: password.isEmpty ? null : password,
      );

      if (cloudUid.isNotEmpty) {
        await Db.instance.setFirebaseUid(saved.id, cloudUid);
      }
      if (CloudAuth.currentUser != null) {
        try {
          await CloudFamily.saveProfile(username: saved.username, phone: saved.phone);
        } catch (_) {}
      }

      // Sign in after registering, and keep the signed-in details up to date.
      if (widget.signUp || _isSignedInUser) {
        await Session.select(saved);
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        _showError('Could not save the account. $e');
      }
    }
  }

  /// Turning passkey on asks to set one only the first time; after that it is reused.
  Future<String?> _askPassword([String message = 'Enter your current password to connect this account to the cloud.']) async {
    final c = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => FancyAlert(
        icon: Icons.cloud_sync_rounded,
        title: const Text('Confirm your password'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(message),
            const SizedBox(height: 16),
            TextField(
              controller: c,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Password'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Connect'),
          ),
        ],
      ),
    );
    final text = c.text;
    c.dispose();
    return ok == true ? text : null;
  }

  Future<void> _connectCloud() async {
    final user = widget.user;
    if (user == null) return;
    final pwd = await _askPassword();
    if (pwd == null || pwd.isEmpty) return;
    final creds = await Db.instance.credentialsFor(user.username);
    if (creds == null || !Auth.verify(creds.salt, creds.passwordHash, pwd)) {
      _showError('That password is not right.');
      return;
    }
    try {
      User cloud;
      try {
        cloud = await CloudAuth.signUp(user.username, pwd);
      } on CloudAuthException catch (e) {
        if (!e.message.contains('taken')) rethrow;
        cloud = await CloudAuth.signIn(user.username, pwd);
      }
      await Db.instance.setFirebaseUid(user.id, cloud.uid);
      if (mounted) setState(() {});
    } on CloudAuthException catch (e) {
      _showError(e.message);
    } catch (e) {
      _showError('Could not connect. $e');
    }
  }

  Future<void> _deleteMyAccount() async {
    final user = widget.user;
    if (user == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => FancyAlert(
        icon: Icons.delete_forever_rounded,
        title: const Text('Delete my account?'),
        content: const Text(
            'Your login, Gmail link and phone number are removed, so the username and Gmail can be used again. '
            'Your past expenses stay in the reports as "Deleted member". This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final pwd = await _askPassword('Enter your password to delete this account.');
    if (pwd == null) return;

    setState(() => _saving = true);
    try {
      final creds = await Db.instance.credentialsFor(user.username);
      if (creds != null &&
          creds.passwordHash.isNotEmpty &&
          !Auth.verify(creds.salt, creds.passwordHash, pwd)) {
        throw CloudAuthException('That password is not right.');
      }
      await CloudAuth.deleteAccount(password: pwd, phone: user.phone);
      await Db.instance.anonymizeUser(user.id);
      if (await QuickLogin.enabledUserId() == user.id) {
        await QuickLogin.disable();
      }
      if (mounted) Navigator.pop(context, true);
      await Session.signOut();
    } on CloudAuthException catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        _showError(e.message);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        _showError('Could not delete the account. $e');
      }
    }
  }

  Future<void> _setPasswordForGoogle() async {
    final p = TextEditingController();
    final c = TextEditingController();
    String? err;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => FancyAlert(
          icon: Icons.lock_rounded,
          title: const Text('Set a password'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('You will sign in with your Gmail address and this password.'),
              const SizedBox(height: 14),
              TextField(
                controller: p,
                obscureText: true,
                decoration: const InputDecoration(labelText: 'New password'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: c,
                obscureText: true,
                decoration: const InputDecoration(labelText: 'Confirm password'),
              ),
              if (err != null)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Text(err!, style: const TextStyle(color: AppColors.red)),
                ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                if (p.text.length < 6) {
                  setD(() => err = 'Use at least 6 characters.');
                } else if (p.text != c.text) {
                  setD(() => err = 'Passwords do not match.');
                } else {
                  Navigator.pop(ctx, true);
                }
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    final pwd = p.text;
    p.dispose();
    c.dispose();
    if (ok != true) return;

    setState(() => _saving = true);
    try {
      await CloudAuth.setPassword(pwd);
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Password set. You can now sign in with your Gmail and password.')));
      }
    } on CloudAuthException catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        _showError(e.message);
      }
    }
  }

  Future<void> _linkGmail() async {
    try {
      await CloudAuth.linkGmail();
      if (mounted) setState(() {});
    } on CloudAuthException catch (e) {
      _showError(e.message);
    } catch (e) {
      _showError('Could not link Gmail. $e');
    }
  }

  Future<void> _togglePasskey(bool on) async {
    final user = widget.user;
    if (user == null) return;
    if (on && !_hasPasskey) {
      final saved = await Navigator.of(context).push<bool>(
        MaterialPageRoute(builder: (_) => PasskeyScreen(user: user, setup: true)),
      );
      if (saved != true) return;
      if (mounted) {
        setState(() {
          _hasPasskey = true;
          _passkeyOn = true;
        });
      }
      return;
    }
    await Db.instance.setPasskeyEnabled(user.id, on);
    if (mounted) setState(() => _passkeyOn = on);
  }

  Future<void> _toggleQuick(bool on) async {
    final user = widget.user;
    if (user == null) return;
    if (on) {
      if (!await QuickLogin.canUseBiometrics()) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text(
                  'Set up a fingerprint or face unlock in your phone settings first.')));
        }
        return;
      }
      final ok = await QuickLogin.authenticate('Confirm to turn on quick login');
      if (!ok) return;
      await QuickLogin.enable(user.id);
    } else {
      await QuickLogin.disable();
    }
    if (mounted) setState(() => _quickOn = on);
  }

  Future<void> _logOut() async {
    await Session.signOut();
    if (mounted) Navigator.of(context).popUntil((route) => route.isFirst);
  }

  String? _validatePassword(String? v) {
    final text = v ?? '';
    if (_isNew && text.isEmpty) return 'Please enter a password';
    if (text.isNotEmpty && text.length < 6) return 'Use at least 6 characters';
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final muted = dark ? const Color(0xFFB7B0CC) : AppColors.muted;
    final title = widget.signUp
        ? 'Register'
        : _isNew
            ? 'New account'
            : 'Edit account';

    return Scaffold(
      body: Form(
        key: _formKey,
        child: ListView(
          controller: _scroll,
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
                  Text(title,
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
                  if (_error != null)
                    Container(
                      margin: const EdgeInsets.only(bottom: 14),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.red.withAlpha(30),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.error_outline_rounded, color: AppColors.red),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(_error!,
                                style: const TextStyle(
                                    color: AppColors.red, fontWeight: FontWeight.w600)),
                          ),
                        ],
                      ),
                    ),
                  SoftCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text('Sign-in',
                            style: TextStyle(
                                fontWeight: FontWeight.w800, fontSize: 15, color: muted)),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _username,
                          autocorrect: false,
                          onChanged: (_) {
                            if (_usernameTaken) setState(() => _usernameTaken = false);
                          },
                          decoration: const InputDecoration(
                            labelText: 'Username *',
                            helperText: '3–20 letters, numbers, _ or .',
                            prefixIcon: Icon(Icons.alternate_email_rounded),
                          ),
                          validator: (v) {
                            final t = v?.trim() ?? '';
                            if (_usernameTaken) return 'This username is already taken';
                            if (t.isEmpty) return 'Please enter a username';
                            return RegExp(r'^[a-zA-Z0-9_.]{3,20}$').hasMatch(t)
                                ? null
                                : 'Use 3–20 letters, numbers, _ or .';
                          },
                        ),
                        const SizedBox(height: 14),
                        if (!_isNew && _isSignedInUser) ...[
                          TextFormField(
                            controller: _currentPassword,
                            obscureText: true,
                            decoration: const InputDecoration(
                              labelText: 'Current password (to change it)',
                              prefixIcon: Icon(Icons.lock_outline_rounded),
                            ),
                          ),
                          const SizedBox(height: 14),
                        ],
                        TextFormField(
                          controller: _password,
                          obscureText: _obscure,
                          decoration: InputDecoration(
                            labelText: _isNew ? 'Password *' : 'New password (optional)',
                            prefixIcon: const Icon(Icons.lock_rounded),
                            suffixIcon: IconButton(
                              tooltip: _obscure ? 'Show password' : 'Hide password',
                              icon: Icon(_obscure
                                  ? Icons.visibility_rounded
                                  : Icons.visibility_off_rounded),
                              onPressed: () => setState(() => _obscure = !_obscure),
                            ),
                          ),
                          validator: _validatePassword,
                        ),
                        const SizedBox(height: 14),
                        TextFormField(
                          controller: _confirm,
                          obscureText: _obscure,
                          decoration: const InputDecoration(
                            labelText: 'Confirm password',
                            prefixIcon: Icon(Icons.lock_outline_rounded),
                          ),
                          validator: (v) {
                            if (_password.text.isEmpty && (v ?? '').isEmpty) return null;
                            return v == _password.text ? null : 'Passwords do not match';
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
                        Row(
                          children: [
                            SizedBox(
                              width: 140,
                              child: DropdownButtonFormField<String>(
                                value: _dial,
                                isExpanded: true,
                                decoration: const InputDecoration(labelText: 'Code'),
                                items: [
                                  for (final c in kDialCodes)
                                    DropdownMenuItem(
                                      value: c.code,
                                      child: Text('${c.code} ${c.country}',
                                          overflow: TextOverflow.ellipsis),
                                    ),
                                ],
                                onChanged: (v) => setState(() => _dial = v ?? _dial),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: TextFormField(
                                controller: _phone,
                                keyboardType: TextInputType.phone,
                                decoration: const InputDecoration(labelText: 'Phone number'),
                              ),
                            ),
                          ],
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
                  if (_isSignedInUser) ...[
                    const SizedBox(height: 24),
                    if (CloudAuth.currentUser != null &&
                        CloudAuth.linkedGmail() != null &&
                        !CloudAuth.hasPassword()) ...[
                      SoftCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Set a password',
                                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                            const SizedBox(height: 6),
                            const Text(
                                'Sign in with your Gmail and a password, and change the password later.'),
                            const SizedBox(height: 12),
                            OutlinedButton(
                              onPressed: _setPasswordForGoogle,
                              child: const Text('Set password'),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),
                    ],
                    if (CloudAuth.linkedGmail() == null) ...[
                      SoftCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                                CloudAuth.currentUser == null
                                    ? 'Connect to the cloud'
                                    : 'Add your Gmail',
                                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                            const SizedBox(height: 6),
                            Text(CloudAuth.currentUser == null
                                ? 'Sync your data across phones and family members.'
                                : 'Sign in with Google, and reset your password if you forget it.'),
                            const SizedBox(height: 12),
                            OutlinedButton(
                              onPressed: CloudAuth.currentUser == null ? _connectCloud : _linkGmail,
                              child: Text(CloudAuth.currentUser == null ? 'Connect' : 'Link Gmail'),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),
                    ],
                    SoftCard(
                      child: SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        secondary: const Icon(Icons.fingerprint_rounded,
                            color: AppColors.primary, size: 30),
                        title: const Text('Quick login',
                            style: TextStyle(fontWeight: FontWeight.w800)),
                        subtitle: const Text(
                            'Sign in with your fingerprint or face on this phone'),
                        value: _quickOn,
                        onChanged: _toggleQuick,
                      ),
                    ),
                    const SizedBox(height: 14),
                    SoftCard(
                      child: SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        secondary: const Icon(Icons.pin_rounded,
                            color: AppColors.primary, size: 30),
                        title: const Text('Passkey',
                            style: TextStyle(fontWeight: FontWeight.w800)),
                        subtitle: Text(_hasPasskey
                            ? 'Your 6-digit passkey is set'
                            : 'Sign in with a 6-digit passkey'),
                        value: _passkeyOn,
                        onChanged: _togglePasskey,
                      ),
                    ),
                    const SizedBox(height: 14),
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.red,
                        side: const BorderSide(color: AppColors.red),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      onPressed: _logOut,
                      icon: const Icon(Icons.logout_rounded),
                      label: const Text('Log out'),
                    ),
                    const SizedBox(height: 14),
                    Center(
                      child: Text('Build $kBuildId',
                          style: const TextStyle(color: AppColors.muted, fontSize: 12)),
                    ),
                  ],
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
            label: Text(widget.signUp
                ? 'Register & sign in'
                : _isNew
                    ? 'Create account'
                    : 'Save changes'),
          ),
        ),
      ),
    );
  }
}
