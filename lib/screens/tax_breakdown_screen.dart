import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../core/flavor_config.dart';
import '../core/theme/app_theme.dart';
import '../core/freemium/freemium_service.dart';
import '../core/freemium/iap_service.dart';
import '../core/analytics/analytics_service.dart';
import '../core/services/pdf_export_service.dart';
import '../main.dart' show isSpanishNotifier, historyService, paywallSession;
import '../widgets/result_card.dart';
import '../widgets/save_scenario_button.dart';
import 'package:calcwise_core/calcwise_core.dart'
    show
        CalcwiseAdFooter,
        CalcwisePageEntrance,
        CalcwisePremiumGate,
        PaywallSoft,
        AppSpacing,
        AppRadius,
        AppTextSize,
        CalcwiseSemanticColors,
        ResultHasher;

// ─── Bracket model ───────────────────────────────────────────────────────────

class _Bracket {
  final double min, max, rate;
  const _Bracket({required this.min, required this.max, required this.rate});
}

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

// ─── US 2025 Federal Tax Brackets (single filer) ────────────────────────────

const _kUSStandardDeduction = 15000.0;

const _kUSBrackets = <_Bracket>[
  _Bracket(min: 0, max: 11925, rate: 0.10),
  _Bracket(min: 11925, max: 48475, rate: 0.12),
  _Bracket(min: 48475, max: 103350, rate: 0.22),
  _Bracket(min: 103350, max: 197300, rate: 0.24),
  _Bracket(min: 197300, max: 250525, rate: 0.32),
  _Bracket(min: 250525, max: 626350, rate: 0.35),
  _Bracket(min: 626350, max: double.infinity, rate: 0.37),
];

// ─── CA 2025 Federal Tax Brackets ───────────────────────────────────────────

const _kCABPA = 16129.0;

const _kCABrackets = <_Bracket>[
  _Bracket(min: 0, max: 55867, rate: 0.15),
  _Bracket(min: 55867, max: 111733, rate: 0.205),
  _Bracket(min: 111733, max: 154906, rate: 0.26),
  _Bracket(min: 154906, max: 220000, rate: 0.29),
  _Bracket(min: 220000, max: double.infinity, rate: 0.33),
];

// ─── UK 2025-26 Income Tax Brackets ─────────────────────────────────────────

const _kUKPersonalAllowance = 12570.0;

const _kUKBrackets = <_Bracket>[
  _Bracket(min: 0, max: 37700, rate: 0.20),
  _Bracket(min: 37700, max: 125140, rate: 0.40),
  _Bracket(min: 125140, max: double.infinity, rate: 0.45),
];

// ─── Province / State data ──────────────────────────────────────────────────

class _RegionTax {
  final String code, name;
  final double rate;
  const _RegionTax(
      {required this.code, required this.name, required this.rate});
}

const _kUSStates = <_RegionTax>[
  _RegionTax(code: 'TX', name: 'Texas', rate: 0.00),
  _RegionTax(code: 'FL', name: 'Florida', rate: 0.00),
  _RegionTax(code: 'WA', name: 'Washington', rate: 0.00),
  _RegionTax(code: 'NY', name: 'New York', rate: 0.109),
  _RegionTax(code: 'CA', name: 'California', rate: 0.133),
];

const _kCAProvinces = <_RegionTax>[
  _RegionTax(code: 'AB', name: 'Alberta', rate: 0.10),
  _RegionTax(code: 'BC', name: 'Colombie-Brit.', rate: 0.0770),
  _RegionTax(code: 'ON', name: 'Ontario', rate: 0.0505),
  _RegionTax(code: 'QC', name: 'Québec', rate: 0.14),
  _RegionTax(code: 'MB', name: 'Manitoba', rate: 0.108),
];

// ─── Bracket computation ────────────────────────────────────────────────────

