import 'package:flutter/material.dart';
import 'package:calcwise_core/calcwise_core.dart';
import 'app_theme_base.dart';

/// UK Theme - Premium Black with Gold accent
class AppThemeUK {
  static const Color primaryLight   = Color(0xFF1F2937); // Premium Black
  static const Color primaryDark    = Color(0xFF111827);
  static const Color accentLight    = Color(0xFFD4AF37); // Gold
  static const Color accentDark     = Color(0xFFD4AF37);
  static const Color background     = Color(0xFFF3F4F6);
  static const Color backgroundDark = Color(0xFF0F172A);
  static const Color cardWhite      = Colors.white;
  static const Color cardDark       = Color(0xFF1F2937);
  
  static ThemeData get lightTheme => ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: primaryLight,
      brightness: Brightness.light,
    ).copyWith(primary: primaryLight, secondary: accentLight),
    scaffoldBackgroundColor: background,
    cardTheme: AppThemeBase.cardTheme(backgroundColor: cardWhite),
    appBarTheme: AppThemeBase.appBarTheme(primaryColor: primaryLight),
    inputDecorationTheme: AppThemeBase.inputDecorationTheme(primaryColor: primaryLight),
    extensions: [CalcwiseTheme.light(primary: Color(0xFF1F2937), accent: Color(0xFFD4AF37))],
    fontFamily: 'Inter',
  );

  static ThemeData get darkTheme => ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: primaryLight,
      brightness: Brightness.dark,
    ).copyWith(primary: accentLight, secondary: accentDark),
    scaffoldBackgroundColor: backgroundDark,
    cardTheme: AppThemeBase.cardTheme(backgroundColor: cardDark),
    appBarTheme: AppBarTheme(
      backgroundColor: primaryDark,
      foregroundColor: accentLight,
      elevation: 0,
    ),
    extensions: [CalcwiseTheme.dark(primary: Color(0xFF1F2937), accent: Color(0xFFD4AF37))],
    fontFamily: 'Inter',
  );
}
