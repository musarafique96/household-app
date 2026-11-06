import 'package:flutter/material.dart';

import '../data/models.dart';
import '../quick_login.dart';
import '../theme.dart';

/// Shown once after the first sign-in on a phone that supports fingerprint or face unlock.
/// Pops with `true` if biometrics were turned on.
class BiometricsIntroScreen extends StatelessWidget {
  final AppUser user;

  const BiometricsIntroScreen({super.key, required this.user});

  Future<void> _enable(BuildContext context) async {
    final ok = await QuickLogin.authenticate('Confirm to enable biometrics');
    if (!context.mounted) return;
    if (ok) {
      await QuickLogin.enable(user.id);
      if (context.mounted) Navigator.pop(context, true);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Fingerprint not recognised. You can turn it on later in your profile.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final ink = dark ? Colors.white : AppColors.ink;
    final muted = dark ? const Color(0xFFB7B0CC) : AppColors.muted;

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: Center(
                child: Container(
                  width: 200,
                  height: 200,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      colors: [AppColors.soft, AppColors.primary.withAlpha(60)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                  ),
                  child: const Icon(Icons.fingerprint_rounded,
                      size: 110, color: AppColors.primary),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 28),
              child: Column(
                children: [
                  Text('Biometrics',
                      style: TextStyle(
                          color: ink, fontSize: 30, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 14),
                  Text(
                    'Enable fingerprint or face unlock for a more secure, fast and '
                    'convenient sign-in. You can also opt out at any time.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: muted, fontSize: 16, height: 1.5),
                  ),
                ],
              ),
            ),
            const Spacer(),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
              child: Column(
                children: [
                  SizedBox(
                    width: double.infinity,
                    height: 58,
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: ink,
                        side: BorderSide(color: ink, width: 2),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(18)),
                      ),
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('Skip for now',
                          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                    ),
                  ),
                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    height: 58,
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: dark ? Colors.white : AppColors.ink,
                        foregroundColor: dark ? AppColors.ink : Colors.white,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(18)),
                      ),
                      onPressed: () => _enable(context),
                      child: const Text('Enable Biometrics',
                          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