List<_BracketResult> _computeBrackets(
    double grossAnnual, List<_Bracket> brackets, double deduction) {
  final taxable = (grossAnnual - deduction).clamp(0.0, double.infinity);
  final results = <_BracketResult>[];
  for (final b in brackets) {
    if (taxable <= b.min) break;
    final inBracket = (taxable - b.min).clamp(
        0.0, b.max == double.infinity ? double.infinity : b.max - b.min);
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

// ─── Flavor helpers ─────────────────────────────────────────────────────────

List<_Bracket> _bracketsForFlavor() {
  if (FlavorConfig.isCA) return _kCABrackets;
  if (FlavorConfig.isUK) return _kUKBrackets;
  return _kUSBrackets;
}

double _deductionForFlavor() {
  if (FlavorConfig.isCA) return _kCABPA;
  if (FlavorConfig.isUK) return _kUKPersonalAllowance;
  return _kUSStandardDeduction;
}

String _currencySymbol() {
  if (FlavorConfig.isCA) return 'CA\$';
  if (FlavorConfig.isUK) return '£';
  return '\$';
}

List<_RegionTax> _regionsForFlavor() {
  if (FlavorConfig.isCA) return _kCAProvinces;
  return _kUSStates;
}

// ─── Screen ─────────────────────────────────────────────────────────────────

class TaxBreakdownScreen extends StatefulWidget {
  final double? initialSalary;
  const TaxBreakdownScreen({super.key, this.initialSalary});

  @override
  State<TaxBreakdownScreen> createState() => _TaxBreakdownScreenState();
}

class _TaxBreakdownScreenState extends State<TaxBreakdownScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _salaryCtrl;

  double? _grossAnnual;
  List<_BracketResult> _brackets = [];

  @override
  void initState() {
    super.initState();
    final initial = widget.initialSalary;
    final defaultSalary = FlavorConfig.isUK ? '55000' : '75000';
    _salaryCtrl = TextEditingController(
      text: (initial != null && initial > 0)
          ? initial.toStringAsFixed(0)
          : defaultSalary,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      analyticsService.logScreenView('tax_breakdown');
      _calculate();
    });
  }

  @override
  void dispose() {
    historyService.cancelPendingSave('salaryapp', 'tax_breakdown');
    _salaryCtrl.dispose();
    super.dispose();
  }

  // ── SmartHistory helpers ──────────────────────────────────────────────────

  double _roundTo(double v, double step) => (v / step).round() * step;

  String _buildHash() {
    final gross = double.tryParse(
            _salaryCtrl.text.replaceAll(',', '').replaceAll(RegExp(r'[^\d.]'), '')) ??
        0;
    return ResultHasher.hashMixed({
      'flavor': FlavorConfig.flavor,
      'gross': _roundTo(gross, 1000),
    });
  }

  Map<String, dynamic> _buildL1() {
    final gross = _grossAnnual ?? 0;
    final totalFed = _brackets.fold(0.0, (s, b) => s + b.taxOwed);
    final effectiveRate = gross > 0 ? totalFed / gross * 100 : 0.0;
    final takeHome = gross - totalFed;
    return {
      'gross': gross,
      'federal_tax': totalFed,
      'effective_rate': effectiveRate,
      'take_home': takeHome,
    };
  }

  Map<String, dynamic> _buildL2() {
    final gross = _grossAnnual ?? 0;
    final totalFed = _brackets.fold(0.0, (s, b) => s + b.taxOwed);
    final deduction = _deductionForFlavor();
    return {
      'inputs': {'gross': gross, 'flavor': FlavorConfig.flavor},
      'results': {
        'federal_tax': totalFed,
        'taxable': (gross - deduction).clamp(0.0, double.infinity),
        'effective_rate_pct': gross > 0 ? totalFed / gross * 100 : 0.0,
        'take_home': gross - totalFed,
        'deduction': deduction,
      },
    };
  }

  void _scheduleAutoSave() {
    if (_grossAnnual == null || _brackets.isEmpty) return;
    historyService.scheduleAutoSave(
      appKey: 'salaryapp',
      screenId: 'tax_breakdown',
      inputHash: _buildHash(),
      l1: _buildL1(),
      l2: _buildL2(),
      onSaved: () { if (mounted) setState(() {}); },
    );
  }

  Future<void> _saveScenario(String? label) async {
    if (!freemiumService.hasFullAccess && !freemiumService.isRewarded) {
      final es = FlavorConfig.isUS && isSpanishNotifier.value;
      final fr = FlavorConfig.isCA && isSpanishNotifier.value;
      await PaywallSoft.show(
        context,
        isSpanish: es,
        isFrench: fr,
        featureTitle: fr
            ? 'Sauvegarder le scénario'
            : (es ? 'Guardar escenario' : 'Save Scenario'),
        featureSubtitle: fr
            ? 'Épinglez vos calculs pour les retrouver plus tard'
            : (es
                ? 'Fija tus cálculos para consultarlos más tarde'
                : 'Pin your calculations to revisit them later'),
        priceLabel: IAPService.instance.localizedPrice.value,
        onUnlock: () => IAPService.instance.buy(),
      );
      return;
    }
    if (_grossAnnual == null) return;
    await historyService.saveScenario(
      appKey: 'salaryapp',
      screenId: 'tax_breakdown',
      inputHash: _buildHash(),
      l1: _buildL1(),
      l2: _buildL2(),
      label: label,
    );
  }

  Future<void> _exportPdf(BuildContext context) async {
    if (_grossAnnual == null || _brackets.isEmpty) return;
    final es = FlavorConfig.isUS && isSpanishNotifier.value;
    final fr = FlavorConfig.isCA && isSpanishNotifier.value;
    await PdfExportService.exportTaxBreakdown(
      context: context,
      grossAnnual: _grossAnnual!,
      brackets: _brackets
          .map((b) => (
                min: b.min,
                max: b.max,
                rate: b.rate,
                amountInBracket: b.amountInBracket,
                taxOwed: b.taxOwed,
              ))
          .toList(),
      fr: fr,
      es: es,
    );
  }

  void _calculate() {
    if (!_formKey.currentState!.validate()) return;
    HapticFeedback.mediumImpact();
    FocusScope.of(context).unfocus();
    final raw =
        _salaryCtrl.text.replaceAll(',', '').replaceAll(RegExp(r'[^\d.]'), '');
    final v = double.tryParse(raw) ?? 0;
    if (v > 0) {
      setState(() {
        _grossAnnual = v;
        _brackets = _computeBrackets(
            v, _bracketsForFlavor(), _deductionForFlavor());
      });
      _scheduleAutoSave();
      paywallSession.recordAction();
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: isSpanishNotifier,
      builder: (context, useAlt, _) {
        final es = FlavorConfig.isUS && useAlt;
        final fr = FlavorConfig.isCA && useAlt;

        final year = '2025';
        final title = FlavorConfig.isCA
            ? (fr
                ? 'Tranches d\'imposition fédérale $year'
                : 'Federal Tax Brackets $year')
            : FlavorConfig.isUK
                ? 'Income Tax Bands $year'
                : (es
                    ? 'Tramos del impuesto $year'
                    : 'Tax Bracket Breakdown $year');
        final calcLabel = fr ? 'Calculer' : (es ? 'Calcular' : 'Calculate');

        return Scaffold(
          appBar: AppBar(title: Text(title)),
          body: CalcwisePageEntrance(
              child: Column(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _SalaryInput(
                            controller: _salaryCtrl, es: es, fr: fr),
                        const SizedBox(height: AppSpacing.lg),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: _calculate,
                            child: Text(calcLabel,
                                style: const TextStyle(
                                    fontSize: AppTextSize.bodyLg,
                                    fontWeight: FontWeight.w700)),
                          ),
                        ),
                        if (_grossAnnual != null &&
                            _brackets.isNotEmpty) ...[
                          const SizedBox(height: AppSpacing.xxlPlus),
                          _TaxBreakdownSection(
                            grossAnnual: _grossAnnual!,
                            brackets: _brackets,
                            es: es,
                            fr: fr,
                          ),
                          const SizedBox(height: AppSpacing.lg),
                          SaveScenarioButton(onSave: _saveScenario),
                          const SizedBox(height: AppSpacing.sm),
                          ValueListenableBuilder<bool>(
                            valueListenable:
                                freemiumService.hasFullAccessNotifier,
                            builder: (context, isPremium, _) {
                              final pdfLabel = fr
                                  ? 'Exporter PDF'
                                  : (es ? 'Exportar PDF' : 'Export PDF');
                              return SizedBox(
                                width: double.infinity,
                                child: OutlinedButton.icon(
                                  icon: Icon(isPremium
                                      ? Icons.picture_as_pdf_rounded
                                      : Icons.lock_outline_rounded),
                                  label: Text(pdfLabel),
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: AppTheme.primary,
                                    side: BorderSide(
                                        color: AppTheme.primary),
                                    padding: const EdgeInsets.symmetric(
                                        vertical: 14),
                                    shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(
                                            AppRadius.xl)),
                                  ),
                                  onPressed: () async {
                                    HapticFeedback.mediumImpact();
                                    if (!isPremium) {
                                      await PdfExportService.showUnlockOrPay(
                                        context,
                                        () => _exportPdf(context),
                                      );
                                    } else {
                                      await _exportPdf(context);
                                    }
                                  },
                                ),
                              );
                            },
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
          )),
        );
      },
    );
  }
}

