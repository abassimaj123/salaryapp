import 'package:flutter/material.dart';
import '../core/freemium/iap_service.dart';
import '../core/theme/app_theme.dart';

class PremiumCtaWidget extends StatelessWidget {
  final String feature;
  final bool compact;
  const PremiumCtaWidget({super.key, required this.feature, this.compact = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: EdgeInsets.all(compact ? 8 : 16),
      decoration: BoxDecoration(
        gradient: AppTheme.primaryGradient,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(
          color: AppTheme.primary.withValues(alpha: 0.25),
          blurRadius: 12, offset: const Offset(0, 4),
        )],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => IAPService.instance.buy(),
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: EdgeInsets.all(compact ? 14 : 20),
            child: Row(children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.star_rounded, color: Colors.white, size: 26),
              ),
              const SizedBox(width: 14),
              Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Unlock $feature',
                      style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 2),
                  const Text('No ads · Unlimited · PDF export',
                      style: TextStyle(color: Colors.white70, fontSize: 12)),
                ],
              )),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
                child: Text(r'$2.99',
                    style: TextStyle(color: AppTheme.primary, fontWeight: FontWeight.bold, fontSize: 13)),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}
