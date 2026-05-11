import 'package:flutter/material.dart';
import 'package:calcwise_core/calcwise_core.dart';
import '../flavor_config.dart';
import 'app_theme_ca.dart';
import 'app_theme_us.dart';
import 'app_theme_uk.dart';

/// Unified theme export — automatically selects correct theme per flavor
class AppTheme {
  AppTheme._();

  // ─── Color accessors for screens ──────────────────────────────────────────
  static Color get primary {
    if (FlavorConfig.isCA) return const Color(0xFFE67E22); // Burnt Orange
    if (FlavorConfig.isUS) return const Color(0xFFDC2626); // Red
    return const Color(0xFF1F2937); // Black
  }

  static Color get accent {
    if (FlavorConfig.isCA) return const Color(0xFFEF4444);
    if (FlavorConfig.isUS) return const Color(0xFFF59E0B);
    return const Color(0xFFD4AF37);
  }

  static Color get success {
    return const Color(0xFF10B981); // Emerald green
  }

  static Color get labelGray {
    return const Color(0xFF6B7280); // Neutral gray
  }

  static Color get error {
    return const Color(0xFFEF4444); // Red
  }

  static Color get warning {
    return const Color(0xFFF59E0B); // Amber
  }

  static Color get divider {
    return const Color(0xFFE5E7EB); // Light gray
  }

  // Gradient for primary brand (used in headers, buttons, etc.)
  static LinearGradient get primaryGradient {
    if (FlavorConfig.isCA) {
      return const LinearGradient(
        colors: [Color(0xFFE67E22), Color(0xFFC86D1F)],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      );
    } else if (FlavorConfig.isUS) {
      return const LinearGradient(
        colors: [Color(0xFFDC2626), Color(0xFFB91C1C)],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      );
    }
    return const LinearGradient(
      colors: [Color(0xFF1F2937), Color(0xFFD4AF37)],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    );
  }

  static ThemeData get theme => CalcwiseThemeFactory.buildLight(primary: primary, accent: accent);
  static ThemeData get dark  => CalcwiseThemeFactory.buildDark(primary: primary, accent: accent);
}
