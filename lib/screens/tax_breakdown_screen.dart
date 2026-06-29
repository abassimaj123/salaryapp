import 'package:flutter/material.dart';
import 'history_screen.dart' show HistoryScreen;
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../core/flavor_config.dart';
import '../core/theme/app_theme.dart';
import '../core/freemium/freemium_service.dart';
import '../core/freemium/iap_service.dart';
import '../core/analytics/analytics_service.dart';
import '../core/services/pdf_export_service.dart';
import '../main.dart' show isSpanishNotifier, salaryNotifier, historyService, paywallSession, adService;
import '../widgets/result_card.dart';
import '../widgets/save_scenario_button.dart';
import 'package:calcwise_core/calcwise_core.dart'
    show
        CalcwiseAdFooter,
        CalcwisePageEntrance,
        CalcwiseStaggerItem,
        CalcwisePremiumGate,
        CalcwiseTax,
        PaywallHard,
        PaywallSoft,
        PaywallTrigger,
        AppSpacing,
        AppRadius,
        AppTextSize,
        CalcwiseSemanticColors,
        ResultHasher;

// ─── Tax year ────────────────────────────────────────────────────────────────
// Federal/income-tax brackets and the tax-free allowance (standard deduction /
// basic personal amount / personal allowance) are sourced from the shared
// CalcwiseTax registry at this year — no longer hardcoded here — so this
// display can never diverge from the salary engine.

const int _kTaxYear = 2026;

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

/// The registry jurisdiction code whose income-tax bands drive the breakdown
/// for the active flavor.
String _jurisdictionForFlavor() {
  if (FlavorConfig.isCA) return 'ca_federal';
  if (FlavorConfig.isUK) return 'uk';
  return 'us_federal';
}

/// Income-tax brackets for the active flavor, derived from the CalcwiseTax
/// registry (2026). The registry's `bands[i].upTo` are cumulative taxable
/// ceilings (after the tax-free allowance); we expand them into [_Bracket]
/// `min`/`max` pairs to feed the existing breakdown widgets unchanged.
List<_Bracket> _bracketsForFlavor() {
  final set = CalcwiseTax.registry.annual(_jurisdictionForFlavor(), _kTaxYear);
  if (set == null) return const [];
  final out = <_Bracket>[];
  var lower = 0.0;
  for (final b in set.bands) {
    out.add(_Bracket(min: lower, max: b.upTo, rate: b.rate));
    lower = b.upTo;
  }
  return out;
}

/// The tax-free allowance (US standard deduction / CA basic personal amount /
/// UK personal allowance) for the active flavor, from the registry (2026).
double _deductionForFlavor() {
  final set = CalcwiseTax.registry.annual(_jurisdictionForFlavor(), _kTaxYear);
  return set?.basicPersonalAmount ?? 0;
}

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
    // Live auto-calc: recompute as the user edits the salary (no button needed).
    _salaryCtrl.addListener(() {
      if (mounted) _calculate();
    });
    // Sync salary when main calculator (Tab 1) updates salaryNotifier.
    salaryNotifier.addListener(_onMainSalaryChanged);
  }

  void _onMainSalaryChanged() {
    final salary = salaryNotifier.value;
    if (salary > 0 && mounted) {
      _salaryCtrl.text = salary.toStringAsFixed(0);
    }
  }

  @override
  void dispose() {
    salaryNotifier.removeListener(_onMainSalaryChanged);
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

  Future<void> _scheduleAutoSave() async {
    if (_grossAnnual == null || _brackets.isEmpty) return;
    historyService.scheduleAutoSave(
      appKey: 'salaryapp',
      screenId: 'tax_breakdown',
      inputHash: _buildHash(),
      l1: _buildL1(),
      l2: _buildL2(),
      onSaved: () {
        if (mounted) setState(() {});
        HistoryScreen.refreshNotifier.value++;
      },
    );
    try { AnalyticsService.instance.logSave(); } catch (_) {}
    try { AnalyticsService.instance.logResultSaved(); } catch (_) {}
    adService.onSave();
    final trigger = await paywallSession.recordAction();
    if (!mounted) return;
    if (trigger == PaywallTrigger.soft) PaywallSoft.show(context);
    if (trigger == PaywallTrigger.hard) PaywallHard.show(context);
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
        onUnlock: () => PaywallHard.show(context),
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
    HistoryScreen.refreshNotifier.value++;
    adService.onSave();
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
    analyticsService.logPdfExported();
  }

  void _calculate() {
    if (!_formKey.currentState!.validate()) return;
    final raw =
        _salaryCtrl.text.replaceAll(',', '').replaceAll(RegExp(r'[^\d.]'), '');
    final v = double.tryParse(raw) ?? 0;
    if (v > 0) {
      AnalyticsService.instance.maybeLogFirstCalculate();
      setState(() {
        _grossAnnual = v;
        _brackets = _computeBrackets(
            v, _bracketsForFlavor(), _deductionForFlavor());
      });
      _scheduleAutoSave();
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: isSpanishNotifier,
      builder: (context, useAlt, _) {
        final es = FlavorConfig.isUS && useAlt;
        final fr = FlavorConfig.isCA && useAlt;

        final year = '$_kTaxYear';
        final title = FlavorConfig.isCA
            ? (fr
                ? 'Tranches d\'imposition fédérale $year'
                : 'Federal Tax Brackets $year')
            : FlavorConfig.isUK
                ? 'Income Tax Bands $year'
                : (es
                    ? 'Tramos del impuesto $year'
                    : 'Tax Bracket Breakdown $year');

        return Scaffold(
          appBar: AppBar(title: Text(title)),
          body: GestureDetector(
            onTap: () => FocusScope.of(context).unfocus(),
            child: CalcwisePageEntrance(
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
                        if (_grossAnnual != null &&
                            _brackets.isNotEmpty) ...[
                          const SizedBox(height: AppSpacing.xxlPlus),
                          CalcwiseStaggerItem(
                            index: 0,
                            child: _TaxBreakdownSection(
                              grossAnnual: _grossAnnual!,
                              brackets: _brackets,
                              es: es,
                              fr: fr,
                            ),
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
          ),
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
            : (es ? 'Tramo por tramo' : '$_kTaxYear Federal Tax Brackets');
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
                    onUnlock: () => PaywallHard.show(context),
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
