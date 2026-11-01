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
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: dark ? const Color(0xFF121019) : AppColors.background,
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: dark ? const Color(0xFF1C1828) : Colors.white,
      indicatorColor: AppColors.soft,
      labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: dark ? const Color(0xFF1C1828) : Colors.white,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide.none,
      ),
    ),
  );
}
