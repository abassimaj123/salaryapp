import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../core/flavor_config.dart';
import '../core/theme/app_theme.dart';
import '../core/freemium/freemium_service.dart';
import '../main.dart' show isSpanishNotifier;
import '../widgets/result_card.dart';
import '../widgets/paywall_hard.dart';
import 'package:calcwise_core/calcwise_core.dart' show CalcwiseAdFooter;
import 'package:calcwise_core/calcwise_core.dart';

// ─── 2024 US Federal Tax Brackets (single filer) ─────────────────────────────

const _kStandardDeduction = 14600.0;

const _kBrackets = <_Bracket>[
  _Bracket(min: 0, max: 11600, rate: 0.10),
  _Bracket(min: 11600, max: 47150, rate: 0.12),
  _Bracket(min: 47150, max: 100525, rate: 0.22),
  _Bracket(min: 100525, max: 191950, rate: 0.24),
  _Bracket(min: 191950, max: 243725, rate: 0.32),
  _Bracket(min: 243725, max: 609350, rate: 0.35),
  _Bracket(min: 609350, max: double.infinity, rate: 0.37),
];

/// Top-5 state flat income-tax rates for 2024 (used in premium comparison).
const _kTopStates = <_StateTax>[
  _StateTax(code: 'TX', name: 'Texas', rate: 0.00),
  _StateTax(code: 'FL', name: 'Florida', rate: 0.00),
  _StateTax(code: 'WA', name: 'Washington', rate: 0.00),
  _StateTax(code: 'NY', name: 'New York', rate: 0.109),
  _StateTax(code: 'CA', name: 'California', rate: 0.133),
];

class _Bracket {
  final double min, max, rate;
  const _Bracket({required this.min, required this.max, required this.rate});
}

class _StateTax {
  final String code, name;
  final double rate;
  const _StateTax({required this.code, required this.name, required this.rate});
}

// ─── Bracket computation helper ───────────────────────────────────────────────

class _BracketResult {
  final double min, max, rate;
  final double amountInBracket;
  final double taxOwed;

  const _BracketResult({
    required this.min,
    required this.max,
    required this.rate,
    required this.amountInBracket,
    required this.taxOwed,
  });
}

List<_BracketResult> _computeBrackets(double grossAnnual) {
  final taxable =
      (grossAnnual - _kStandardDeduction).clamp(0.0, double.infinity);
  final results = <_BracketResult>[];
  for (final b in _kBrackets) {
    if (taxable <= b.min) break;
    final inBracket = (taxable - b.min)
        .clamp(0.0, b.max == double.infinity ? double.infinity : b.max - b.min);
    if (inBracket <= 0) continue;
    results.add(_BracketResult(
      min: b.min,
      max: b.max,
      rate: b.rate,
      amountInBracket: inBracket,
      taxOwed: inBracket * b.rate,
    ));
  }
  return results;
}

// ─── Screen ───────────────────────────────────────────────────────────────────

class TaxBreakdownScreen extends StatefulWidget {
  final double? initialSalary;

  const TaxBreakdownScreen({super.key, this.initialSalary});

  @override
  State<TaxBreakdownScreen> createState() => _TaxBreakdownScreenState();
}

class _TaxBreakdownScreenState extends State<TaxBreakdownScreen> {
  final _formKey = GlobalKey<FormState>();
  final _salaryCtrl = TextEditingController();

  double? _grossAnnual;
  List<_BracketResult> _brackets = [];

  @override
  void initState() {
    super.initState();
    if (widget.initialSalary != null && widget.initialSalary! > 0) {
      _salaryCtrl.text = widget.initialSalary!.toStringAsFixed(0);
      _run(widget.initialSalary!);
    }
  }

  @override
  void dispose() {
    _salaryCtrl.dispose();
    super.dispose();
  }

  void _run(double gross) {
    setState(() {
      _grossAnnual = gross;
      _brackets = _computeBrackets(gross);
    });
  }

