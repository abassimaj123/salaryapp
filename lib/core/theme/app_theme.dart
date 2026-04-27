import 'package:flutter/material.dart';

class AppTheme {
  static const primary    = Color(0xFFE65100);
  static const background = Color(0xFFF8FAFC);
  static const cardWhite  = Colors.white;
  static const success    = Color(0xFF34C759);
  static const warning    = Color(0xFFFFA500);
  static const labelGray  = Color(0xFF64748B);
  static const divider    = Color(0xFFE2E8F0);

  static ThemeData get theme => ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: primary),
        scaffoldBackgroundColor: background,
        cardTheme: CardThemeData(
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          color: cardWhite,
          surfaceTintColor: Colors.transparent,
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: primary,
          foregroundColor: Colors.white,
          elevation: 0,
          centerTitle: false,
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: const Color(0xFFF1F5F9),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: primary, width: 2),
          ),
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: primary,
            foregroundColor: Colors.white,
            minimumSize: const Size(double.infinity, 52),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            elevation: 0,
          ),
        ),
        textTheme: const TextTheme(
          titleLarge:  TextStyle(fontSize: 26, fontWeight: FontWeight.bold),
          titleMedium: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
          bodyLarge:   TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
          bodyMedium:  TextStyle(fontSize: 14, color: labelGray),
        ),
        navigationBarTheme: NavigationBarThemeData(
          backgroundColor: cardWhite,
          indicatorColor: primary.withValues(alpha: 0.12),
          labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        ),
      );

  static LinearGradient get primaryGradient => LinearGradient(
    colors: [primary, Color.lerp(primary, Colors.black, 0.15)!],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
}
