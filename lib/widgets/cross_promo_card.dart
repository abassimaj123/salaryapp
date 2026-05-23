import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import '../core/flavor_config.dart';
import '../core/theme/app_theme.dart';
import '../main.dart';
import 'package:calcwise_core/calcwise_core.dart';

// ── Cross-promo: AutoLoan ───────────────────────────────────────────────────
// Shown to free users only. Dismissible, remembers dismissal for 7 days.
class CrossPromoCard extends StatefulWidget {
  final bool isPremium;
  const CrossPromoCard({super.key, required this.isPremium});

  @override
  State<CrossPromoCard> createState() => _CrossPromoCardState();
}

class _CrossPromoCardState extends State<CrossPromoCard> {
  bool _dismissed = false;
  bool _checked = false;

  static const _prefKey = 'cross_promo_dismissed_salaryapp';
  static const _targetName = 'Auto Loan Calculator';
  static const _targetTagline = 'Best car loan deal — fast';
  static const _targetTaglineEs = 'El mejor préstamo de auto — rápido';
  static const _targetTaglineFr = 'Meilleur prêt auto — rapide';

  static const _targetId = 'com.calcwise.autoloan';
  static const _accentColor = AppTheme.crossPromoGreen;

  @override
  void initState() {
    super.initState();
    _checkDismissed();
  }

  Future<void> _checkDismissed() async {
    final prefs = await SharedPreferences.getInstance();
    final ts = prefs.getInt(_prefKey) ?? 0;
    final age = DateTime.now().millisecondsSinceEpoch - ts;
    if (mounted)
      setState(() {
        _dismissed = age < 7 * 24 * 3600 * 1000;
        _checked = true;
      });
  }

  Future<void> _dismiss() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_prefKey, DateTime.now().millisecondsSinceEpoch);
    if (mounted) setState(() => _dismissed = true);
  }

  Future<void> _open() async {
    final uri =
        Uri.parse('https://play.google.com/store/apps/details?id=$_targetId');
    if (await canLaunchUrl(uri))
      await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  String _altLabel(String en, String es, String fr) {
    if (!isSpanishNotifier.value) return en;
    return FlavorConfig.isCA ? fr : es;
  }

  @override
  Widget build(BuildContext context) {
    if (!_checked || _dismissed || widget.isPremium)
      return const SizedBox.shrink();
    return Container(
      margin:
          const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: 6),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: _accentColor.withValues(alpha: 0.06),
        border: Border.all(color: _accentColor.withValues(alpha: 0.2)),
        borderRadius: BorderRadius.circular(AppRadius.xl),
      ),
      child: Row(children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: _accentColor.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(AppRadius.mdPlus),
          ),
          child:
              Icon(Icons.directions_car_rounded, color: _accentColor, size: 22),
        ),
        const SizedBox(width: AppSpacing.smPlus),
        Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 6, vertical: AppSpacing.xxs),
              decoration: BoxDecoration(
                color: _accentColor,
                borderRadius: BorderRadius.circular(AppRadius.xs),
              ),
              child: const Text('CalqWise',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 9,
                      fontWeight: FontWeight.bold)),
            ),
            const SizedBox(width: 6),
            Text(
                _altLabel(
                    'Also from us', 'También de nosotros', 'Aussi de nous'),
                style: TextStyle(fontSize: 10, color: CalcwiseTheme.of(context).textSecondary)),
          ]),
          const SizedBox(height: AppSpacing.xxs),
          Text(_targetName,
              style: TextStyle(
                  fontSize: AppTextSize.md,
                  fontWeight: FontWeight.w600,
                  color: CalcwiseTheme.of(context).textPrimary)),
          Text(_altLabel(_targetTagline, _targetTaglineEs, _targetTaglineFr),
              style: TextStyle(
                  fontSize: AppTextSize.xs, color: CalcwiseTheme.of(context).textSecondary)),
        ])),
        const SizedBox(width: AppSpacing.sm),
        Column(children: [
          GestureDetector(
            onTap: _dismiss,
            child: Icon(Icons.close_rounded,
                size: 16, color: CalcwiseTheme.of(context).textSecondary),
          ),
          const SizedBox(height: AppSpacing.sm),
          GestureDetector(
            onTap: _open,
            child: Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.smPlus, vertical: 5),
              decoration: BoxDecoration(
                color: _accentColor,
                borderRadius: BorderRadius.circular(AppRadius.md),
              ),
              child: Text(_altLabel('Free', 'Gratis', 'Gratuit'),
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: AppTextSize.xs,
                      fontWeight: FontWeight.bold)),
            ),
          ),
        ]),
      ]),
    );
  }
}
