import 'package:flutter/material.dart';
import 'package:calcwise_core/calcwise_core.dart'
    show CalcwiseSplash, isOnboardingComplete, AppDuration;
import '../core/flavor_config.dart';
import '../core/theme/app_theme.dart';
import '../core/analytics/analytics_service.dart';
import 'onboarding_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});
  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    try {
      analyticsService.logAppOpen();
    } catch (_) {}
  }

  String _flavorSuffix() {
    if (FlavorConfig.isCA) return 'CA';
    if (FlavorConfig.isUK) return 'UK';
    return 'US';
  }

  String _flavorTagline() => 'Know your true take-home pay';

  List<String> _flavorChips() {
    if (FlavorConfig.isCA) return ['Income Tax', 'CPP & EI', 'Net Pay'];
    if (FlavorConfig.isUK) return ['Income Tax', 'National Insurance', 'Net Pay'];
    return ['Federal Tax', 'FICA', 'Net Pay'];
  }

  Future<void> _navigate() async {
    final done = await isOnboardingComplete('salaryapp');
    if (!mounted) return;
    if (!done) {
      Navigator.of(context).pushReplacement(
        PageRouteBuilder(
          pageBuilder: (_, __, ___) => const OnboardingScreen(),
          transitionsBuilder: (_, anim, __, child) =>
              FadeTransition(opacity: anim, child: child),
          transitionDuration: AppDuration.base,
        ),
      );
    } else {
      Navigator.of(context).pushReplacementNamed('/home');
    }
  }

  @override
  Widget build(BuildContext context) => CalcwiseSplash(
        appName: 'Salary',
        appSuffix: _flavorSuffix(),
        tagline: _flavorTagline(),
        chips: _flavorChips(),
        badgeIcon: Icons.account_balance_wallet_rounded,
        backgroundColor: AppTheme.primary,
        onComplete: () async => _navigate(),
      );
}