  void _calculate() {
    if (!_formKey.currentState!.validate()) return;
    HapticFeedback.mediumImpact();
    FocusScope.of(context).unfocus();
    final raw =
        _salaryCtrl.text.replaceAll(',', '.').replaceAll(RegExp(r'[^\d.]'), '');
    final v = double.tryParse(raw) ?? 0;
    if (v > 0) _run(v);
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: isSpanishNotifier,
      builder: (context, useAlt, _) {
        final es = FlavorConfig.isUS && useAlt;
        final fr = FlavorConfig.isCA && useAlt;

        final title = fr
            ? 'Tranches d\'imposition'
            : (es ? 'Tramos del impuesto' : 'Tax Bracket Breakdown');
        final calcLabel = fr ? 'Calculer' : (es ? 'Calcular' : 'Calculate');

        return Scaffold(
          appBar: AppBar(title: Text(title)),
          body: Column(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (!FlavorConfig.isUS) ...[
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: AppSpacing.md,
                                vertical: AppSpacing.sm),
                            decoration: BoxDecoration(
                              color: AppTheme.warning.withValues(alpha: 0.12),
                              borderRadius:
                                  BorderRadius.circular(AppRadius.lg),
                              border: Border.all(
                                  color:
                                      AppTheme.warning.withValues(alpha: 0.4)),
                            ),
                            child: Row(children: [
                              Icon(Icons.info_outline_rounded,
                                  color: AppTheme.warning, size: 18),
                              const SizedBox(width: AppSpacing.sm),
                              Expanded(
                                child: Text(
                                  fr
                                      ? 'Affichage des tranches fédérales américaines (US IRS 2024)'
                                      : 'Showing US Federal tax brackets (IRS 2024)',
                                  style: TextStyle(
                                      fontSize: AppTextSize.sm,
                                      color: AppTheme.warning),
                                ),
                              ),
                            ]),
                          ),
                          const SizedBox(height: AppSpacing.md),
                        ],
                        _SalaryInput(controller: _salaryCtrl, es: es, fr: fr),
                        const SizedBox(height: AppSpacing.lg),
                        ElevatedButton(
                          onPressed: _calculate,
                          child: Text(calcLabel,
                              style: TextStyle(
                                  fontSize: AppTextSize.bodyLg,
                                  fontWeight: FontWeight.w700)),
                        ),
                        if (_grossAnnual != null && _brackets.isNotEmpty) ...[
                          const SizedBox(height: AppSpacing.xxlPlus),
                          _TaxBreakdownSection(
                            grossAnnual: _grossAnnual!,
                            brackets: _brackets,
                            es: es,
                            fr: fr,
                          ),
                        ],
                        const SizedBox(height: AppSpacing.lg),
                      ],
                    ),
                  ),
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

// ─── Salary input ─────────────────────────────────────────────────────────────

class _SalaryInput extends StatelessWidget {
  final TextEditingController controller;
  final bool es, fr;

  const _SalaryInput(
      {required this.controller, required this.es, required this.fr});

  @override
  Widget build(BuildContext context) {
    final label = fr
        ? 'Salaire brut annuel'
        : (es ? 'Salario bruto anual' : 'Annual Gross Salary');

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: TextFormField(
          controller: controller,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'[\d.,]')),
          ],
          decoration: InputDecoration(
            prefixText: '\$ ',
            prefixStyle: const TextStyle(
                fontSize: AppTextSize.subtitle, fontWeight: FontWeight.w600),
            labelText: label,
            hintText: '75000',
          ),
          style: const TextStyle(
              fontSize: AppTextSize.subtitle, fontWeight: FontWeight.w600),
          validator: (v) {
            if (v == null || v.trim().isEmpty) {
              return fr ? 'Requis' : (es ? 'Requerido' : 'Required');
            }
            final val = double.tryParse(
                v.replaceAll(',', '.').replaceAll(RegExp(r'[^\d.]'), ''));
            if (val == null || val <= 0) {
              return fr
                  ? 'Montant invalide'
                  : (es ? 'Inválido' : 'Invalid amount');
            }
            return null;
          },
        ),
      ),
    );
  }
}

// ─── Main breakdown section ───────────────────────────────────────────────────

class _TaxBreakdownSection extends StatelessWidget {
  final double grossAnnual;
  final List<_BracketResult> brackets;
  final bool es, fr;

  const _TaxBreakdownSection({
    required this.grossAnnual,
    required this.brackets,
    required this.es,
    required this.fr,
  });

  String _fmt(double v) => NumberFormat.currency(
        symbol: '\$',
        decimalDigits: 0,
      ).format(v);

  String _fmt2(double v) => NumberFormat.currency(
        symbol: '\$',
        decimalDigits: 2,
      ).format(v);

