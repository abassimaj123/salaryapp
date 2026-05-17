import 'package:flutter/material.dart';
import 'package:calcwise_core/calcwise_core.dart';
import 'app_theme_base.dart';

/// Canada Theme - Professional Burnt Orange with Red Accents
class AppThemeCA {
  static const Color primaryLight =
      Color(0xFFE67E22); // Burnt Orange (improved contrast)
  static const Color primaryDark = Color(0xFFC86D1F); // Deep Burnt Orange
  static const Color secondaryLight =
      Color(0xFFEF4444); // Red for icons/accents
  static const Color secondaryDark = Color(0xFFDC2626); // Dark Red
  static const Color background = Color(0xFFFFFBF7); // Warm white
  static const Color backgroundDark = Color(0xFF2D1810); // Dark warm brown
  static const Color cardWhite = Colors.white;
  static const Color cardDark = Color(0xFF3F2415);

  static ThemeData get lightTheme => ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: primaryLight,
          brightness: Brightness.light,
        ).copyWith(primary: primaryLight, secondary: secondaryLight),
        scaffoldBackgroundColor: background,
        cardTheme: AppThemeBase.cardTheme(backgroundColor: cardWhite),
        appBarTheme: AppThemeBase.appBarTheme(primaryColor: primaryLight),
        inputDecorationTheme:
            AppThemeBase.inputDecorationTheme(primaryColor: primaryLight),
        extensions: [
          CalcwiseTheme.light(
              primary: Color(0xFFE67E22),
              accent: Color(0xFFEF4444),
              primaryDeep: Color(0xFFC86D1F))
        ],
        fontFamily: 'Inter',
      );

  static ThemeData get darkTheme => ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: primaryLight,
          brightness: Brightness.dark,
        ).copyWith(primary: primaryLight, secondary: secondaryDark),
        scaffoldBackgroundColor: backgroundDark,
        cardTheme: AppThemeBase.cardTheme(backgroundColor: cardDark),
        appBarTheme: AppBarTheme(
          backgroundColor: primaryDark,
          foregroundColor: Colors.white,
          elevation: 0,
        ),
        extensions: [
          CalcwiseTheme.dark(
              primary: Color(0xFFE67E22),
              accent: Color(0xFFEF4444),
              primaryDeep: Color(0xFFC86D1F))
        ],
        fontFamily: 'Inter',
      );
}
