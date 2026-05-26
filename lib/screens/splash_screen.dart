import 'package:flutter/material.dart';
import 'package:calcwise_core/calcwise_core.dart'
    show isOnboardingComplete, AppDuration;
import '../core/theme/app_theme.dart';
import '../core/analytics/analytics_service.dart';
import 'onboarding_screen.dart';

/// Minimal splash — shows brand color while async init runs.
/// The animated 3-dot entrance is handled by the native Android splash
/// (windowSplashScreenAnimatedIcon in values-v31/styles.xml).
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
    _navigate();
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
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: AppTheme.primary,
        body: const SizedBox.expand(),
      );
}