  @override
  Widget build(BuildContext context) {
    final totalFederal = brackets.fold(0.0, (sum, b) => sum + b.taxOwed);
    final taxable =
        (grossAnnual - _kStandardDeduction).clamp(0.0, double.infinity);
    final effectiveRate =
        grossAnnual > 0 ? totalFederal / grossAnnual * 100 : 0.0;
    final takeHome = grossAnnual - totalFederal;

    final deductionLabel = fr
        ? 'Déduction standard (célibataire)'
        : (es ? 'Deducción estándar (soltero)' : 'Standard Deduction (Single)');
    final taxableLabel =
        fr ? 'Revenu imposable' : (es ? 'Ingreso imponible' : 'Taxable Income');
    final federalLabel = fr
        ? 'Impôt fédéral total'
        : (es ? 'Impuesto federal total' : 'Total Federal Tax');
    final effectiveLabel =
        fr ? 'Taux effectif' : (es ? 'Tasa efectiva' : 'Effective Rate');
    final takeHomeLabel = fr
        ? 'Revenu net (avant état/FICA)'
        : (es
            ? 'Take-home (antes de estado/FICA)'
            : 'Take-Home (before state/FICA)');
    final bracketsTitle = fr
        ? 'Tranche par tranche'
        : (es ? 'Tramo por tramo' : '2024 Federal Tax Brackets');
    final bracketLabel = fr ? 'Tranche' : (es ? 'Tramo' : 'Bracket');
    final rateLabel = fr ? 'Taux' : (es ? 'Tasa' : 'Rate');
    final inBracketLabel =
        fr ? 'Dans la tranche' : (es ? 'En el tramo' : 'In Bracket');
    final taxOwedLabel = fr ? 'Impôt dû' : (es ? 'Impuesto' : 'Tax Owed');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Summary cards
        ResultCard(
          label: federalLabel,
          value: _fmt(totalFederal),
          icon: Icons.account_balance_rounded,
          highlight: true,
        ),
        const SizedBox(height: AppSpacing.md),
        Row(children: [
          Expanded(
              child: ResultCard(
                  label: effectiveLabel,
                  value: '${effectiveRate.toStringAsFixed(1)}%')),
          const SizedBox(width: AppSpacing.smPlus),
          Expanded(
              child: ResultCard(label: takeHomeLabel, value: _fmt(takeHome))),
        ]),
        const SizedBox(height: AppSpacing.smPlus),
        Row(children: [
          Expanded(
              child: ResultCard(
                  label: deductionLabel, value: _fmt(_kStandardDeduction))),
          const SizedBox(width: AppSpacing.smPlus),
          Expanded(
              child: ResultCard(label: taxableLabel, value: _fmt(taxable))),
        ]),
        const SizedBox(height: AppSpacing.xl),

        // Progress bar visualization
        _BracketProgressBar(brackets: brackets, grossAnnual: grossAnnual),
        const SizedBox(height: AppSpacing.xl),

        // Bracket table
        Card(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Icon(Icons.table_chart_rounded,
                      size: 18, color: AppTheme.primary),
                  const SizedBox(width: AppSpacing.sm),
                  Text(bracketsTitle,
                      style: TextStyle(
                          fontSize: AppTextSize.bodyMd,
                          fontWeight: FontWeight.w600)),
                ]),
                const SizedBox(height: AppSpacing.mdPlus),
                Table(
                  columnWidths: const {
                    0: FlexColumnWidth(3),
                    1: FlexColumnWidth(1.5),
                    2: FlexColumnWidth(3),
                    3: FlexColumnWidth(3),
                  },
                  children: [
                    TableRow(
                      decoration: BoxDecoration(
                          border: Border(
                              bottom: BorderSide(color: AppTheme.divider))),
                      children: [
                        _th(bracketLabel),
                        _th(rateLabel),
                        _th(inBracketLabel),
                        _th(taxOwedLabel),
                      ],
                    ),
                    for (final b in brackets)
                      TableRow(
                        children: [
                          _td('\$${_shortNum(b.min)}–${b.max == double.infinity ? '∞' : '\$${_shortNum(b.max)}'}'),
                          _td('${(b.rate * 100).toStringAsFixed(0)}%',
                              color: _bracketColor(b.rate)),
                          _td(_fmt2(b.amountInBracket)),
                          _td(_fmt2(b.taxOwed),
                              color: CalcwiseSemanticColors.errorDark),
                        ],
                      ),
                    TableRow(
                      decoration: BoxDecoration(
                          border:
                              Border(top: BorderSide(color: AppTheme.divider))),
                      children: [
                        _td('Total', bold: true),
                        _td(''),
                        _td(''),
                        _td(_fmt2(totalFederal),
                            bold: true,
                            color: CalcwiseSemanticColors.errorDark),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.lg),

        // Premium: state tax comparison
        ValueListenableBuilder<bool>(
          valueListenable: freemiumService.isPremiumNotifier,
          builder: (context, isPremium, _) => isPremium
              ? _StateComparisonCard(grossAnnual: grossAnnual, es: es, fr: fr)
              : _PremiumStateTeaser(es: es, fr: fr, context: context),
        ),
      ],
    );
  }

