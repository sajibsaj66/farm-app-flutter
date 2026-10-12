import 'package:flutter/material.dart';

/// DeshIT-BD brand palette shared by every view.
///
/// Navy for the main interface, orange for primary actions and highlights,
/// white and light grey for content, green for good results, and red or
/// amber for warnings.
class AppColors {
  AppColors._();

  // Brand
  static const navy = Color(0xFF0B2545);
  static const navyLight = Color(0xFF1D4E89);
  static const orange = Color(0xFFF57C00);
  static const orangeSoft = Color(0xFFFFEEDD);

  /// The main brand colour (navy). Kept as `brand` for existing views.
  static const brand = navy;
  static const brandSoft = Color(0xFFE6EDF7);
  static const ink = Color(0xFF14213D);

  // Content
  static const canvas = Color(0xFFF3F5F9);
  static const inputBorder = Color(0xFFDCE2EC);
  static const muted = Color(0xFF5B6475);

  // Status
  static const positive = Color(0xFF2E7D32);
  static const positiveSoft = Color(0xFFE5F4E7);
  static const warning = Color(0xFFB26A00);
  static const warningSoft = Color(0xFFFFF3DC);
  static const danger = Color(0xFFC62828);
  static const dangerSoft = Color(0xFFFDE7E4);

  /// Header cards (dashboards, profiles).
  static const heroGradient = LinearGradient(colors: [navy, navyLight], begin: Alignment.topLeft, end: Alignment.bottomRight);
}
