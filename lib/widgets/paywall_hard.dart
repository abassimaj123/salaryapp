import 'package:flutter/material.dart';
import '../core/freemium/iap_service.dart';
import '../core/freemium/freemium_service.dart';
import '../core/ads/ad_service.dart';
import '../core/theme/app_theme.dart';

class PaywallHard extends StatelessWidget {
  const PaywallHard({super.key});

  static Future<void> show(BuildContext context) => showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => const PaywallHard(),
      );

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.orange.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.trending_up_rounded, color: Colors.orange, size: 32),
            ),
            const SizedBox(height: 16),
            const Text('Don\'t let fees cost you thousands',
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.primary)),
            const SizedBox(height: 6),
            const Text('Premium shows exactly how to save more',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: AppTheme.labelGray)),
            const SizedBox(height: 18),
            ...['💰 Compare multiple scenarios', '📉 Auto optimisation strategy',
                    '📊 Unlimited history & PDF export', '🚫 Zero ads — ever']
                .map((f) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 5),
                      child: Row(children: [
                        const SizedBox(width: 8),
                        Expanded(child: Text(f, style: const TextStyle(fontSize: 14))),
                      ]),
                    )),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {
                  Navigator.pop(context);
                  IAPService.instance.buy();
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                child: const Text('Start saving now\n\$2.99 (save \$100+)',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontWeight: FontWeight.bold, height: 1.4)),
              ),
            ),
            const SizedBox(height: 8),
            if (AdService.instance.isRewardedReady)
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: () {
                    Navigator.pop(context);
                    AdService.instance.showRewarded(
                      onRewarded: () => freemiumService.activateRewarded(),
                    );
                  },
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppTheme.primary,
                    side: const BorderSide(color: AppTheme.primary),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  child: const Text('Watch ad (60 min free)', style: TextStyle(fontSize: 13)),
                ),
              ),
            const SizedBox(height: 4),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Maybe later',
                  style: TextStyle(color: AppTheme.labelGray, fontSize: 13)),
            ),
          ],
        ),
      ),
    );
  }
}
