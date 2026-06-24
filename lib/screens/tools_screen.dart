import 'package:flutter/material.dart';
import '../main.dart' show isSpanishNotifier, paywallSession;
import '../core/freemium/freemium_service.dart';
import '../core/analytics/analytics_service.dart';
import '../core/flavor_config.dart';
import '../core/freemium/iap_service.dart';
import '../widgets/tool_hub_card.dart';
import 'raise_calculator_screen.dart';
import 'bonus_calculator_screen.dart';
import 'w4_wizard_screen.dart';
import 'salary_comparison_screen.dart';
import 'rrsp_optimizer_screen.dart';
import 'retirement_optimizer_screen.dart';
import 'benefits_calculator_screen.dart';
import 'package:calcwise_core/calcwise_core.dart'
    show
        CalcwiseAdFooter,
        AppDuration,
        AppSpacing,
        AppTextSize,
        PaywallTrigger,
        PaywallSoft;
import '../widgets/paywall_hard.dart';

/// Tools screen — hub for salary calculators and utilities
class ToolsScreen extends StatefulWidget {
  const ToolsScreen({super.key});
  @override
  State<ToolsScreen> createState() => _ToolsScreenState();
}

class _ToolsScreenState extends State<ToolsScreen> {
  @override
  void initState() {
    super.initState();
    analyticsService.logScreenView('tools');
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: isSpanishNotifier,
      builder: (context, useAlt, _) {
        final es = FlavorConfig.isUS && useAlt;
        final fr = FlavorConfig.isCA && useAlt;

        String t(String en, String esStr, String frStr) =>
            fr ? frStr : (es ? esStr : en);

        Future<void> push(Widget screen) async {
          if (!context.mounted) return;
          await Navigator.push(
            context,
            PageRouteBuilder(
              pageBuilder: (_, __, ___) => screen,
              transitionsBuilder: (_, anim, __, child) =>
                  FadeTransition(opacity: anim, child: child),
              transitionDuration: AppDuration.base,
            ),
          );
        }

        return Scaffold(
          appBar: AppBar(
            title: Text(t('Tools', 'Herramientas', 'Outils')),
            elevation: 0,
          ),
          body: Column(
            children: [
              Expanded(
                child: ListView(
                  key: const PageStorageKey('tools_hub'),
                  padding: const EdgeInsets.fromLTRB(
                      AppSpacing.lg, AppSpacing.sm, AppSpacing.lg,
                      AppSpacing.lg),
                  children: [
                    // ── Raise Calculator ── all flavors ──────────────────────
                    ToolHubCard(
                      icon: Icons.trending_up_rounded,
                      title: t('Raise Calculator', 'Calculadora de Aumento',
                          'Calculateur d\'augmentation'),
                      subtitle: t(
                        'Calculate the impact of a raise on your salary.',
                        'Calcular el impacto de un aumento en tu salario.',
                        'Calculer l\'impact d\'une augmentation sur votre salaire.',
                      ),
                      onTap: () async {
                        final trigger = await paywallSession.recordAction();
                        if (!context.mounted) return;
                        if (trigger == PaywallTrigger.soft) PaywallSoft.show(context);
                        if (trigger == PaywallTrigger.hard) { PaywallHard.show(context); return; }
                        await push(const RaiseCalculatorScreen());
                      },
                    ),
                    const SizedBox(height: AppSpacing.md),

                    // ── Bonus Calculator ── all flavors ──────────────────────
                    ToolHubCard(
                      icon: Icons.card_giftcard_rounded,
                      title: t('Bonus Calculator', 'Calculadora de Bonificación',
                          'Calculateur de prime'),
                      subtitle: t(
                        'Estimate taxes and net gains on bonuses.',
                        'Estimar impuestos y ganancias netas en bonificaciones.',
                        'Estimer les impôts et gains nets sur les primes.',
                      ),
                      onTap: () async {
                        final trigger = await paywallSession.recordAction();
                        if (!context.mounted) return;
                        if (trigger == PaywallTrigger.soft) PaywallSoft.show(context);
                        if (trigger == PaywallTrigger.hard) { PaywallHard.show(context); return; }
                        await push(const BonusCalculatorScreen());
                      },
                    ),
                    const SizedBox(height: AppSpacing.md),

                    // ── Benefits Value Calculator ── all flavors ──────────────
                    ToolHubCard(
                      icon: Icons.volunteer_activism_rounded,
                      title: t(
                        'Benefits Value Calculator',
                        'Calculadora de valor de beneficios',
                        'Calculateur d\'avantages',
                      ),
                      subtitle: t(
                        'Calculate the real value of your employer benefits and total compensation.',
                        'Calcula el valor real de tus beneficios y compensación total.',
                        'Calculez la valeur réelle de vos avantages et rémunération globale.',
                      ),
                      onTap: () async {
                        analyticsService.logCalculationCompleted(
                            params: {'action': 'benefits_calculator_tapped'});
                        final trigger = await paywallSession.recordAction();
                        if (!context.mounted) return;
                        if (trigger == PaywallTrigger.soft) PaywallSoft.show(context);
                        if (trigger == PaywallTrigger.hard) { PaywallHard.show(context); return; }
                        await push(const BenefitsCalculatorScreen());
                      },
                    ),

                    // ── CA-specific ──────────────────────────────────────────
                    if (FlavorConfig.isCA) ...[
                      const SizedBox(height: AppSpacing.md),
                      ToolHubCard(
                        icon: Icons.account_balance_rounded,
                        title: fr ? 'Optimiseur REER' : 'RRSP Optimizer',
                        subtitle: fr
                            ? 'Réduisez votre impôt avec vos cotisations REER.'
                            : 'Reduce your tax with optimal RRSP contributions.',
                        onTap: () async {
                          analyticsService.logCalculationCompleted(
                              params: {'action': 'rrsp_optimizer_tapped'});
                          await push(const RrspOptimizerScreen());
                        },
                      ),
                    ],

                    // ── CA + UK: Salary Comparison ───────────────────────────
                    if (!FlavorConfig.isUS) ...[
                      const SizedBox(height: AppSpacing.md),
                      ToolHubCard(
                        icon: Icons.compare_arrows_rounded,
                        title: fr
                            ? 'Comparer deux salaires'
                            : 'Salary Comparison',
                        subtitle: fr
                            ? 'Comparez deux offres : salaire net, impôts, mensuel.'
                            : 'Compare two offers side by side: net pay, taxes, monthly.',
                        onTap: () async {
                          analyticsService.logCalculationCompleted(
                              params: {'action': 'salary_comparison_tapped'});
                          await push(const SalaryComparisonScreen());
                        },
                      ),
                    ],

                    // ── US-specific ──────────────────────────────────────────
                    if (FlavorConfig.isUS) ...[
                      const SizedBox(height: AppSpacing.md),
                      ToolHubCard(
                        icon: Icons.assignment_rounded,
                        title: es ? 'Asistente W-4' : 'W-4 Withholding Wizard',
                        subtitle: es
                            ? 'Optimiza tu retención federal.'
                            : 'Get your federal withholding exactly right.',
                        isPremium: true,
                        onTap: () async {
                          await paywallSession.recordAction();
                          if (!context.mounted) return;
                          if (!freemiumService.hasFullAccess) {
                            analyticsService.logPaywallViewed('feature_hard');
                            analyticsService.logFeatureGated('w4_wizard');
                            await PaywallHard.show(context,
                                isSpanish: es,
                                priceLabel:
                                    IAPService.instance.localizedPrice.value,
                                onPurchase: IAPService.instance.buy);
                            return;
                          }
                          if (!context.mounted) return;
                          await push(const W4WizardScreen());
                        },
                      ),
                      const SizedBox(height: AppSpacing.md),
                      ToolHubCard(
                        icon: Icons.compare_arrows_rounded,
                        title: es ? 'Comparar Salarios' : 'Salary Comparison',
                        subtitle: es
                            ? 'Compara dos ofertas: neto, impuestos, mensual.'
                            : 'Compare two offers side by side: net pay, taxes, monthly.',
                        isPremium: true,
                        onTap: () async {
                          analyticsService.logCalculationCompleted(
                              params: {'action': 'salary_comparison_tapped'});
                          final trigger = await paywallSession.recordAction();
                          if (!context.mounted) return;
                          if (trigger == PaywallTrigger.hard) {
                            analyticsService.logPaywallViewed('session_hard');
                            await PaywallHard.show(context, isSpanish: es);
                            return;
                          } else if (trigger == PaywallTrigger.soft) {
                            analyticsService.logPaywallViewed('session_soft');
                            await PaywallSoft.show(context,
                                isSpanish: es,
                                featureTitle: es
                                    ? 'Comparar Salarios'
                                    : 'Salary Comparison');
                          }
                          if (!context.mounted) return;
                          await push(const SalaryComparisonScreen());
                        },
                      ),
                      const SizedBox(height: AppSpacing.md),
                      ToolHubCard(
                        icon: Icons.savings_rounded,
                        title: es ? 'Optimizador 401(k)' : '401(k) Optimizer',
                        subtitle: es
                            ? 'Minimiza impuestos con aportes al 401(k).'
                            : 'Minimize taxes with optimal 401(k) contributions.',
                        onTap: () =>
                            push(const RetirementOptimizerScreen()),
                      ),
                    ],
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