  String _shortNum(double v) {
    if (v >= 1000000) return '${(v / 1000000).toStringAsFixed(1)}M';
    if (v >= 1000) return '${(v / 1000).toStringAsFixed(0)}k';
    return v.toStringAsFixed(0);
  }

  Color _bracketColor(double rate) {
    if (rate <= 0.10) return CalcwiseSemanticColors.successDeep;
    if (rate <= 0.12) return CalcwiseSemanticColors.successDark;
    if (rate <= 0.22) return CalcwiseSemanticColors.warnIcon;
    if (rate <= 0.24) return CalcwiseSemanticColors.warnIcon;
    if (rate <= 0.32) return CalcwiseSemanticColors.alertText;
    if (rate <= 0.35) return CalcwiseSemanticColors.errorDark;
    return CalcwiseSemanticColors.errorDark;
  }

  Widget _th(String text) => Padding(
        padding: const EdgeInsets.only(bottom: AppSpacing.sm),
        child: Text(text,
            style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: AppTheme.labelGray)),
      );

  Widget _td(String text, {Color? color, bool bold = false}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Text(text,
            style: TextStyle(
                fontSize: AppTextSize.xs,
                fontWeight: bold ? FontWeight.bold : FontWeight.w500,
                color: color)),
      );
}

// ─── Stacked progress bar ─────────────────────────────────────────────────────

class _BracketProgressBar extends StatelessWidget {
  final List<_BracketResult> brackets;
  final double grossAnnual;

  const _BracketProgressBar(
      {required this.brackets, required this.grossAnnual});

  Color _color(double rate) {
    if (rate <= 0.10) return CalcwiseSemanticColors.successDeep;
    if (rate <= 0.12) return CalcwiseSemanticColors.successDark;
    if (rate <= 0.22) return const Color(0xFFF5C518);
    if (rate <= 0.24) return CalcwiseSemanticColors.warnIcon;
    if (rate <= 0.32) return CalcwiseSemanticColors.alertText;
    if (rate <= 0.35) return CalcwiseSemanticColors.errorDark;
    return CalcwiseSemanticColors.errorDark;
  }

