import 'package:flutter/material.dart';

/// Shared theme utilities for all flavors
class AppThemeBase {
  // Common palettes
  static const success = Color(0xFF34C759);
  static const error = Color(0xFFFF3B30);
  static const warning = Color(0xFFFFA500);

  // Common spacing & typography
  static const borderRadiusSm = 8.0;
  static const borderRadiusMd = 12.0;
  static const borderRadiusLg = 16.0;

  static const double baseFont = 16.0;

  // Common card theme
  static CardThemeData cardTheme({required Color backgroundColor}) =>
      CardThemeData(
        elevation: 0,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(borderRadiusLg)),
        color: backgroundColor,
        surfaceTintColor: Colors.transparent,
      );

  // Common app bar theme
  static AppBarTheme appBarTheme({required Color primaryColor}) => AppBarTheme(
        backgroundColor: primaryColor,
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: false,
      );

  // Common input decoration
  static InputDecorationTheme inputDecorationTheme(
          {required Color primaryColor}) =>
      InputDecorationTheme(
        filled: true,
        fillColor: const Color(0xFFF1F5F9),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(borderRadiusMd),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(borderRadiusMd),
          borderSide: BorderSide(color: primaryColor, width: 2),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      );
}
