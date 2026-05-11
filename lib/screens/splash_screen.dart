import 'package:flutter/material.dart';
import 'package:calcwise_core/calcwise_core.dart';
import '../core/theme/app_theme.dart';
import '../core/analytics/analytics_service.dart';
import '../main.dart' show paywallSession;

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});
  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    try { analyticsService.logAppOpen(); } catch (_) {}
  }

  @override
  Widget build(BuildContext context) => CalcwiseSplash(
    appName:     'Salary',
    appSuffix:   'Pro',
    tagline:     'Know what you actually take home',
    chips:       const ['After Tax', 'Hourly Rate', '3 Countries'],
    badgeSymbol: r'$+',
    badgeIcon: Icons.payments_rounded,
    backgroundColor: AppTheme.primary,
    onComplete: () async {
      Navigator.of(context).pushReplacementNamed('/home');
      await paywallSession.recordSession();
    },
  );
}
