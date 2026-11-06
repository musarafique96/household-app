import 'package:flutter/material.dart';

class AppColors {
  static const primary = Color(0xFF6A3DE8);
  static const deep = Color(0xFF3E2490);
  static const soft = Color(0xFFEDE7FB);
  static const background = Color(0xFFF5F2FB);
  static const green = Color(0xFF22A559);
  static const red = Color(0xFFE5484D);
  static const amber = Color(0xFFF5A524);
  static const pink = Color(0xFFE94E8B);
  static const blue = Color(0xFF3B82F6);
  static const ink = Color(0xFF1E1B2E);
  static const muted = Color(0xFF7A7592);
}

ThemeData buildTheme({required bool dark}) {
  final scheme = ColorScheme.fromSeed(
    seedColor: AppColors.primary,
    brightness: dark ? Brightness.dark : Brightness.light,
  );

  // One set of surface colours used by every popup, dialog and menu.
  final surface = dark ? const Color(0xFF1F1B2E) : Colors.white;
  final raised = dark ? const Color(0xFF2A2640) : Colors.white;
  final fill = dark ? const Color(0xFF171425) : const Color(0xFFF1EEF9);
  final text = dark ? const Color(0xFFF4F1FB) : AppColors.ink;
  final muted = dark ? const Color(0xFFB7B0CC) : AppColors.muted;
  const radius = 16.0;

  OutlineInputBorder border(Color color, [double width = 0]) => OutlineInputBorder(
        borderRadius: BorderRadius.circular(radius),
        borderSide: BorderSide(color: color, width: width),
      );

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: dark ? const Color(0xFF121019) : AppColors.background,
    canvasColor: raised,
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: dark ? const Color(0xFF1C1828) : Colors.white,
      surfaceTintColor: Colors.transparent,
      height: 72,
      indicatorColor: AppColors.primary,
      indicatorShape: const StadiumBorder(),
      labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      // Selected tab: purple pill with a white icon and bold label.
      iconTheme: WidgetStateProperty.resolveWith((states) => IconThemeData(
            size: 24,
            color: states.contains(WidgetState.selected) ? Colors.white : muted,
          )),
      labelTextStyle: WidgetStateProperty.resolveWith((states) => TextStyle(
            fontSize: 12,
            fontWeight: states.contains(WidgetState.selected) ? FontWeight.w800 : FontWeight.w600,
            color: states.contains(WidgetState.selected) ? text : muted,
          )),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: surface,
      surfaceTintColor: Colors.transparent,
      elevation: 12,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      titleTextStyle: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: text),
      contentTextStyle: TextStyle(fontSize: 15, color: muted),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: surface,
      surfaceTintColor: Colors.transparent,
      showDragHandle: true,
      dragHandleColor: muted.withAlpha(110),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: raised,
      surfaceTintColor: Colors.transparent,
      elevation: 8,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      textStyle: TextStyle(color: text, fontWeight: FontWeight.w600),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        backgroundColor: WidgetStateProperty.resolveWith((states) =>
            states.contains(WidgetState.selected) ? AppColors.primary : fill),
        foregroundColor: WidgetStateProperty.resolveWith((states) =>
            states.contains(WidgetState.selected) ? Colors.white : text),
        side: const WidgetStatePropertyAll(BorderSide(color: Colors.transparent)),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        disabledBackgroundColor: AppColors.primary.withAlpha(90),
        disabledForegroundColor: Colors.white70,
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radius)),
        textStyle: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: dark ? const Color(0xFFCDBFFF) : AppColors.primary,
        textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: dark ? raised : AppColors.ink,
      contentTextStyle: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: fill,
      labelStyle: TextStyle(color: muted),
      floatingLabelStyle: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.w700),
      hintStyle: TextStyle(color: muted),
      border: border(Colors.transparent),
      enabledBorder: border(Colors.transparent),
      focusedBorder: border(AppColors.primary, 1.6),
    ),
  );
}
