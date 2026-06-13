import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:calcwise_core/calcwise_core.dart';
import 'app_theme_base.dart';

/// Canada Theme - Canada Red (matches MortgageCA icon palette)
class AppThemeCA {
  static const Color primaryLight =
      Color(0xFFC8102E); // Canada Red
  static const Color primaryDark = Color(0xFFA50D24); // Deep Canada Red
  static const Color secondaryLight =
      Color(0xFFFF3D5A); // Lighter red accent
  static const Color secondaryDark = Color(0xFFE8112A); // Medium Canada Red
  static const Color background = Color(0xFFFFF5F6); // Light warm white
  static const Color backgroundDark = Color(0xFF1A0509); // Dark red-tinted
  static const Color cardWhite = Colors.white;
  static const Color cardDark = Color(0xFF2D0A10); // Dark red card

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
              primary: Color(0xFFC8102E),
              accent: Color(0xFFFF3D5A),
              primaryDeep: Color(0xFFA50D24))
        ],
        textTheme: GoogleFonts.interTextTheme(ThemeData.light().textTheme),
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
              primary: Color(0xFFC8102E),
              accent: Color(0xFFFF3D5A),
              primaryDeep: Color(0xFFA50D24))
        ],
        textTheme: GoogleFonts.interTextTheme(ThemeData.dark().textTheme),
      );
}
