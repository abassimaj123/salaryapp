import 'package:flutter/material.dart';
import '../main.dart' show isSpanishNotifier, paywallSession;
import '../core/analytics/analytics_service.dart';
import '../core/flavor_config.dart';
import '../widgets/app_bar_actions.dart';
import 'raise_calculator_screen.dart';
import 'bonus_calculator_screen.dart';
import 'w4_wizard_screen.dart';
import 'salary_comparison_screen.dart';
import 'package:calcwise_core/calcwise_core.dart'
    show
        CalcwiseAdFooter,
        AppDuration,
        AppSpacing,
        AppRadius,
        AppTextSize,
        PaywallTrigger,
        PaywallHard,
        PaywallSoft;

/// Tools screen — hub for salary calculators and utilities
class ToolsScreen extends StatelessWidget {
  const ToolsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: isSpanishNotifier,
      builder: (context, useAlt, _) {
        return Scaffold(
          appBar: AppBar(
            title: Text(useAlt ? 'Herramientas' : 'Tools'),
            elevation: 0,
            actions: const [AppBarActions()],
          ),
          body: Column(
            children: [
              Expanded(
                child: ListView(
                  key: const PageStorageKey('tools_hub'),
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  children: [
                    _ToolCard(
                      icon: Icons.trending_up_rounded,
                      title: useAlt
                          ? 'Calculadora de Aumento'
                          : 'Raise Calculator',
                      subtitle: useAlt
                          ? 'Calcular el impacto de un aumento en tu salario'
                          : 'Calculate the impact of a raise on your salary',
                      onTap: () => Navigator.push(
                          context,
                          PageRouteBuilder(
                            pageBuilder: (_, __, ___) => const RaiseCalculatorScreen(),
                            transitionsBuilder: (_, anim, __, child) =>
                                FadeTransition(opacity: anim, child: child),
                            transitionDuration: AppDuration.base,
                          )),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    _ToolCard(
                      icon: Icons.card_giftcard_rounded,
                      title: useAlt
                          ? 'Calculadora de Bonificación'
                          : 'Bonus Calculator',
                      subtitle: useAlt
                          ? 'Estimar impuestos y ganancias netas en bonificaciones'
                          : 'Estimate taxes and net gains on bonuses',
                      onTap: () => Navigator.push(
                          context,
                          PageRouteBuilder(
                            pageBuilder: (_, __, ___) =>
                                const BonusCalculatorScreen(),
                            transitionsBuilder: (_, anim, __, child) =>
                                FadeTransition(opacity: anim, child: child),
                            transitionDuration: AppDuration.base,
                          )),
                    ),
                    if (FlavorConfig.isUS) ...[
                      const SizedBox(height: AppSpacing.md),
                      _ToolCard(
                        icon: Icons.assignment_rounded,
                        title: 'W4 Wizard',
                        subtitle: useAlt
                            ? 'Asistente para optimizar tu formulario W4'
                            : 'Wizard to optimize your W4 withholding',
                        onTap: () => Navigator.push(
                            context,
                            PageRouteBuilder(
                              pageBuilder: (_, __, ___) =>
                                  const W4WizardScreen(),
                              transitionsBuilder: (_, anim, __, child) =>
                                  FadeTransition(opacity: anim, child: child),
                              transitionDuration: AppDuration.base,
                            )),
                      ),
                    ],
                    if (FlavorConfig.isUS) ...[
                    const SizedBox(height: AppSpacing.md),
                    _ToolCard(
                      icon: Icons.compare_arrows_rounded,
                      title: useAlt ? 'Comparar Salarios' : 'Salary Comparison',
                      subtitle: useAlt
                          ? 'Compara dos ofertas: neto, impuestos, mensual'
                          : 'Compare two offers: net pay, taxes, monthly',
                      onTap: () async {
                        analyticsService.logCalculationCompleted(
                            params: {'action': 'salary_comparison_tapped'});
                        final trigger = await paywallSession.recordAction();
                        if (!context.mounted) return;
                        if (trigger == PaywallTrigger.hard) {
                          analyticsService.logPaywallViewed('session_hard');
                          PaywallHard.show(context);
                          return;
                        } else if (trigger == PaywallTrigger.soft) {
                          analyticsService.logPaywallViewed('session_soft');
                          PaywallSoft.show(context,
                              featureTitle: useAlt
                                  ? 'Comparar Salarios'
                                  : 'Salary Comparison');
                        }
                        Navigator.push(
                          context,
                          PageRouteBuilder(
                            pageBuilder: (_, __, ___) =>
                                const SalaryComparisonScreen(),
                            transitionsBuilder: (_, anim, __, child) =>
                                FadeTransition(opacity: anim, child: child),
                            transitionDuration: AppDuration.base,
                          ),
                        );
                      },
                    ),
                  ], // end FlavorConfig.isUS (Salary Comparison)
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
            color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.10),
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
