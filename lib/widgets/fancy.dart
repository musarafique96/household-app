import 'package:flutter/material.dart';

import '../theme.dart';

/// A dialog with a gradient header, an icon and rounded corners.
/// Takes the same title, content and actions as [AlertDialog].
class FancyAlert extends StatelessWidget {
  final Widget? title;
  final Widget? content;
  final List<Widget>? actions;
  final IconData icon;
  final Color color;

  const FancyAlert({
    super.key,
    this.title,
    this.content,
    this.actions,
    this.icon = Icons.auto_awesome_rounded,
    this.color = AppColors.primary,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final surface = theme.dialogTheme.backgroundColor ?? theme.colorScheme.surface;
    final deep = Color.lerp(color, Colors.black, 0.28)!;

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      backgroundColor: surface,
      surfaceTintColor: Colors.transparent,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(20, 22, 20, 22),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [color, deep],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: Colors.white.withAlpha(46),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, color: Colors.white, size: 24),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: DefaultTextStyle(
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 21,
                      fontWeight: FontWeight.w800,
                    ),
                    child: title ?? const SizedBox.shrink(),
                  ),
                ),
              ],
            ),
          ),
          if (content != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
              child: content,
            ),
          if (actions != null && actions!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 16, 12, 12),
              child: Wrap(
                alignment: WrapAlignment.end,
                spacing: 8,
                runSpacing: 8,
                children: actions!,
              ),
            ),
        ],
      ),
    );
  }
}
