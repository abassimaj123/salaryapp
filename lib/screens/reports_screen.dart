import 'package:flutter/material.dart';
import 'package:calcwise_core/calcwise_core.dart'
    show CalcwiseAdFooter, AppDuration, AppSpacing, AppTextSize;
import '../core/analytics/analytics_service.dart';
import '../core/flavor_config.dart';
import '../main.dart' show isSpanishNotifier, salaryNotifier;
import '../widgets/tool_hub_card.dart';
import 'retirement_optimizer_screen.dart';
import 'salary_comparison_screen.dart';
import 'tax_breakdown_screen.dart';

/// Reports screen — salary and tax breakdown hub
class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      analyticsService.logScreenView('reports');
    });
  }

  @override
  Widget build(BuildContext context) {
    // CA and UK have only 1 report — show it directly (no list wrapper)
    if (FlavorConfig.isCA || FlavorConfig.isUK) {
      return ValueListenableBuilder<double>(
        valueListenable: salaryNotifier,
        builder: (_, salary, __) =>
            TaxBreakdownScreen(initialSalary: salary),
      );
    }

    return ValueListenableBuilder<bool>(
      valueListenable: isSpanishNotifier,
      builder: (context, useAlt, _) {
        final es = FlavorConfig.isUS && useAlt;

        String t(String en, String esStr) => es ? esStr : en;

        return Scaffold(
          appBar: AppBar(
            title: Text(t('Reports', 'Reportes')),
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
                    Padding(
                      padding: const EdgeInsets.only(
                          bottom: AppSpacing.md, top: AppSpacing.xs),
                      child: Text(
                        t(
                          'Detailed breakdowns to understand your money.',
                          'Desgloses detallados para entender tu dinero.',
                        ),
                        style: TextStyle(
                          fontSize: AppTextSize.sm,
                          color: Theme.of(context)
                              .colorScheme
                              .onSurfaceVariant,
                        ),
                      ),
                    ),
                    // ── Tax Breakdown ──────────────────────────────────────────
                    ToolHubCard(
                      icon: Icons.receipt_long_rounded,
                      title: t('Tax Bracket Breakdown',
                          'Tramos del impuesto'),
                      subtitle: t(
                        'Detailed taxes by bracket, effective rate, and take-home pay.',
                        'Ver impuestos por tramo, tasa efectiva e ingreso neto.',
                      ),
                      onTap: () => Navigator.push(
                        context,
                        PageRouteBuilder(
                          pageBuilder: (_, __, ___) =>
                              TaxBreakdownScreen(
                                  initialSalary: salaryNotifier.value),
                          transitionsBuilder: (_, anim, __, child) =>
                              FadeTransition(
                                  opacity: anim, child: child),
                          transitionDuration: AppDuration.base,
                        ),
                      ),
                    ),
                    if (FlavorConfig.isUS) ...[
                      const SizedBox(height: AppSpacing.md),
                      // ── 401(k) Optimizer ────────────────────────────────────────
                      ToolHubCard(
                        icon: Icons.savings_rounded,
                        title: t('401(k) Optimizer',
                            'Optimizador 401(k)'),
                        subtitle: t(
                          'Minimize taxes with optimal 401(k) contributions.',
                          'Minimiza impuestos con aportes al 401(k).',
                        ),
                        onTap: () => Navigator.push(
                          context,
                          PageRouteBuilder(
                            pageBuilder: (_, __, ___) =>
                                const RetirementOptimizerScreen(),
                            transitionsBuilder: (_, anim, __, child) =>
                                FadeTransition(
                                    opacity: anim, child: child),
                            transitionDuration: AppDuration.base,
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: AppSpacing.md),
                    // ── Salary Comparison ──────────────────────────────────────
                    ToolHubCard(
                      icon: Icons.compare_arrows_rounded,
                      title: t('Salary Comparison',
                          'Comparar Salarios'),
                      subtitle: t(
                        'Compare two offers side by side: net pay, taxes, monthly.',
                        'Compara dos ofertas: neto, impuestos, mensual.',
                      ),
                      isPremium: true,
                      onTap: () => Navigator.push(
                        context,
                        PageRouteBuilder(
                          pageBuilder: (_, __, ___) =>
                              const SalaryComparisonScreen(),
                          transitionsBuilder: (_, anim, __, child) =>
                              FadeTransition(
                                  opacity: anim, child: child),
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
