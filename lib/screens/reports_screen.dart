import 'package:flutter/material.dart';
import '../core/flavor_config.dart';
import '../main.dart' show isSpanishNotifier;
import 'tax_breakdown_screen.dart';
import 'rrsp_optimizer_screen.dart';
import 'retirement_optimizer_screen.dart';
import 'salary_comparison_screen.dart';
import '../widgets/tool_hub_card.dart';
import 'package:calcwise_core/calcwise_core.dart'
    show CalcwiseAdFooter, AppDuration, AppSpacing, AppTextSize;

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

        String t(String en, String esStr, String frStr) =>
            fr ? frStr : (es ? esStr : en);

        final cards = <Widget>[
          // ── Tax Breakdown ── all flavors ────────────────────────────────────
          ToolHubCard(
            icon: Icons.receipt_long_rounded,
            title: t('Tax Bracket Breakdown', 'Tramos del impuesto',
                'Tranches d\'imposition'),
            subtitle: t(
              'Detailed taxes by bracket, effective rate, and take-home pay.',
              'Ver impuestos por tramo, tasa efectiva e ingreso neto.',
              'Impôts par tranche, taux effectif et salaire net.',
            ),
            onTap: () => Navigator.push(
              context,
              PageRouteBuilder(
                pageBuilder: (_, __, ___) => const TaxBreakdownScreen(),
                transitionsBuilder: (_, anim, __, child) =>
                    FadeTransition(opacity: anim, child: child),
                transitionDuration: AppDuration.base,
              ),
            ),
          ),

          // ── CA-specific ─────────────────────────────────────────────────────
          if (FlavorConfig.isCA) ...[
            const SizedBox(height: AppSpacing.md),
            ToolHubCard(
              icon: Icons.account_balance_rounded,
              title: fr ? 'Optimiseur REER' : 'RRSP Optimizer',
              subtitle: fr
                  ? 'Réduisez votre impôt avec vos cotisations REER optimales.'
                  : 'Reduce your tax with optimal RRSP contributions.',
              onTap: () => Navigator.push(
                context,
                PageRouteBuilder(
                  pageBuilder: (_, __, ___) => const RrspOptimizerScreen(),
                  transitionsBuilder: (_, anim, __, child) =>
                      FadeTransition(opacity: anim, child: child),
                  transitionDuration: AppDuration.base,
                ),
              ),
            ),
          ],

          // ── US-specific ─────────────────────────────────────────────────────
          if (FlavorConfig.isUS) ...[
            const SizedBox(height: AppSpacing.md),
            ToolHubCard(
              icon: Icons.savings_rounded,
              title: es ? 'Optimizador 401(k)' : '401(k) Optimizer',
              subtitle: es
                  ? 'Minimiza impuestos con aportes al 401(k).'
                  : 'Minimize taxes with optimal 401(k) contributions.',
              onTap: () => Navigator.push(
                context,
                PageRouteBuilder(
                  pageBuilder: (_, __, ___) =>
                      const RetirementOptimizerScreen(),
                  transitionsBuilder: (_, anim, __, child) =>
                      FadeTransition(opacity: anim, child: child),
                  transitionDuration: AppDuration.base,
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            ToolHubCard(
              icon: Icons.compare_arrows_rounded,
              title: es ? 'Comparar Salarios' : 'Salary Comparison',
              subtitle: es
                  ? 'Compara dos ofertas: neto, impuestos, mensual.'
                  : 'Compare two offers side by side: net pay, taxes, monthly.',
              isPremium: true,
              onTap: () => Navigator.push(
                context,
                PageRouteBuilder(
                  pageBuilder: (_, __, ___) =>
                      const SalaryComparisonScreen(),
                  transitionsBuilder: (_, anim, __, child) =>
                      FadeTransition(opacity: anim, child: child),
                  transitionDuration: AppDuration.base,
                ),
              ),
            ),
          ],
        ];

        return Scaffold(
          appBar: AppBar(
            title: Text(t('Reports', 'Reportes', 'Rapports')),
            elevation: 0,
          ),
          body: Column(
            children: [
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(
                      AppSpacing.lg, AppSpacing.sm, AppSpacing.lg,
                      AppSpacing.lg),
                  children: [
                    // Section description
                    Padding(
                      padding: const EdgeInsets.only(
                          bottom: AppSpacing.md, top: AppSpacing.xs),
                      child: Text(
                        t(
                          'Detailed breakdowns to understand your money.',
                          'Desgloses detallados para entender tu dinero.',
                          'Analyses détaillées pour mieux comprendre vos finances.',
                        ),
                        style: TextStyle(
                          fontSize: AppTextSize.sm,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                    ...cards,
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