  @override
  Widget build(BuildContext context) {
    final totalFederal = brackets.fold(0.0, (sum, b) => sum + b.taxOwed);
    final takeHome = grossAnnual - totalFederal;
    final total = grossAnnual;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(Icons.bar_chart_rounded, size: 18, color: AppTheme.primary),
              const SizedBox(width: AppSpacing.sm),
              Text('Tax Visualization',
                  style: TextStyle(
                      fontSize: AppTextSize.bodyMd,
                      fontWeight: FontWeight.w600)),
            ]),
            const SizedBox(height: AppSpacing.lg),

            // Stacked bar
            ClipRRect(
              borderRadius: BorderRadius.circular(AppRadius.md),
              child: SizedBox(
                height: 28,
                child: Row(
                  children: [
                    // Net pay (green)
                    Flexible(
                      flex: (takeHome / total * 1000).round(),
                      child: Container(color: AppTheme.success),
                    ),
                    // Tax brackets (varying colors)
                    for (final b in brackets)
                      Flexible(
                        flex: (b.taxOwed / total * 1000).round().clamp(1, 1000),
                        child: Container(color: _color(b.rate)),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.md),

            // Legend
            Wrap(
              spacing: 12,
              runSpacing: 6,
              children: [
                _legendItem(AppTheme.success, 'Net pay'),
                for (final b in brackets)
                  _legendItem(
                      _color(b.rate), '${(b.rate * 100).toStringAsFixed(0)}%'),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _legendItem(Color color, String label) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: AppSpacing.xs),
          Text(label,
              style: TextStyle(
                  fontSize: AppTextSize.xs, color: AppTheme.labelGray)),
        ],
      );
}

// ─── Premium: State tax comparison ───────────────────────────────────────────

class _StateComparisonCard extends StatelessWidget {
  final double grossAnnual;
  final bool es, fr;

  const _StateComparisonCard({
    required this.grossAnnual,
    required this.es,
    required this.fr,
  });

  String _fmt(double v) =>
      NumberFormat.currency(symbol: '\$', decimalDigits: 0).format(v);

  @override
  Widget build(BuildContext context) {
    final title = fr
        ? 'Comparaison par état (Top 5)'
        : (es ? 'Comparar estados (Top 5)' : 'State Tax Comparison (Top 5)');
    final stateLabel = fr ? 'État' : (es ? 'Estado' : 'State');
    final stateTaxLabel =
        fr ? 'Impôt état' : (es ? 'Impuesto estatal' : 'State Tax');
    final totalTaxLabel =
        fr ? 'Total impôts' : (es ? 'Total impuestos' : 'Total Tax');
    final takeHomeLabel =
        fr ? 'Revenu net' : (es ? 'Ingreso neto' : 'Take-Home');

    // Compute federal tax once
    final federal = _kBrackets.fold(0.0, (sum, b) {
      final taxable =
          (grossAnnual - _kStandardDeduction).clamp(0.0, double.infinity);
      if (taxable <= b.min) return sum;
      final inBracket = (taxable - b.min).clamp(
          0.0, b.max == double.infinity ? double.infinity : b.max - b.min);
      return sum + inBracket * b.rate;
    });

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(Icons.location_city_rounded,
                  size: 18, color: AppTheme.primary),
              const SizedBox(width: AppSpacing.sm),
              Text(title,
                  style: TextStyle(
                      fontSize: AppTextSize.bodyMd,
                      fontWeight: FontWeight.w600)),
            ]),
            const SizedBox(height: AppSpacing.mdPlus),
            Table(
              columnWidths: const {
                0: FlexColumnWidth(2),
                1: FlexColumnWidth(2.5),
                2: FlexColumnWidth(2.5),
                3: FlexColumnWidth(2.5),
              },
              children: [
                TableRow(
                  decoration: BoxDecoration(
                      border:
                          Border(bottom: BorderSide(color: AppTheme.divider))),
                  children: [
                    _th(stateLabel),
                    _th(stateTaxLabel),
                    _th(totalTaxLabel),
                    _th(takeHomeLabel),
                  ],
                ),
                for (final s in _kTopStates)
                  () {
                    final stateTax = grossAnnual * s.rate;
                    final total = federal + stateTax;
                    final net = grossAnnual - total;
                    return TableRow(children: [
                      _td(s.code, bold: true),
                      _td(_fmt(stateTax),
                          color: s.rate == 0
                              ? AppTheme.success
                              : CalcwiseSemanticColors.warnIcon),
                      _td(_fmt(total), color: CalcwiseSemanticColors.errorDark),
                      _td(_fmt(net), color: AppTheme.success),
                    ]);
                  }(),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _th(String text) => Padding(
        padding: const EdgeInsets.only(bottom: AppSpacing.sm),
        child: Text(text,
            style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: AppTheme.labelGray)),
      );

  Widget _td(String text, {Color? color, bool bold = false}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Text(text,
            style: TextStyle(
                fontSize: AppTextSize.sm,
                fontWeight: bold ? FontWeight.bold : FontWeight.w500,
                color: color)),
      );
}

// ─── Teaser for non-premium users ─────────────────────────────────────────────

class _PremiumStateTeaser extends StatelessWidget {
  final bool es, fr;
  final BuildContext context;

  const _PremiumStateTeaser(
      {required this.es, required this.fr, required this.context});

  @override
  Widget build(BuildContext outerCtx) {
    final title = fr
        ? 'Comparaison par état — Premium'
        : (es
            ? 'Comparar estados — Premium'
            : 'State Tax Comparison — Premium');
    final desc = fr
        ? 'Voyez comment TX, FL, CA, NY, WA se comparent pour votre salaire.'
        : (es
            ? 'Compara TX, FL, CA, NY, WA para tu salario.'
            : 'See how TX, FL, CA, NY & WA compare for your salary.');
    final btnLabel = fr
        ? 'Débloquer Premium'
        : (es ? 'Desbloquear Premium' : 'Unlock Premium');

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(Icons.lock_outline, size: 18, color: AppTheme.primary),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                  child: Text(title,
                      style: TextStyle(
                          fontSize: AppTextSize.bodyMd,
                          fontWeight: FontWeight.w600))),
            ]),
            const SizedBox(height: AppSpacing.sm),
            Text(desc,
                style: TextStyle(
                    fontSize: AppTextSize.md, color: AppTheme.labelGray)),
            const SizedBox(height: AppSpacing.md),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => PaywallHard.show(outerCtx),
                child: Text(btnLabel),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