// ─── Salary input ───────────────────────────────────────────────────────────

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
    final symbol = _currencySymbol();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: TextFormField(
          controller: controller,
          keyboardType:
              const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'[\d.,]')),
          ],
          decoration: InputDecoration(
            prefixText: '$symbol ',
            prefixStyle: const TextStyle(
                fontSize: AppTextSize.subtitle,
                fontWeight: FontWeight.w600),
            labelText: label,
            hintText: FlavorConfig.isUK ? '55000' : '75000',
          ),
          style: const TextStyle(
              fontSize: AppTextSize.subtitle, fontWeight: FontWeight.w600),
          validator: (v) {
            if (v == null || v.trim().isEmpty) {
              return fr ? 'Requis' : (es ? 'Requerido' : 'Required');
            }
            final val = double.tryParse(
                v.replaceAll(',', '').replaceAll(RegExp(r'[^\d.]'), ''));
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

// ─── Main breakdown section ─────────────────────────────────────────────────

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
        symbol: _currencySymbol(),
        decimalDigits: 0,
      ).format(v);

  String _fmt2(double v) => NumberFormat.currency(
        symbol: _currencySymbol(),
        decimalDigits: 2,
      ).format(v);

  @override
  Widget build(BuildContext context) {
    final deduction = _deductionForFlavor();
    final totalFederal = brackets.fold(0.0, (sum, b) => sum + b.taxOwed);
    final taxable = (grossAnnual - deduction).clamp(0.0, double.infinity);
    final effectiveRate =
        grossAnnual > 0 ? totalFederal / grossAnnual * 100 : 0.0;
    final takeHome = grossAnnual - totalFederal;

    // ── Labels ──────────────────────────────────────────────────────────────
    final deductionLabel = FlavorConfig.isCA
        ? (fr ? 'Montant personnel de base' : 'Basic Personal Amount')
        : FlavorConfig.isUK
            ? 'Personal Allowance'
            : (es
                ? 'Deducción estándar (soltero)'
                : 'Standard Deduction (Single)');
    final taxableLabel = fr
        ? 'Revenu imposable'
        : (es ? 'Ingreso imponible' : 'Taxable Income');
    final federalLabel = FlavorConfig.isCA
        ? (fr ? 'Impôt fédéral total' : 'Total Federal Tax')
        : FlavorConfig.isUK
            ? 'Total Income Tax'
            : (es ? 'Impuesto federal total' : 'Total Federal Tax');
    final effectiveLabel =
        fr ? 'Taux effectif' : (es ? 'Tasa efectiva' : 'Effective Rate');
    final takeHomeLabel = FlavorConfig.isCA
        ? (fr
            ? 'Revenu net (avant provincial/CPP/AE)'
            : 'Net (before provincial/CPP/EI)')
        : FlavorConfig.isUK
            ? 'Net (before NI)'
            : (es
                ? 'Take-home (antes de estado/FICA)'
                : 'Take-Home (before state/FICA)');
    final bracketsTitle = FlavorConfig.isCA
        ? (fr ? 'Tranche par tranche' : 'Bracket by Bracket')
        : FlavorConfig.isUK
            ? 'Tax Bands'
            : (es ? 'Tramo por tramo' : '2025 Federal Tax Brackets');
    final bracketLabel = fr ? 'Tranche' : (es ? 'Tramo' : 'Bracket');
    final rateLabel = fr ? 'Taux' : (es ? 'Tasa' : 'Rate');
    final inBracketLabel =
        fr ? 'Dans la tranche' : (es ? 'En el tramo' : 'In Bracket');
    final taxOwedLabel = fr ? 'Impôt dû' : (es ? 'Impuesto' : 'Tax Owed');
    final netPayLabel = fr ? 'Salaire net' : (es ? 'Neto' : 'Net pay');

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
              child:
                  ResultCard(label: takeHomeLabel, value: _fmt(takeHome))),
        ]),
        const SizedBox(height: AppSpacing.smPlus),
        Row(children: [
          Expanded(
              child: ResultCard(
                  label: deductionLabel, value: _fmt(deduction))),
          const SizedBox(width: AppSpacing.smPlus),
          Expanded(
              child: ResultCard(label: taxableLabel, value: _fmt(taxable))),
        ]),
        const SizedBox(height: AppSpacing.xl),

        // Progress bar visualization
        _BracketProgressBar(
            brackets: brackets,
            grossAnnual: grossAnnual,
            es: es,
            fr: fr,
            netPayLabel: netPayLabel),
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
                      style: const TextStyle(
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
                              bottom:
                                  BorderSide(color: AppTheme.divider))),
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
                          _td('${_currencySymbol()}${_shortNum(b.min)}–${b.max == double.infinity ? '∞' : '${_currencySymbol()}${_shortNum(b.max)}'}'),
                          _td(_rateFmt(b.rate),
                              color: _bracketColor(
                                  b.rate, Theme.of(context).brightness)),
                          _td(_fmt2(b.amountInBracket)),
                          _td(_fmt2(b.taxOwed),
                              color: CalcwiseSemanticColors.error(
                                  Theme.of(context).brightness)),
                        ],
                      ),
                    TableRow(
                      decoration: BoxDecoration(
                          border: Border(
                              top: BorderSide(color: AppTheme.divider))),
                      children: [
                        _td('Total', bold: true),
                        _td(''),
                        _td(''),
                        _td(_fmt2(totalFederal),
                            bold: true,
                            color: CalcwiseSemanticColors.error(
                                Theme.of(context).brightness)),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.lg),

        // Premium: region comparison (US: states, CA: provinces)
        if (!FlavorConfig.isUK)
          ValueListenableBuilder<bool>(
            valueListenable: freemiumService.hasFullAccessNotifier,
            builder: (context, isPremium, _) => isPremium
                ? _RegionComparisonCard(
                    grossAnnual: grossAnnual, es: es, fr: fr)
                : CalcwisePremiumGate(
                    title: FlavorConfig.isCA
                        ? (fr
                            ? 'Comparaison par province'
                            : 'Province Tax Comparison')
                        : (es
                            ? 'Comparar estados'
                            : 'State Tax Comparison'),
                    description: FlavorConfig.isCA
                        ? (fr
                            ? 'Comparez l\'impôt provincial entre AB, BC, ON, QC et MB.'
                            : 'Compare provincial tax across AB, BC, ON, QC & MB.')
                        : (es
                            ? 'Compara TX, FL, CA, NY, WA para tu salario.'
                            : 'See how TX, FL, CA, NY & WA compare for your salary.'),
                    onUnlock: () => IAPService.instance.buy(),
                    price: IAPService.instance.localizedPrice,
                  ),
          ),
      ],
    );
  }

  String _shortNum(double v) {
    if (v >= 1000000) return '${(v / 1000000).toStringAsFixed(1)}M';
    if (v >= 1000) return '${(v / 1000).toStringAsFixed(0)}k';
    return v.toStringAsFixed(0);
  }

  String _rateFmt(double rate) {
    final pct = rate * 100;
    return pct == pct.roundToDouble()
        ? '${pct.toStringAsFixed(0)}%'
        : '${pct.toStringAsFixed(1)}%';
  }

  Color _bracketColor(double rate, Brightness b) {
    if (rate <= 0.15) return CalcwiseSemanticColors.success(b);
    if (rate <= 0.22) return CalcwiseSemanticColors.warnIcon;
    if (rate <= 0.29) return CalcwiseSemanticColors.alert(b);
    return CalcwiseSemanticColors.error(b);
  }

  Widget _th(String text) => Padding(
        padding: const EdgeInsets.only(bottom: AppSpacing.sm),
        child: Text(text,
            style: TextStyle(
                fontSize: AppTextSize.xs,
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

// ─── Stacked progress bar ───────────────────────────────────────────────────

class _BracketProgressBar extends StatelessWidget {
  final List<_BracketResult> brackets;
  final double grossAnnual;
  final bool es, fr;
  final String netPayLabel;

  const _BracketProgressBar({
    required this.brackets,
    required this.grossAnnual,
    this.es = false,
    this.fr = false,
    required this.netPayLabel,
  });

  Color _color(double rate) {
    if (rate <= 0.15) return CalcwiseSemanticColors.successDeep;
    if (rate <= 0.22) return CalcwiseSemanticColors.premiumGold;
    if (rate <= 0.29) return CalcwiseSemanticColors.warnIcon;
    if (rate <= 0.35) return CalcwiseSemanticColors.alertText;
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
              Icon(Icons.bar_chart_rounded,
                  size: 18, color: AppTheme.primary),
              const SizedBox(width: AppSpacing.sm),
              Text(
                  fr
                      ? 'Visualisation fiscale'
                      : (es
                          ? 'Visualización fiscal'
                          : 'Tax Visualization'),
                  style: const TextStyle(
                      fontSize: AppTextSize.bodyMd,
                      fontWeight: FontWeight.w600)),
            ]),
            const SizedBox(height: AppSpacing.lg),
            ClipRRect(
              borderRadius: BorderRadius.circular(AppRadius.md),
              child: SizedBox(
                height: 28,
                child: Row(
                  children: [
                    Flexible(
                      flex: (takeHome / total * 1000).round(),
                      child: Container(color: AppTheme.success),
                    ),
                    for (final b in brackets)
                      Flexible(
                        flex:
                            (b.taxOwed / total * 1000).round().clamp(1, 1000),
                        child: Container(color: _color(b.rate)),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Wrap(
              spacing: 12,
              runSpacing: 6,
              children: [
                _legendItem(AppTheme.success, netPayLabel),
                for (final b in brackets)
                  _legendItem(_color(b.rate),
                      '${(b.rate * 100).toStringAsFixed(b.rate * 100 == (b.rate * 100).roundToDouble() ? 0 : 1)}%'),
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
            decoration:
                BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: AppSpacing.xs),
          Text(label,
              style: TextStyle(
                  fontSize: AppTextSize.xs, color: AppTheme.labelGray)),
        ],
      );
}

// ─── Premium: Region tax comparison (US: states, CA: provinces) ─────────────

class _RegionComparisonCard extends StatelessWidget {
  final double grossAnnual;
  final bool es, fr;

  const _RegionComparisonCard({
    required this.grossAnnual,
    required this.es,
    required this.fr,
  });

  String _fmt(double v) => NumberFormat.currency(
        symbol: _currencySymbol(),
        decimalDigits: 0,
      ).format(v);

  @override
  Widget build(BuildContext context) {
    final isCA = FlavorConfig.isCA;
    final regions = _regionsForFlavor();
    final title = isCA
        ? (fr
            ? 'Comparaison par province (Top 5)'
            : 'Provincial Tax Comparison (Top 5)')
        : (es ? 'Comparar estados (Top 5)' : 'State Tax Comparison (Top 5)');
    final regionLabel =
        isCA ? (fr ? 'Prov.' : 'Prov.') : (es ? 'Estado' : 'State');
    final regionTaxLabel = isCA
        ? (fr ? 'Impôt prov.' : 'Prov. Tax')
        : (es ? 'Impuesto estatal' : 'State Tax');
    final totalTaxLabel =
        fr ? 'Total impôts' : (es ? 'Total impuestos' : 'Total Tax');
    final takeHomeLabel =
        fr ? 'Revenu net' : (es ? 'Ingreso neto' : 'Take-Home');

    // Compute federal tax
    final deduction = _deductionForFlavor();
    final brackets = _bracketsForFlavor();
    final federalResults = _computeBrackets(grossAnnual, brackets, deduction);
    final federal = federalResults.fold(0.0, (sum, b) => sum + b.taxOwed);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(
                  isCA
                      ? Icons.map_rounded
                      : Icons.location_city_rounded,
                  size: 18,
                  color: AppTheme.primary),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(title,
                    style: const TextStyle(
                        fontSize: AppTextSize.bodyMd,
                        fontWeight: FontWeight.w600)),
              ),
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
                      border: Border(
                          bottom: BorderSide(color: AppTheme.divider))),
                  children: [
                    _th(regionLabel),
                    _th(regionTaxLabel),
                    _th(totalTaxLabel),
                    _th(takeHomeLabel),
                  ],
                ),
                for (final r in regions)
                  () {
                    final regionTax = grossAnnual * r.rate;
                    final total = federal + regionTax;
                    final net = grossAnnual - total;
                    return TableRow(children: [
                      _td(r.code, bold: true),
                      _td(_fmt(regionTax),
                          color: r.rate == 0
                              ? AppTheme.success
                              : CalcwiseSemanticColors.warnIcon),
                      _td(_fmt(total),
                          color: CalcwiseSemanticColors.error(
                              Theme.of(context).brightness)),
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
                fontSize: AppTextSize.xs,
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
