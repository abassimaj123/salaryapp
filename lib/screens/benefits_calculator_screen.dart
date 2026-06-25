import 'dart:isolate';
import 'dart:typed_data';

import 'package:intl/date_symbol_data_local.dart';
import 'package:flutter/material.dart';
import 'history_screen.dart' show HistoryScreen;
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../core/flavor_config.dart';
import '../core/freemium/freemium_service.dart';
import '../core/freemium/iap_service.dart';
import '../core/theme/app_theme.dart';
import '../core/analytics/analytics_service.dart';
import '../main.dart' show isSpanishNotifier, salaryNotifier, historyService, paywallSession, adService;
import '../widgets/result_card.dart';
import '../widgets/save_scenario_button.dart';
import 'package:calcwise_core/calcwise_core.dart'
    show
        AmountFormatter,
        CalcwiseAdFooter,
        CalcwiseHeroCard,
        CalcwisePageEntrance,
        CalcwisePremiumGate,
        CurrencyInputFormatter,
        PaywallHard,
        PaywallSoft,
        AppDuration,
        AppSpacing,
        AppRadius,
        AppTextSize,
        PaywallTrigger,
        ResultHasher;

// ─── Isolate param + top-level function ──────────────────────────────────────

class _BenefitsPdfParams {
  final double baseSalary, healthAnnual, retirementAnnual, ptoAnnual,
      remoteAnnual, otherAnnual, totalBenefits, totalCompensation;
  final String currencySymbol, retirementLabel, dateStr;
  final bool fr, es, isUK;
  const _BenefitsPdfParams({
    required this.baseSalary,
    required this.healthAnnual,
    required this.retirementAnnual,
    required this.ptoAnnual,
    required this.remoteAnnual,
    required this.otherAnnual,
    required this.totalBenefits,
    required this.totalCompensation,
    required this.currencySymbol,
    required this.retirementLabel,
    required this.dateStr,
    required this.fr,
    required this.es,
    required this.isUK,
  });
}

Future<Uint8List> _buildBenefitsPdfBytes(_BenefitsPdfParams p) async {
  await initializeDateFormatting();
  final symbol = p.currencySymbol;
  final fmtCur = NumberFormat.currency(symbol: symbol, decimalDigits: 0);

  pw.Widget row(String label, String value, {bool bold = false}) => pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 3),
        child: pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(label,
                style: const pw.TextStyle(fontSize: AppTextSize.sm)),
            pw.Text(value,
                style: pw.TextStyle(
                    fontSize: AppTextSize.sm,
                    fontWeight:
                        bold ? pw.FontWeight.bold : pw.FontWeight.normal)),
          ],
        ),
      );

  final doc = pw.Document();
  doc.addPage(pw.Page(
    build: (ctx) => pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          p.fr
              ? 'Rapport de rémunération globale'
              : p.es
                  ? 'Informe de compensación total'
                  : 'Total Compensation Report',
          style: pw.TextStyle(
              fontSize: AppTextSize.title, fontWeight: pw.FontWeight.bold),
        ),
        pw.SizedBox(height: 4),
        pw.Text(p.dateStr,
            style: const pw.TextStyle(fontSize: AppTextSize.xs)),
        pw.Divider(height: 24),
        row(
            p.fr
                ? 'Salaire de base'
                : p.es
                    ? 'Salario base'
                    : 'Base Salary',
            fmtCur.format(p.baseSalary)),
        pw.Divider(height: 16),
        pw.Text(
            p.fr
                ? 'Valeur des avantages sociaux'
                : p.es
                    ? 'Valor de beneficios laborales'
                    : 'Benefits Value',
            style: pw.TextStyle(
                fontSize: AppTextSize.sm, fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 6),
        row(
            p.fr
                ? 'Assurance santé (annuelle)'
                : p.es
                    ? 'Seguro de salud (anual)'
                    : (p.isUK
                        ? 'Private Health Insurance (annual)'
                        : 'Health Insurance (annual)'),
            fmtCur.format(p.healthAnnual)),
        row(p.retirementLabel, fmtCur.format(p.retirementAnnual)),
        row(
            p.fr
                ? 'Valeur des congés payés'
                : p.es
                    ? 'Valor de vacaciones pagadas'
                    : (p.isUK ? 'Annual Leave Value' : 'PTO Value'),
            fmtCur.format(p.ptoAnnual)),
        if (p.remoteAnnual > 0)
          row(
              p.fr
                  ? 'Économies télétravail (annuelles)'
                  : p.es
                      ? 'Ahorro trabajo remoto (anual)'
                      : 'Remote Work Savings (annual)',
              fmtCur.format(p.remoteAnnual)),
        if (p.otherAnnual > 0)
          row(
              p.fr
                  ? 'Autres avantages'
                  : p.es
                      ? 'Otros beneficios'
                      : 'Other Perks',
              fmtCur.format(p.otherAnnual)),
        pw.Divider(height: 16),
        row(
            p.fr
                ? 'Total des avantages sociaux'
                : p.es
                    ? 'Total beneficios'
                    : 'Total Benefits Value',
            fmtCur.format(p.totalBenefits),
            bold: true),
        pw.SizedBox(height: 8),
        row(
            p.fr
                ? 'Rémunération globale'
                : p.es
                    ? 'Compensación total'
                    : 'Total Compensation',
            fmtCur.format(p.totalCompensation),
            bold: true),
        pw.SizedBox(height: 20),
        pw.Text(
          p.fr
              ? '* Estimations à titre informatif uniquement. Ceci n\'est pas un conseil financier.'
              : p.es
                  ? '* Estimaciones con fines informativos únicamente. No es asesoramiento financiero.'
                  : '* Estimates for informational purposes only. Not financial advice.',
          style: const pw.TextStyle(fontSize: 8),
        ),
      ],
    ),
  ));
  return await doc.save();
}

