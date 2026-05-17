import 'package:flutter/material.dart';
import '../main.dart' show isSpanishNotifier, paywallSession;
import '../core/analytics/analytics_service.dart';
import '../widgets/app_bar_actions.dart';
import 'raise_screen.dart';
import 'bonus_calculator_screen.dart';
import 'w4_wizard_screen.dart';
import 'salary_comparison_screen.dart';
import 'package:calcwise_core/calcwise_core.dart'
    show CalcwiseAdFooter, AppDuration, PaywallTrigger, PaywallHard, PaywallSoft;

// Local spacing constants (mirrors calcwise_core tokens)
const double _spMd = 12.0;
const double _spLg = 16.0;
const double _spSm = 8.0;
const double _radLg = 12.0;
const double _textBody = 14.0;
const double _textSm = 12.0;

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
                  padding: const EdgeInsets.all(_spLg),
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
                            pageBuilder: (_, __, ___) => const RaiseScreen(),
                            transitionsBuilder: (_, anim, __, child) =>
                                FadeTransition(opacity: anim, child: child),
                            transitionDuration: AppDuration.base,
                          )),
                    ),
                    const SizedBox(height: _spMd),
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
                    const SizedBox(height: _spMd),
                    _ToolCard(
                      icon: Icons.assignment_rounded,
                      title: 'W4 Wizard',
                      subtitle: useAlt
                          ? 'Asistente para optimizar tu formulario W4'
                          : 'Wizard to optimize your W4 withholding',
                      onTap: () => Navigator.push(
                          context,
                          PageRouteBuilder(
                            pageBuilder: (_, __, ___) => const W4WizardScreen(),
                            transitionsBuilder: (_, anim, __, child) =>
                                FadeTransition(opacity: anim, child: child),
                            transitionDuration: AppDuration.base,
                          )),
                    ),
                    const SizedBox(height: _spMd),
                    _ToolCard(
                      icon: Icons.compare_arrows_rounded,
                      title: useAlt
                          ? 'Comparar Salarios'
                          : 'Salary Comparison',
                      subtitle: useAlt
                          ? 'Compara dos ofertas: neto, impuestos, mensual'
                          : 'Compare two offers: net pay, taxes, monthly',
                      onTap: () async {
                        analyticsService.logCalculationCompleted(
                            params: {'action': 'salary_comparison_tapped'});
                        final trigger =
                            await paywallSession.recordAction();
                        if (!context.mounted) return;
                        if (trigger == PaywallTrigger.hard) {
                          analyticsService
                              .logPaywallViewed('session_hard');
                          PaywallHard.show(context);
                          return;
                        } else if (trigger == PaywallTrigger.soft) {
                          analyticsService
                              .logPaywallViewed('session_soft');
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
    return Card(
      shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(_radLg)),
      child: ListTile(
        leading: Icon(icon, size: 28),
        title: Text(title,
            style: const TextStyle(
                fontWeight: FontWeight.w600, fontSize: _textBody)),
        subtitle: Text(subtitle,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: _textSm)),
        trailing: const Icon(Icons.chevron_right_rounded),
        onTap: onTap,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: _spLg, vertical: _spSm),
      ),
    );
  }
}
