import 'package:flutter/material.dart';
import 'package:calcwise_core/calcwise_core.dart';
import 'app_theme_base.dart';

/// USA Theme - Confident Red
class AppThemeUS {
  static const Color primaryLight = Color(0xFFDC2626); // Confident Red
  static const Color primaryDark = Color(0xFFB91C1C);
  static const Color secondaryLight = Color(0xFF1F2937); // Dark Gray
  static const Color secondaryDark = Color(0xFFF3F4F6);
  static const Color background = Color(0xFFFFFFFF);
  static const Color backgroundDark = Color(0xFF111827);
  static const Color cardWhite = Colors.white;
  static const Color cardDark = Color(0xFF1F2937);

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
              primary: Color(0xFFDC2626),
              accent: Color(0xFFF59E0B),
              primaryDeep: Color(0xFFB91C1C))
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
              primary: Color(0xFFDC2626),
              accent: Color(0xFFF59E0B),
              primaryDeep: Color(0xFFB91C1C))
        ],
        fontFamily: 'Inter',
      );
}
