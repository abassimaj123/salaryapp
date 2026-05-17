import 'package:flutter/material.dart';
import '../main.dart' show isSpanishNotifier;
import '../widgets/app_bar_actions.dart';
import 'tax_breakdown_screen.dart';
import 'package:calcwise_core/calcwise_core.dart' show CalcwiseAdFooter;
import 'package:calcwise_core/calcwise_core.dart';

const double _spMd = 12.0;
const double _spLg = 16.0;

/// Reports screen — salary and tax breakdown hub
class ReportsScreen extends StatelessWidget {
  const ReportsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: isSpanishNotifier,
      builder: (context, useAlt, _) {
        return Scaffold(
          appBar: AppBar(
            title: Text(useAlt ? 'Reportes' : 'Reports'),
            elevation: 0,
            actions: const [AppBarActions()],
          ),
          body: Column(
            children: [
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.all(_spLg),
                  children: [
                    Card(
                      child: ListTile(
                        leading:
                            const Icon(Icons.receipt_long_rounded, size: 28),
                        title: const Text('Tax Breakdown',
                            style: TextStyle(fontWeight: FontWeight.w600)),
                        subtitle: Text(
                            useAlt
                                ? 'Ver desglose detallado de impuestos y deducciones'
                                : 'View detailed tax and deduction breakdown',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis),
                        trailing: const Icon(Icons.chevron_right_rounded),
                        onTap: () => Navigator.push(
                            context,
                            PageRouteBuilder(
                              pageBuilder: (_, __, ___) =>
                                  const TaxBreakdownScreen(),
                              transitionsBuilder: (_, anim, __, child) =>
                                  FadeTransition(opacity: anim, child: child),
                              transitionDuration: AppDuration.base,
                            )),
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: _spLg, vertical: _spMd),
                      ),
                    ),
                    const SizedBox(height: _spMd),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(_spLg),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              useAlt ? 'Sobre Reportes' : 'About Reports',
                              style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: AppTextSize.bodyMd),
                            ),
                            const SizedBox(height: _spMd),
                            Text(
                              useAlt
                                  ? 'Usa el desglose fiscal para ver impuestos detallados por tramo, deducciones del W-4, y el impacto neto en tu salario.'
                                  : 'Use the tax breakdown to see detailed taxes by bracket, W-4 deductions, and the net impact on your paycheck.',
                              style: const TextStyle(
                                  fontSize: AppTextSize.md, height: 1.6),
                            ),
                          ],
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
