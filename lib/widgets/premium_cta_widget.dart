import 'package:flutter/material.dart';
import '../core/freemium/iap_service.dart';
import '../core/theme/app_theme.dart';
import 'package:calcwise_core/calcwise_core.dart';

class PremiumCtaWidget extends StatelessWidget {
  final String feature;
  final bool compact;
  const PremiumCtaWidget(
      {super.key, required this.feature, this.compact = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: EdgeInsets.all(compact ? 8 : 16),
      decoration: BoxDecoration(
        gradient: AppTheme.primaryGradient,
        borderRadius: BorderRadius.circular(AppRadius.xl),
        boxShadow: [
          BoxShadow(
            color: AppTheme.primary.withValues(alpha: 0.25),
            blurRadius: 12,
            offset: const Offset(0, 4),
          )
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => IAPService.instance.buy(),
          borderRadius: BorderRadius.circular(AppRadius.xl),
          child: Padding(
            padding: EdgeInsets.all(compact ? 14 : 20),
            child: Row(children: [
              Container(
                padding: const EdgeInsets.all(AppSpacing.smPlus),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(AppRadius.lg),
                ),
                child: Icon(Icons.star_rounded, color: Colors.white, size: 26),
              ),
              SizedBox(width: AppSpacing.mdPlus),
              Expanded(
                  child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Unlock $feature',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: AppTextSize.bodyMd,
                          fontWeight: FontWeight.bold)),
                  SizedBox(height: AppSpacing.xxs),
                  Text('No ads · Unlimited · PDF export',
                      style: TextStyle(
                          color: Colors.white70, fontSize: AppTextSize.sm)),
                ],
              )),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: AppSpacing.mdPlus, vertical: AppSpacing.sm),
                decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20)),
                child: Text(r'$2.99',
                    style: TextStyle(
                        color: AppTheme.primary,
                        fontWeight: FontWeight.bold,
                        fontSize: AppTextSize.md)),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}