// ─── Benefits Value Calculator ────────────────────────────────────────────────
//
// Calculates the total monetary value of employer benefits and adds it to the
// base salary to produce a Total Compensation figure.
//
// Flavor-specific labels:
//   US  → 401(k) Match  | USD
//   CA  → RRSP Match    | CAD
//   UK  → Pension Contribution | GBP

class BenefitsCalculatorScreen extends StatefulWidget {
  const BenefitsCalculatorScreen({super.key});

  @override
  State<BenefitsCalculatorScreen> createState() =>
      _BenefitsCalculatorScreenState();
}

class _BenefitsCalculatorScreenState extends State<BenefitsCalculatorScreen> {
  // ── Controllers ────────────────────────────────────────────────────────────
  late final TextEditingController _salaryCtrl;
  final _healthCtrl = TextEditingController(text: '500');
  final _retirementPctCtrl = TextEditingController(text: '4');
  final _ptoDaysCtrl = TextEditingController(text: '15');
  final _remoteCtrl = TextEditingController(text: '0');
  final _otherCtrl = TextEditingController(text: '0');

  // ── Results ────────────────────────────────────────────────────────────────
  _BenefitsResult? _result;
  bool _hasCalculated = false;

  @override
  void initState() {
    super.initState();
    final salary = salaryNotifier.value;
    _salaryCtrl =
        TextEditingController(text: salary > 0 ? salary.toStringAsFixed(0) : (FlavorConfig.isUK ? '55000' : '75000'));

    // Auto-calculate on load for all users (free users see gated results)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      analyticsService.logScreenView('benefits_calculator');
      _calculate();
    });
    for (final c in [_salaryCtrl, _healthCtrl, _retirementPctCtrl, _ptoDaysCtrl, _remoteCtrl, _otherCtrl]) {
      c.addListener(() { if (mounted) _calculate(); });
    }
  }

  @override
  void dispose() {
    historyService.cancelPendingSave('salaryapp', 'benefits');
    _salaryCtrl.dispose();
    _healthCtrl.dispose();
    _retirementPctCtrl.dispose();
    _ptoDaysCtrl.dispose();
    _remoteCtrl.dispose();
    _otherCtrl.dispose();
    super.dispose();
  }

  // ── SmartHistory helpers ──────────────────────────────────────────────────

  double _roundTo(double v, double step) => (v / step).round() * step;

  String _buildHash() {
    final salary = _parse(_salaryCtrl);
    final health = _parse(_healthCtrl);
    final retPct = _parse(_retirementPctCtrl);
    final pto = _parse(_ptoDaysCtrl);
    return ResultHasher.hashMixed({
      'flavor': FlavorConfig.flavor,
      'salary': _roundTo(salary, 1000),
      'health': _roundTo(health, 50),
      'ret_pct': _roundTo(retPct, 0.25),
      'pto': pto.round(),
    });
  }

  Map<String, dynamic> _buildL1() {
    final r = _result;
    if (r == null) return {};
    return {
      'base_salary': r.baseSalary,
      'total_benefits': r.totalBenefits,
      'total_compensation': r.totalCompensation,
      'benefits_pct': r.baseSalary > 0 ? (r.totalBenefits / r.baseSalary * 100) : 0.0,
    };
  }

  Map<String, dynamic> _buildL2() {
    final r = _result;
    if (r == null) return {};
    return {
      'inputs': {
        'base_salary': r.baseSalary,
        'health_monthly': _parse(_healthCtrl),
        'retirement_pct': _parse(_retirementPctCtrl),
        'pto_days': _parse(_ptoDaysCtrl),
        'remote_monthly': _parse(_remoteCtrl),
        'other_annual': _parse(_otherCtrl),
        'flavor': FlavorConfig.flavor,
      },
      'results': {
        'health_annual': r.healthAnnual,
        'retirement_annual': r.retirementAnnual,
        'pto_annual': r.ptoAnnual,
        'remote_annual': r.remoteAnnual,
        'other_annual': r.otherAnnual,
        'total_benefits': r.totalBenefits,
        'total_compensation': r.totalCompensation,
      },
    };
  }

  Future<void> _scheduleAutoSave() async {
    if (_result == null) return;
    historyService.scheduleAutoSave(
      appKey: 'salaryapp',
      screenId: 'benefits',
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
    if (_result == null) return;
    await historyService.saveScenario(
      appKey: 'salaryapp',
      screenId: 'benefits',
      inputHash: _buildHash(),
      l1: _buildL1(),
      l2: _buildL2(),
      label: label,
    );
    HistoryScreen.refreshNotifier.value++;
    adService.onSave();
  }

  double _parse(TextEditingController c) {
    final raw = c.text.replaceAll(',', '').replaceAll(RegExp(r'[^\d.]'), '');
    return double.tryParse(raw) ?? 0;
  }

  void _calculate() {
    final salary = _parse(_salaryCtrl);
    final healthMonthly = _parse(_healthCtrl);
    final retirementPct = _parse(_retirementPctCtrl);
    final ptoDays = _parse(_ptoDaysCtrl);
    final remoteMonthly = _parse(_remoteCtrl);
    final otherAnnual = _parse(_otherCtrl);

    if (salary <= 0) return;

    AnalyticsService.instance.maybeLogFirstCalculate();

    final healthAnnual = healthMonthly * 12;
    final retirementAnnual = salary * retirementPct / 100;
    // PTO value = salary / 260 * number of PTO days
    final ptoAnnual = salary / 260.0 * ptoDays;
    final remoteAnnual = remoteMonthly * 12;

    final totalBenefits =
        healthAnnual + retirementAnnual + ptoAnnual + remoteAnnual + otherAnnual;
    final totalCompensation = salary + totalBenefits;

    setState(() {
      _result = _BenefitsResult(
        baseSalary: salary,
        healthAnnual: healthAnnual,
        retirementAnnual: retirementAnnual,
        ptoAnnual: ptoAnnual,
        remoteAnnual: remoteAnnual,
        otherAnnual: otherAnnual,
        totalBenefits: totalBenefits,
        totalCompensation: totalCompensation,
      );
      _hasCalculated = true;
    });
    analyticsService.logCalculationCompleted();
    _scheduleAutoSave();
  }

  Future<void> _checkPaywall() async {
    final trigger = await paywallSession.recordAction();
    if (!mounted) return;
    if (trigger == PaywallTrigger.soft) PaywallSoft.show(context);
    if (trigger == PaywallTrigger.hard) PaywallHard.show(context);
  }

  Future<void> _sharePdf(BuildContext context, _BenefitsResult r, bool fr,
      bool es) async {
    final retLabel = _retirementLabel(fr, es);
    // Format date on the MAIN isolate — worker isolates don't inherit
    // initializeDateFormatting(), so formatting 'fr'/'es' there would throw.
    final dateStr = DateFormat('MMMM d, yyyy', fr ? 'fr' : (es ? 'es' : 'en'))
        .format(DateTime.now());
    final bytes = await Isolate.run(() => _buildBenefitsPdfBytes(
          _BenefitsPdfParams(
            baseSalary: r.baseSalary,
            healthAnnual: r.healthAnnual,
            retirementAnnual: r.retirementAnnual,
            ptoAnnual: r.ptoAnnual,
            remoteAnnual: r.remoteAnnual,
            otherAnnual: r.otherAnnual,
            totalBenefits: r.totalBenefits,
            totalCompensation: r.totalCompensation,
            currencySymbol: FlavorConfig.currencySymbol,
            retirementLabel: retLabel,
            dateStr: dateStr,
            fr: fr,
            es: es,
            isUK: FlavorConfig.isUK,
          ),
        ));
    await Printing.sharePdf(
        bytes: bytes,
        filename:
            'total_compensation_${DateTime.now().millisecondsSinceEpoch}.pdf');
  }

  String _retirementLabel(bool fr, bool es) {
    if (FlavorConfig.isCA) return fr ? 'Cotisation REER employeur' : 'RRSP Match';
    if (FlavorConfig.isUK) return 'Pension Contribution';
    return es ? 'Aportación 401(k) empleador' : '401(k) Match';
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

        final symbol = FlavorConfig.currencySymbol;
        final retLabel = _retirementLabel(fr, es);

        return Scaffold(
          appBar: AppBar(
            title: Text(t(
              'Benefits Value Calculator',
              'Calculadora de beneficios',
              'Calculateur d\'avantages',
            )),
          ),
          body: GestureDetector(
            onTap: () => FocusScope.of(context).unfocus(),
            child: CalcwisePageEntrance(
              child: Column(
            children: [
              Expanded(
                child: SingleChildScrollView(
                      padding: EdgeInsets.fromLTRB(
                        AppSpacing.lg,
                        AppSpacing.lg,
                        AppSpacing.lg,
                        AppSpacing.lg +
                            MediaQuery.of(context).padding.bottom +
                            AppSpacing.xl,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            t(
                              'Enter your employer\'s benefit contributions to calculate your true total compensation.',
                              'Ingresa las contribuciones de beneficios de tu empleador para calcular tu compensación total real.',
                              'Entrez les contributions d\'avantages sociaux de votre employeur pour calculer votre rémunération globale réelle.',
                            ),
                            style: TextStyle(
                              fontSize: AppTextSize.md,
                              color: AppTheme.labelGray,
                            ),
                          ),
                          const SizedBox(height: AppSpacing.md),

                          // ── Input card ─────────────────────────────────────
                          Card(
                            child: Padding(
                              padding: const EdgeInsets.all(AppSpacing.lg),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    t('Your Salary', 'Tu salario',
                                        'Votre salaire'),
                                    style: TextStyle(
                                      fontSize: AppTextSize.md,
                                      fontWeight: FontWeight.w600,
                                      color: AppTheme.labelGray,
                                    ),
                                  ),
                                  const SizedBox(height: AppSpacing.sm),
                                  TextFormField(
                                    controller: _salaryCtrl,
                                    keyboardType:
                                        const TextInputType.numberWithOptions(
                                            decimal: true),
                                    textInputAction: TextInputAction.next,
                                    inputFormatters: [
                                      CurrencyInputFormatter(
                                          locale: FlavorConfig.isCA
                                              ? 'en_CA'
                                              : (FlavorConfig.isUK ? 'en_GB' : 'en_US')),
                                    ],
                                    decoration: InputDecoration(
                                      labelText: t('Base Annual Salary',
                                          'Salario anual base',
                                          'Salaire annuel de base'),
                                      prefixText: '$symbol ',
                                      hintText: '75000',
                                    ),
                                    style: const TextStyle(
                                        fontSize: AppTextSize.bodyLg,
                                        fontWeight: FontWeight.w600),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: AppSpacing.sm),

                          // ── Benefits inputs ────────────────────────────────
                          Card(
                            child: Padding(
                              padding: const EdgeInsets.all(AppSpacing.lg),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    t('Employer Benefits',
                                        'Beneficios del empleador',
                                        'Avantages employeur'),
                                    style: TextStyle(
                                      fontSize: AppTextSize.md,
                                      fontWeight: FontWeight.w600,
                                      color: AppTheme.labelGray,
                                    ),
                                  ),
                                  const SizedBox(height: AppSpacing.sm),

                                  // Health Insurance
                                  TextFormField(
                                    controller: _healthCtrl,
                                    keyboardType:
                                        const TextInputType.numberWithOptions(
                                            decimal: true),
                                    textInputAction: TextInputAction.next,
                                    inputFormatters: [
                                      FilteringTextInputFormatter.allow(
                                          RegExp(r'[\d.,]')),
                                    ],
                                    decoration: InputDecoration(
                                      labelText: FlavorConfig.isUK
                                          ? 'Private Health Insurance (employer contribution)'
                                          : t(
                                              'Health Insurance (employer contribution)',
                                              'Seguro de salud (contribución empleador)',
                                              'Assurance santé (contribution employeur)',
                                            ),
                                      prefixText: '$symbol ',
                                      hintText: '400',
                                      helperText:
                                          t('/month', '/mes', '/mois'),
                                    ),
                                  ),
                                  const SizedBox(height: AppSpacing.sm),

                                  // Retirement match %
                                  TextFormField(
                                    controller: _retirementPctCtrl,
                                    keyboardType:
                                        const TextInputType.numberWithOptions(
                                            decimal: true),
                                    textInputAction: TextInputAction.next,
                                    inputFormatters: [
                                      FilteringTextInputFormatter.allow(
                                          RegExp(r'[\d.,]')),
                                    ],
                                    decoration: InputDecoration(
                                      labelText: retLabel,
                                      suffixText: '%',
                                      hintText: '4',
                                      helperText: t(
                                          '% of base salary',
                                          '% del salario base',
                                          '% du salaire de base'),
                                    ),
                                  ),
                                  const SizedBox(height: AppSpacing.sm),

                                  // PTO days
                                  TextFormField(
                                    controller: _ptoDaysCtrl,
                                    keyboardType:
                                        const TextInputType.numberWithOptions(
                                            decimal: true),
                                    textInputAction: TextInputAction.next,
                                    inputFormatters: [
                                      FilteringTextInputFormatter.allow(
                                          RegExp(r'[\d.,]')),
                                    ],
                                    decoration: InputDecoration(
                                      labelText: FlavorConfig.isUK
                                          ? 'Annual Leave Days'
                                          : t('PTO Days', 'Días de vacaciones',
                                              'Jours de congé payé'),
                                      hintText: '15',
                                      helperText: t(
                                          'Value = salary ÷ 260 × days',
                                          'Valor = salario ÷ 260 × días',
                                          'Valeur = salaire ÷ 260 × jours'),
                                    ),
                                  ),
                                  const SizedBox(height: AppSpacing.sm),

                                  // Remote savings
                                  TextFormField(
                                    controller: _remoteCtrl,
                                    keyboardType:
                                        const TextInputType.numberWithOptions(
                                            decimal: true),
                                    textInputAction: TextInputAction.next,
                                    inputFormatters: [
                                      FilteringTextInputFormatter.allow(
                                          RegExp(r'[\d.,]')),
                                    ],
                                    decoration: InputDecoration(
                                      labelText: t(
                                        'Remote Work Savings (optional)',
                                        'Ahorro trabajo remoto (opcional)',
                                        'Économies télétravail (facultatif)',
                                      ),
                                      prefixText: '$symbol ',
                                      hintText: '0',
                                      helperText:
                                          t('/month', '/mes', '/mois'),
                                    ),
                                  ),
                                  const SizedBox(height: AppSpacing.sm),

                                  // Other perks
                                  TextFormField(
                                    controller: _otherCtrl,
                                    keyboardType:
                                        const TextInputType.numberWithOptions(
                                            decimal: true),
                                    textInputAction: TextInputAction.done,
                                    inputFormatters: [
                                      FilteringTextInputFormatter.allow(
                                          RegExp(r'[\d.,]')),
                                    ],
                                    decoration: InputDecoration(
                                      labelText: t(
                                        'Other Perks (optional)',
                                        'Otros beneficios (opcional)',
                                        'Autres avantages (facultatif)',
                                      ),
                                      prefixText: '$symbol ',
                                      hintText: '0',
                                      helperText:
                                          t('/year', '/año', '/an'),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          // ── Results ────────────────────────────────────────
                          if (_hasCalculated && _result != null) ...[
                            const SizedBox(height: AppSpacing.xl),
                            if (freemiumService.hasFullAccess)
                              _buildResults(context, _result!, fr, es, symbol,
                                  retLabel, t)
                            else ...[
                              // Show hero card as preview
                              Container(
                                margin: const EdgeInsets.only(top: AppSpacing.lg),
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(28),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.3),
                                      blurRadius: 8,
                                      offset: const Offset(0, 4),
                                    ),
                                  ],
                                ),
                                child: CalcwiseHeroCard(
                                label: t(
                                  'Total Compensation',
                                  'Compensación total',
                                  'Rémunération globale',
                                ),
                                value: NumberFormat.currency(
                                        symbol: symbol, decimalDigits: 0)
                                    .format(_result!.totalCompensation),
                                secondary: t(
                                  'Salary + Benefits / year',
                                  'Salario + Beneficios / año',
                                  'Salaire + Avantages / an',
                                ),
                                rawValue: _result!.totalCompensation,
                                valueFormatter: (v) => AmountFormatter.ui(v, FlavorConfig.currencyCode),
                                gradient: LinearGradient(
                                  colors: [
                                    AppTheme.primary,
                                    AppTheme.primary
                                        .withValues(alpha: 0.75),
                                  ],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                ),
                              ),
                              ),
                              const SizedBox(height: AppSpacing.sm),
                              CalcwisePremiumGate(
                                title: t(
                                  'Full Benefits Report',
                                  'Informe completo',
                                  'Rapport complet des avantages',
                                ),
                                description: t(
                                  'Detailed breakdown, PDF export, and benefits as % of salary.',
                                  'Desglose detallado, exportación PDF y beneficios como % del salario.',
                                  'Détail complet, export PDF et avantages en % du salaire.',
                                ),
                                onUnlock: () => PaywallHard.show(context),
                                price: IAPService.instance.localizedPrice,
                              ),
                            ],
                          ],

                          const SizedBox(height: AppSpacing.lg),
                        ],
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

  Widget _buildResults(
    BuildContext context,
    _BenefitsResult r,
    bool fr,
    bool es,
    String symbol,
    String retLabel,
    String Function(String, String, String) t,
  ) {
    final fmtCur =
        NumberFormat.currency(symbol: symbol, decimalDigits: 0);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Hero: Total Compensation
        CalcwiseHeroCard(
          label: t(
            'Total Compensation',
            'Compensación total',
            'Rémunération globale',
          ),
          value: fmtCur.format(r.totalCompensation),
          secondary: t(
            'Salary + Benefits / year',
            'Salario + Beneficios / año',
            'Salaire + Avantages / an',
          ),
          rawValue: r.totalCompensation,
          valueFormatter: (v) => AmountFormatter.ui(v, FlavorConfig.currencyCode),
          rawStats: [
            (label: t('Base Salary', 'Salario base', 'Salaire de base'), value: r.baseSalary, formatter: (v) => AmountFormatter.ui(v, FlavorConfig.currencyCode)),
            (label: t('Total Benefits', 'Total beneficios', 'Total avantages'), value: r.totalBenefits, formatter: (v) => AmountFormatter.ui(v, FlavorConfig.currencyCode)),
          ],
          gradient: LinearGradient(
            colors: [
              AppTheme.primary,
              AppTheme.primary.withValues(alpha: 0.75),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),

        // Benefits breakdown card
        Card(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              children: [
                MetricRow(
                  label: t('Base Salary', 'Salario base', 'Salaire de base'),
                  value: fmtCur.format(r.baseSalary),
                  valueColor: AppTheme.primary,
                ),
                const Divider(height: 20),
                Text(
                  t('Benefits Breakdown', 'Desglose de beneficios',
                      'Détail des avantages'),
                  style: TextStyle(
                    fontSize: AppTextSize.md,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.labelGray,
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                if (r.healthAnnual > 0)
                  MetricRow(
                    label: FlavorConfig.isUK
                        ? 'Private Health Insurance (annual)'
                        : t('Health Insurance (annual)',
                            'Seguro de salud (anual)',
                            'Assurance santé (annuelle)'),
                    value: fmtCur.format(r.healthAnnual),
                    valueColor: AppTheme.success,
                  ),
                MetricRow(
                  label: retLabel,
                  value: fmtCur.format(r.retirementAnnual),
                  valueColor: AppTheme.success,
                ),
                MetricRow(
                  label: FlavorConfig.isUK
                      ? 'Annual Leave Value'
                      : t('PTO Value', 'Valor vacaciones', 'Valeur congés'),
                  value: fmtCur.format(r.ptoAnnual),
                  valueColor: AppTheme.success,
                ),
                if (r.remoteAnnual > 0)
                  MetricRow(
                    label: t('Remote Savings (annual)',
                        'Ahorro remoto (anual)',
                        'Économies télétravail (annuel)'),
                    value: fmtCur.format(r.remoteAnnual),
                    valueColor: AppTheme.success,
                  ),
                if (r.otherAnnual > 0)
                  MetricRow(
                    label: t('Other Perks', 'Otros beneficios',
                        'Autres avantages'),
                    value: fmtCur.format(r.otherAnnual),
                    valueColor: AppTheme.success,
                  ),
                const Divider(height: 20),
                MetricRow(
                  label: t('Total Benefits Value', 'Valor total de beneficios',
                      'Valeur totale des avantages sociaux'),
                  value: fmtCur.format(r.totalBenefits),
                  valueColor: AppTheme.success,
                ),
                MetricRow(
                  label: t('Total Compensation', 'Compensación total',
                      'Rémunération globale'),
                  value: fmtCur.format(r.totalCompensation),
                  valueColor: AppTheme.primary,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),

        // Benefits as % of salary
        _BenefitsPercentCard(result: r, fr: fr, es: es, symbol: symbol),

        const SizedBox(height: AppSpacing.md),

        // PDF export button
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            icon: const Icon(Icons.picture_as_pdf_rounded),
            label: Text(t(
                'Export PDF Report', 'Exportar informe PDF',
                'Exporter rapport PDF')),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppTheme.primary,
              side: BorderSide(color: AppTheme.primary),
              padding:
                  const EdgeInsets.symmetric(vertical: AppSpacing.smPlus),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppRadius.xl)),
            ),
            onPressed: () => _sharePdf(context, r, fr, es),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Text(
            t(
              '* Estimates only. Consult HR or a financial advisor for exact benefit values.',
              '* Solo estimaciones. Consulta a RR.HH. o a un asesor financiero para valores exactos.',
              '* Estimations uniquement. Consultez les RH ou un conseiller financier pour des valeurs exactes.',
            ),
            style: TextStyle(
              fontSize: AppTextSize.xs,
              color: AppTheme.labelGray,
              fontStyle: FontStyle.italic,
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        SaveScenarioButton(onSave: _saveScenario),
      ],
    );
  }
}

// ─── Benefits % of salary card ────────────────────────────────────────────────

class _BenefitsPercentCard extends StatelessWidget {
  final _BenefitsResult result;
  final bool fr, es;
  final String symbol;

  const _BenefitsPercentCard({
    required this.result,
    required this.fr,
    required this.es,
    required this.symbol,
  });

  @override
  Widget build(BuildContext context) {
    final pct = result.baseSalary > 0
        ? (result.totalBenefits / result.baseSalary * 100)
        : 0.0;
    final title = fr
        ? 'Avantages en % du salaire'
        : (es ? 'Beneficios como % del salario' : 'Benefits as % of Salary');
    final pctLabel = fr
        ? 'Vos avantages représentent ${pct.toStringAsFixed(1)} % de votre salaire'
        : (es
            ? 'Tus beneficios representan el ${pct.toStringAsFixed(1)} % de tu salario'
            : 'Your benefits represent ${pct.toStringAsFixed(1)}% of your base salary');

    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppTheme.primary.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(AppRadius.xl),
        border: Border.all(color: AppTheme.primary.withValues(alpha: 0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.pie_chart_rounded, color: AppTheme.primary, size: 18),
              const SizedBox(width: 8),
              Text(title,
                  style: TextStyle(
                      fontSize: AppTextSize.bodyMd,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.primary)),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            pctLabel,
            style: TextStyle(
                fontSize: AppTextSize.md, color: AppTheme.labelGray),
          ),
          const SizedBox(height: AppSpacing.sm),
          ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.full),
            child: LinearProgressIndicator(
              value: (pct / 100).clamp(0.0, 1.0),
              minHeight: 8,
              backgroundColor: AppTheme.divider,
              valueColor: AlwaysStoppedAnimation<Color>(AppTheme.primary),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Result model ─────────────────────────────────────────────────────────────

class _BenefitsResult {
  final double baseSalary;
  final double healthAnnual;
  final double retirementAnnual;
  final double ptoAnnual;
  final double remoteAnnual;
  final double otherAnnual;
  final double totalBenefits;
  final double totalCompensation;

  const _BenefitsResult({
    required this.baseSalary,
    required this.healthAnnual,
    required this.retirementAnnual,
    required this.ptoAnnual,
    required this.remoteAnnual,
    required this.otherAnnual,
    required this.totalBenefits,
    required this.totalCompensation,
  });
}
