import 'package:flutter/material.dart';

import '../auth.dart';
import '../data/db.dart';
import '../data/models.dart';
import '../quick_login.dart';
import '../session.dart';
import '../theme.dart';
import '../widgets/fancy.dart';
import 'account_form_screen.dart';

/// Sign-in page. Shown whenever nobody is signed in.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _username = TextEditingController();
  final _password = TextEditingController();
  bool _obscure = true;
  bool _busy = false;
  String? _error;
  AppUser? _quickUser;

  @override
  void initState() {
    super.initState();
    _loadQuickUser();
  }

  Future<void> _loadQuickUser() async {
    final id = await QuickLogin.enabledUserId();
    if (id == null) return;
    final users = await Db.instance.activeUsers();
    final match = users.where((u) => u.id == id).toList();
    if (match.isNotEmpty && mounted) setState(() => _quickUser = match.first);
  }

  /// Signs in with fingerprint or face for the account that has quick login.
  Future<void> _quickSignIn() async {
    final user = _quickUser;
    if (user == null) return;
    final ok = await QuickLogin.authenticate('Sign in to Household as ${user.name}');
    if (!mounted) return;
    if (!ok) {
      setState(() => _error = 'Fingerprint not recognised. You can use your password.');
      return;
    }
    await Session.select(user);
  }

  /// Runs after a successful password sign-in. Offers quick login once per phone.
  Future<void> _finishSignIn(AppUser user) async {
    if (!await QuickLogin.wasPrompted() && await QuickLogin.canUseBiometrics()) {
      await QuickLogin.markPrompted();
      if (!mounted) return;
      final wantsIt = await showDialog<bool>(
        context: context,
        builder: (ctx) => FancyAlert(
          icon: Icons.fingerprint_rounded,
          title: const Text('Enable quick login?'),
          content: const Text(
            'Sign in next time with your fingerprint or face instead of typing your password.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Not now'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Enable'),
            ),
          ],
        ),
      );
      if (wantsIt == true && await QuickLogin.authenticate('Confirm to enable quick login')) {
        await QuickLogin.enable(user.id);
      }
    }
    await Session.select(user);
  }

  @override
  void dispose() {
    _username.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _signIn() async {
    final username = _username.text.trim();
    final password = _password.text;
    if (username.isEmpty || password.isEmpty) {
      setState(() => _error = 'Enter your username and password.');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });

    final c = await Db.instance.credentialsFor(username);
    if (!mounted) return;

    if (c == null) {
      setState(() {
        _busy = false;
        _error = 'No account has that username.';
      });
      return;
    }

    // Accounts created before sign-in existed have no password yet.
    if (c.passwordHash.isEmpty) {
      setState(() => _busy = false);
      await _setPasswordForExistingAccount(c.user);
      return;
    }

    if (!Auth.verify(c.salt, c.passwordHash, password)) {
      setState(() {
        _busy = false;
        _error = 'That password is not right.';
      });
      return;
    }

    await _finishSignIn(c.user);
  }

  Future<void> _setPasswordForExistingAccount(AppUser user) async {
    final pwd = TextEditingController();
    final confirm = TextEditingController();
    String? err;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialog) => FancyAlert(
          icon: Icons.lock_reset_rounded,
          title: const Text('Set a password'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'This account was created before sign-in existed. Set a password for ${user.name} to continue.',
              ),
              const SizedBox(height: 16),
              TextField(
                controller: pwd,
                obscureText: true,
                decoration: const InputDecoration(labelText: 'New password'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: confirm,
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
                if (pwd.text.length < 6) {
                  setDialog(() => err = 'Use at least 6 characters.');
                } else if (pwd.text != confirm.text) {
                  setDialog(() => err = 'Passwords do not match.');
                } else {
                  Navigator.pop(ctx, true);
                }
              },
              child: const Text('Save & sign in'),
            ),
          ],
        ),
      ),
    );

    if (ok == true) {
      final saved = await Db.instance.saveUser(user, password: pwd.text);
      await _finishSignIn(saved);
    }
    pwd.dispose();
    confirm.dispose();
  }

  Future<void> _register() async {
    await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const AccountFormScreen(signUp: true)),
    );
  }

  InputDecoration _field(String label, IconData icon, {Widget? suffix}) {
    // A plain hint that disappears when typing, so nothing is clipped at the top edge.
    return InputDecoration(
      hintText: label,
      hintStyle: const TextStyle(color: AppColors.muted, fontSize: 16),
      floatingLabelBehavior: FloatingLabelBehavior.never,
      contentPadding: const EdgeInsets.symmetric(vertical: 18, horizontal: 16),
      prefixIcon: Icon(icon, color: AppColors.primary),
      suffixIcon: suffix,
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: Colors.white, width: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [AppColors.primary, AppColors.deep, Color(0xFF17112E)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            stops: [0, 0.55, 1],
          ),
        ),
        child: Stack(
          children: [
            Positioned(
              top: -80,
              right: -60,
              child: _glow(220, AppColors.pink.withAlpha(90)),
            ),
            Positioned(
              bottom: -90,
              left: -70,
              child: _glow(260, AppColors.blue.withAlpha(70)),
            ),
            SafeArea(
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 420),
                    child: Column(
                      children: [
                        Container(
                          width: 88,
                          height: 88,
                          decoration: BoxDecoration(
                            color: Colors.white.withAlpha(40),
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white.withAlpha(90), width: 1.5),
                          ),
                          child: const Icon(Icons.home_rounded, color: Colors.white, size: 44),
                        ),
                        const SizedBox(height: 18),
                        const Text(
                          'Household',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 32,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.3,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Sign in to manage your home budget',
                          style: TextStyle(color: Colors.white.withAlpha(200), fontSize: 15),
                        ),
                        const SizedBox(height: 32),
                        Container(
                          padding: const EdgeInsets.all(22),
                          decoration: BoxDecoration(
                            color: Colors.white.withAlpha(26),
                            borderRadius: BorderRadius.circular(28),
                            border: Border.all(color: Colors.white.withAlpha(60)),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withAlpha(60),
                                blurRadius: 30,
                                offset: const Offset(0, 14),
                              ),
                            ],
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              if (_quickUser != null) ...[
                                _QuickButton(name: _quickUser!.name, onTap: _quickSignIn),
                                const SizedBox(height: 18),
                                Row(
                                  children: [
                                    Expanded(child: Divider(color: Colors.white.withAlpha(90))),
                                    Padding(
                                      padding: const EdgeInsets.symmetric(horizontal: 10),
                                      child: Text('or use password',
                                          style: TextStyle(
                                              color: Colors.white.withAlpha(200), fontSize: 13)),
                                    ),
                                    Expanded(child: Divider(color: Colors.white.withAlpha(90))),
                                  ],
                                ),
                                const SizedBox(height: 18),
                              ],
                              TextField(
                                controller: _username,
                                autocorrect: false,
                                textInputAction: TextInputAction.next,
                                style: const TextStyle(color: AppColors.ink),
                                decoration: _field('Username', Icons.alternate_email_rounded),
                              ),
                              const SizedBox(height: 14),
                              TextField(
                                controller: _password,
                                obscureText: _obscure,
                                onSubmitted: (_) => _signIn(),
                                style: const TextStyle(color: AppColors.ink),
                                decoration: _field(
                                  'Password',
                                  Icons.lock_rounded,
                                  suffix: IconButton(
                                    tooltip: _obscure ? 'Show password' : 'Hide password',
                                    icon: Icon(
                                      _obscure
                                          ? Icons.visibility_rounded
                                          : Icons.visibility_off_rounded,
                                      color: AppColors.muted,
                                    ),
                                    onPressed: () => setState(() => _obscure = !_obscure),
                                  ),
                                ),
                              ),
                              if (_error != null) ...[
                                const SizedBox(height: 14),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 12, vertical: 10),
                                  decoration: BoxDecoration(
                                    color: AppColors.red.withAlpha(60),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Row(
                                    children: [
                                      const Icon(Icons.error_outline_rounded,
                                          color: Colors.white, size: 20),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(_error!,
                                            style: const TextStyle(
                                                color: Colors.white,
                                                fontWeight: FontWeight.w600)),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                              const SizedBox(height: 22),
                              _SignInButton(busy: _busy, onTap: _signIn),
                            ],
                          ),
                        ),
                        const SizedBox(height: 22),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text("New here? ",
                                style: TextStyle(color: Colors.white.withAlpha(210))),
                            TextButton(
                              onPressed: _register,
                              style: TextButton.styleFrom(foregroundColor: Colors.white),
                              child: const Text(
                                'Register',
                                style: TextStyle(
                                    fontWeight: FontWeight.w800,
                                    decoration: TextDecoration.underline),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _glow(double size, Color color) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(colors: [color, color.withAlpha(0)]),
        ),
      ),
    );
  }
}

/// Gradient pill button with a loading state.
class _SignInButton extends StatelessWidget {
  final bool busy;
  final VoidCallback onTap;

  const _SignInButton({required this.busy, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: busy ? null : onTap,
        child: Ink(
          height: 56,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [AppColors.pink, AppColors.primary],
            ),
            borderRadius: BorderRadius.circular(18),
            boxShadow: [
              BoxShadow(
                color: AppColors.pink.withAlpha(90),
                blurRadius: 18,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Center(
            child: busy
                ? const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
                  )
                : const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Sign in',
                        style: TextStyle(
                            color: Colors.white, fontSize: 17, fontWeight: FontWeight.w800),
                      ),
                      SizedBox(width: 8),
                      Icon(Icons.arrow_forward_rounded, color: Colors.white),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}

/// Big round fingerprint button for quick login.
class _QuickButton extends StatelessWidget {
  final String name;
  final VoidCallback onTap;

  const _QuickButton({required this.name, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Material(
          color: Colors.transparent,
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: Container(
              width: 76,
              height: 76,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [AppColors.pink, AppColors.primary],
                ),
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: AppColors.pink.withAlpha(90),
                    blurRadius: 18,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: const Icon(Icons.fingerprint_rounded, color: Colors.white, size: 42),
            ),
          ),
        ),
        const SizedBox(height: 10),
        Text(
          'Sign in as $name',
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
        ),
      ],
    );
  }
}
