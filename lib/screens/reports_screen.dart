import 'package:flutter/material.dart';
import '../core/flavor_config.dart';
import '../main.dart' show isSpanishNotifier;
import 'tax_breakdown_screen.dart';
import 'package:calcwise_core/calcwise_core.dart'
    show
        CalcwiseAdFooter,
        AppDuration,
        AppSpacing,
        AppRadius,
        AppTextSize;

/// Reports screen — salary and tax breakdown hub
class ReportsScreen extends StatelessWidget {
  const ReportsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: isSpanishNotifier,
      builder: (context, useAlt, _) {
        final es = FlavorConfig.isUS && useAlt;
        final fr = FlavorConfig.isCA && useAlt;

        String _t(String en, String esStr, String frStr) =>
            fr ? frStr : (es ? esStr : en);

        return Scaffold(
          appBar: AppBar(
            title: Text(_t('Reports', 'Reportes', 'Rapports')),
            elevation: 0,
          ),
          body: Column(
            children: [
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  children: [
                    _ToolCard(
                      icon: Icons.receipt_long_rounded,
                      title: _t('Tax Breakdown', 'Desglose fiscal',
                          'Décomposition fiscale'),
                      subtitle: _t(
                        'View detailed taxes by bracket, deductions, and net paycheck impact.',
                        'Ver impuestos detallados por tramo, deducciones e impacto neto.',
                        'Voir les impôts par tranche, déductions et impact net.',
                      ),
                      onTap: () => Navigator.push(
                        context,
                        PageRouteBuilder(
                          pageBuilder: (_, __, ___) =>
                              const TaxBreakdownScreen(),
                          transitionsBuilder: (_, anim, __, child) =>
                              FadeTransition(opacity: anim, child: child),
                          transitionDuration: AppDuration.base,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const CalcwiseAdFooter(),
            ],
          ),
        );
      },
    );
  }
}

class _ToolCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _ToolCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(
            color: Theme.of(context).dividerColor.withValues(alpha: 0.5)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ListTile(
        leading: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color:
                Theme.of(context).colorScheme.primary.withValues(alpha: 0.10),
            shape: BoxShape.circle,
          ),
          child: Icon(icon,
              color: Theme.of(context).colorScheme.primary, size: 22),
        ),
        title: Text(title,
            style: const TextStyle(
                fontWeight: FontWeight.w600, fontSize: AppTextSize.body)),
        subtitle: Text(subtitle,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: AppTextSize.sm)),
        trailing: const Icon(Icons.chevron_right_rounded),
        onTap: onTap,
        contentPadding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg, vertical: AppSpacing.sm),
      ),
    );
  }
}
