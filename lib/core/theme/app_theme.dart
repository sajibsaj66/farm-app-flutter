import 'package:flutter/material.dart';

import 'app_colors.dart';

class AppTheme {
  AppTheme._();

  static ThemeData get light {
    final inputBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: AppColors.inputBorder),
    );
    final scheme = ColorScheme.fromSeed(seedColor: AppColors.navy).copyWith(
      primary: AppColors.navy,
      onPrimary: Colors.white,
      secondary: AppColors.orange,
      onSecondary: Colors.white,
      tertiary: AppColors.positive,
      error: AppColors.danger,
      surface: Colors.white,
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: AppColors.canvas,
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.navy,
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: false,
        iconTheme: IconThemeData(color: Colors.white),
        actionsIconTheme: IconThemeData(color: Colors.white),
      ),
      // Orange for primary actions (Save, Add new, Sign in…).
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(backgroundColor: AppColors.orange, foregroundColor: Colors.white, disabledBackgroundColor: const Color(0xFFF2C9A1)),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(backgroundColor: AppColors.orange, foregroundColor: Colors.white),
      outlinedButtonTheme: OutlinedButtonThemeData(style: OutlinedButton.styleFrom(foregroundColor: AppColors.navy, side: const BorderSide(color: AppColors.inputBorder))),
      textButtonTheme: TextButtonThemeData(style: TextButton.styleFrom(foregroundColor: AppColors.navyLight)),
      cardTheme: const CardThemeData(color: Colors.white, surfaceTintColor: Colors.white),
      chipTheme: const ChipThemeData(selectedColor: AppColors.orangeSoft, checkmarkColor: AppColors.orange),
      navigationBarTheme: const NavigationBarThemeData(backgroundColor: Colors.white, indicatorColor: AppColors.orangeSoft),
      navigationRailTheme: const NavigationRailThemeData(
        backgroundColor: Colors.white,
        indicatorColor: AppColors.orangeSoft,
        selectedIconTheme: IconThemeData(color: AppColors.orange),
        selectedLabelTextStyle: TextStyle(color: AppColors.navy, fontWeight: FontWeight.w700, fontSize: 12),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        border: inputBorder,
        enabledBorder: inputBorder,
        focusedBorder: inputBorder.copyWith(borderSide: const BorderSide(color: AppColors.navyLight, width: 1.6)),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(color: AppColors.orange),
    );
  }
}
