import 'package:flutter/material.dart';

import '../theme.dart';

/// Row of dots showing how many digits have been typed.
class PinDots extends StatelessWidget {
  final int filled;
  final int length;

  const PinDots({super.key, required this.filled, this.length = 6});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var i = 0; i < length; i++)
          AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            margin: const EdgeInsets.symmetric(horizontal: 9),
            width: 16,
            height: 16,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: i < filled ? AppColors.primary : AppColors.muted.withAlpha(60),
            ),
          ),
      ],
    );
  }
}

/// Numeric keypad: digits 0–9 and a backspace key.
/// [bottomLeft] fills the empty bottom-left slot, for example a fingerprint button.
class PinKeypad extends StatelessWidget {
  final ValueChanged<String> onDigit;
  final VoidCallback onBackspace;
  final Color textColor;
  final Widget? bottomLeft;

  const PinKeypad({
    super.key,
    required this.onDigit,
    required this.onBackspace,
    required this.textColor,
    this.bottomLeft,
  });

  @override
  Widget build(BuildContext context) {
    const rows = [
      ['1', '2', '3'],
      ['4', '5', '6'],
      ['7', '8', '9'],
      ['', '0', 'back'],
    ];
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var r = 0; r < rows.length; r++)
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              for (final key in rows[r])
                if (key.isEmpty)
                  SizedBox(width: 88, height: 76, child: r == 3 ? bottomLeft : null)
                else
                  _key(key),
            ],
          ),
      ],
    );
  }

  Widget _key(String key) {
    final isBack = key == 'back';
    return InkWell(
      customBorder: const CircleBorder(),
      onTap: () => isBack ? onBackspace() : onDigit(key),
      child: SizedBox(
        width: 88,
        height: 76,
        child: Center(
          child: isBack
              ? Icon(Icons.backspace_outlined, color: textColor, size: 28)
              : Text(key,
                  style: TextStyle(
                      color: textColor, fontSize: 30, fontWeight: FontWeight.w500)),
        ),
      ),
    );
  }
}
