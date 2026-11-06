import 'package:flutter/material.dart';

import '../data/db.dart';
import '../data/models.dart';
import '../theme.dart';

/// 6-digit passkey pad.
/// [setup] true: choose a new passkey, entered twice to confirm.
/// [setup] false: enter the saved passkey to sign in.
/// Pops with `true` when done.
class PasskeyScreen extends StatefulWidget {
  final AppUser user;
  final bool setup;

  const PasskeyScreen({super.key, required this.user, required this.setup});

  @override
  State<PasskeyScreen> createState() => _PasskeyScreenState();
}

class _PasskeyScreenState extends State<PasskeyScreen> {
  static const _length = 6;

  String _entry = '';
  String? _first;
  String? _message;
  bool _busy = false;

  bool get _confirming => widget.setup && _first != null;

  String get _title {
    if (!widget.setup) return 'Enter passkey';
    return _confirming ? 'Confirm passkey' : 'Set passkey';
  }

  String get _subtitle {
    if (!widget.setup) return 'Enter your 6-digit passkey';
    return _confirming
        ? 'Enter the same 6 digits again'
        : 'Enter a new 6-digit passkey';
  }

  void _press(String digit) {
    if (_busy || _entry.length >= _length) return;
    setState(() {
      _entry += digit;
      _message = null;
    });
    if (_entry.length == _length) _complete();
  }

  void _backspace() {
    if (_busy || _entry.isEmpty) return;
    setState(() => _entry = _entry.substring(0, _entry.length - 1));
  }

  void _fail(String message) {
    setState(() {
      _entry = '';
      _message = message;
    });
  }

  Future<void> _complete() async {
    final pin = _entry;

    if (!widget.setup) {
      final ok = await Db.instance.checkPasskey(widget.user.id, pin);
      if (!mounted) return;
      if (ok) {
        Navigator.pop(context, true);
      } else {
        _fail('Wrong passkey. Try again.');
      }
      return;
    }

    if (_first == null) {
      setState(() {
        _first = pin;
        _entry = '';
      });
      return;
    }

    if (pin != _first) {
      setState(() => _first = null);
      _fail("Passkeys don't match. Start again.");
      return;
    }

    setState(() => _busy = true);
    await Db.instance.setPasskey(widget.user.id, pin);
    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final text = dark ? const Color(0xFFF4F1FB) : AppColors.ink;
    final muted = dark ? const Color(0xFFB7B0CC) : AppColors.muted;

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: IconButton(
                tooltip: 'Back',
                onPressed: () => Navigator.pop(context, false),
                icon: Icon(Icons.arrow_back_rounded, color: text, size: 28),
              ),
            ),
            const Spacer(),
            // Dots show how many digits have been entered.
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var i = 0; i < _length; i++)
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    margin: const EdgeInsets.symmetric(horizontal: 9),
                    width: 16,
                    height: 16,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: i < _entry.length
                          ? AppColors.primary
                          : AppColors.muted.withAlpha(60),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 36),
            Text(_title,
                style: TextStyle(
                    color: text, fontSize: 26, fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            Text(_subtitle, style: TextStyle(color: muted, fontSize: 15)),
            const SizedBox(height: 14),
            SizedBox(
              height: 22,
              child: Text(_message ?? '',
                  style: const TextStyle(
                      color: AppColors.red, fontWeight: FontWeight.w600)),
            ),
            const Spacer(),
            _keypad(text),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _keypad(Color text) {
    const rows = [
      ['1', '2', '3'],
      ['4', '5', '6'],
      ['7', '8', '9'],
      ['', '0', 'back'],
    ];
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final row in rows)
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              for (final key in row) _key(key, text),
            ],
          ),
      ],
    );
  }

  Widget _key(String key, Color text) {
    if (key.isEmpty) return const SizedBox(width: 88, height: 76);
    final isBack = key == 'back';
    return InkWell(
      customBorder: const CircleBorder(),
      onTap: () => isBack ? _backspace() : _press(key),
      child: SizedBox(
        width: 88,
        height: 76,
        child: Center(
          child: isBack
              ? Icon(Icons.backspace_outlined, color: text, size: 28)
              : Text(key,
                  style: TextStyle(
                      color: text, fontSize: 30, fontWeight: FontWeight.w500)),
        ),
      ),
    );
  }
}
