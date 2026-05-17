import 'package:flutter/material.dart';
import 'package:calcwise_core/calcwise_core.dart'
    show CalcwiseAppBarActions, CalcwiseRewardAdSheet, AppDuration;
import '../core/freemium/freemium_service.dart';
import '../main.dart' show paywallSession;
import '../screens/settings_screen.dart';

/// Standard AppBar trailing actions used across all SalaryApp tab screens.
/// Delegates to CalcwiseAppBarActions for a single source of truth.
class AppBarActions extends StatelessWidget {
  const AppBarActions({super.key});

  @override
  Widget build(BuildContext context) {
    return CalcwiseAppBarActions(
      freemium: freemiumService,
      session: paywallSession,
      onSettings: () => Navigator.push(
        context,
        PageRouteBuilder(
          pageBuilder: (_, __, ___) => const SettingsScreen(),
          transitionsBuilder: (_, anim, __, child) =>
              FadeTransition(opacity: anim, child: child),
          transitionDuration: AppDuration.base,
        ),
      ),
      onRewardAd: () => CalcwiseRewardAdSheet.show(context),
    );
  }
}
