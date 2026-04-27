import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});
  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  static const _bg = Color(0xFFE65100);
  late AnimationController _ctrl;
  late Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: _bg,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: _bg,
    ));
    _ctrl  = AnimationController(vsync: this, duration: const Duration(milliseconds: 800))..forward();
    _scale = CurvedAnimation(parent: _ctrl, curve: Curves.elasticOut);
    Future.delayed(const Duration(milliseconds: 1500), () {
      if (mounted) Navigator.of(context).pushReplacementNamed('/home');
    });
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      body: Center(
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          ScaleTransition(
            scale: _scale,
            child: Container(
              width: 110, height: 110,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(28),
              ),
              child: const Icon(Icons.calculate_outlined, size: 62, color: Colors.white),
            ),
          ),
          const SizedBox(height: 32),
          Text('Salary Calculator',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white, fontSize: 22,
                  fontWeight: FontWeight.w700, letterSpacing: 0.3)),
          const SizedBox(height: 8),
          Text('Net Pay & Tax Estimator',
              style: TextStyle(color: Colors.white.withValues(alpha: 0.75), fontSize: 14)),
          const SizedBox(height: 56),
          const _Dots(),
        ]),
      ),
    );
  }
}

class _Dots extends StatefulWidget {
  const _Dots();
  @override
  State<_Dots> createState() => _DotsState();
}
class _DotsState extends State<_Dots> with SingleTickerProviderStateMixin {
  late AnimationController _c;
  @override
  void initState() {
    super.initState();
    _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1200))..repeat();
  }
  @override
  void dispose() { _c.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (_, __) => Row(mainAxisAlignment: MainAxisAlignment.center,
        children: List.generate(3, (i) {
          final t  = (_c.value - i * 0.15) % 1.0;
          final op = (t < 0.5 ? t * 2 : (1 - t) * 2).clamp(0.3, 1.0);
          return Container(
            margin: const EdgeInsets.symmetric(horizontal: 4),
            width: 7, height: 7,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: op), shape: BoxShape.circle),
          );
        }),
      ),
    );
  }
}
