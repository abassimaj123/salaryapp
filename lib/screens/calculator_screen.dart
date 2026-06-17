import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'history_screen.dart' show HistoryScreen;
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:calcwise_core/calcwise_core.dart' hide PaywallHard;
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';
import '../core/services/pdf_export_service.dart' show PdfExportService;

import '../core/analytics/analytics_service.dart';
import '../core/flavor_config.dart';
import '../core/salary_engine.dart';
import '../core/local_taxes.dart';
import '../widgets/sankey_chart.dart';
import '../widgets/save_scenario_button.dart';
import '../main.dart' show adService, historyService;
import '../core/freemium/freemium_service.dart';
import '../core/freemium/iap_service.dart';
import '../main.dart' show paywallSession;
import '../core/theme/app_theme.dart';
import '../widgets/paywall_hard.dart';
import '../l10n/strings_en.dart';
import '../l10n/strings_es.dart';
import '../l10n/strings_fr.dart';
import '../widgets/result_card.dart';
import '../widgets/insight_card.dart';
import '../core/insight_engine.dart';
import '../main.dart'
    show
        isSpanishNotifier,
        salaryNotifier,
        ukStudentLoanNotifier,
        ukScotlandNotifier;

// ─── Pay-frequency enum ───────────────────────────────────────────────────────

enum PayFrequency { annual, monthly, biWeekly, weekly, hourly }

extension _FreqLabel on PayFrequency {
  String label(bool useAlt) {
    final es = FlavorConfig.isUS && useAlt;
    final fr = FlavorConfig.isCA && useAlt;
    switch (this) {
      case PayFrequency.annual:
        return fr ? 'Annuel' : (es ? 'Anual' : 'Annual');
      case PayFrequency.monthly:
        return fr ? 'Mensuel' : (es ? 'Mensual' : 'Monthly');
      case PayFrequency.biWeekly:
        return fr ? 'Bimensuel' : (es ? 'Quincenal' : 'Bi-weekly');
      case PayFrequency.weekly:
        return fr ? 'Hebdo' : (es ? 'Semanal' : 'Weekly');
      case PayFrequency.hourly:
        return fr ? 'Horaire' : (es ? 'Por hora' : 'Hourly');
    }
  }

  /// Convert frequency amount to gross annual salary.
  double toAnnual(double amount) {
    switch (this) {
      case PayFrequency.annual:
        return amount;
      case PayFrequency.monthly:
        return amount * 12;
      case PayFrequency.biWeekly:
        return amount * 26;
      case PayFrequency.weekly:
        return amount * 52;
      case PayFrequency.hourly:
        return amount * 40 * 52;
    }
  }
}

// ─── Isolate params + top-level PDF builders ─────────────────────────────────

class _SalaryAnalysisPdfParams {
  final double grossAnnual, federalTax, ficaTax, stateTax, totalTax, netAnnual,
      netMonthly, effectiveRate;
  final String currencySymbol, dateStr;
  final String federalLabel, ficaLabel, stateLabel, grossLabel, netLabel,
      totalLabel, rateLabel, monthLabel, titleText;
  final bool hasFica, hasState;
  const _SalaryAnalysisPdfParams({
    required this.grossAnnual,
    required this.federalTax,
    required this.ficaTax,
    required this.stateTax,
    required this.totalTax,
    required this.netAnnual,
    required this.netMonthly,
    required this.effectiveRate,
    required this.currencySymbol,
    required this.dateStr,
    required this.federalLabel,
    required this.ficaLabel,
    required this.stateLabel,
    required this.grossLabel,
    required this.netLabel,
    required this.totalLabel,
    required this.rateLabel,
    required this.monthLabel,
    required this.titleText,
    required this.hasFica,
    required this.hasState,
  });
}

Future<Uint8List> _buildSalaryAnalysisPdfBytes(
    _SalaryAnalysisPdfParams p) async {
  final fmtCurrency =
      NumberFormat.currency(symbol: p.currencySymbol, decimalDigits: 2);
  String fmtPct(double v) => '${v.toStringAsFixed(1)}%';

  pw.Widget pdfRow(String label, String value) => pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 4),
        child: pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(label, style: const pw.TextStyle(fontSize: AppTextSize.sm)),
            pw.Text(value,
                style: pw.TextStyle(
                    fontSize: AppTextSize.sm, fontWeight: pw.FontWeight.bold)),
          ],
        ),
      );

  final doc = pw.Document();
  doc.addPage(pw.Page(
    build: (ctx) => pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(p.titleText,
            style: pw.TextStyle(
                fontSize: AppTextSize.titleMd,
                fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 4),
        pw.Text(p.dateStr,
            style: const pw.TextStyle(fontSize: AppTextSize.xs)),
        pw.Divider(height: 20),
        pdfRow(p.grossLabel, fmtCurrency.format(p.grossAnnual)),
        pdfRow(p.federalLabel, fmtCurrency.format(p.federalTax)),
        if (p.hasFica) pdfRow(p.ficaLabel, fmtCurrency.format(p.ficaTax)),
        if (p.hasState) pdfRow(p.stateLabel, fmtCurrency.format(p.stateTax)),
        pdfRow(p.totalLabel, fmtCurrency.format(p.totalTax)),
        pdfRow(p.rateLabel, fmtPct(p.effectiveRate)),
        pw.Divider(height: 20),
        pdfRow(p.netLabel, fmtCurrency.format(p.netAnnual)),
        pdfRow(p.monthLabel, fmtCurrency.format(p.netMonthly)),
      ],
    ),
  ));
  return await doc.save();
}

class _TotalCompPdfParams {
  final double grossAnnual, federalTax, ficaTax, stateTax, totalTax, netAnnual,
      healthAnnual, retirementAnnual, ptoAnnual, totalBenefits, totalComp;
  final String currencySymbol, dateStr;
  final String federalLabel, ficaLabel, stateLabel, retLabel, titleText;
  final bool hasFica, hasState, isUK, fr, es;
  const _TotalCompPdfParams({
    required this.grossAnnual,
    required this.federalTax,
    required this.ficaTax,
    required this.stateTax,
    required this.totalTax,
    required this.netAnnual,
    required this.healthAnnual,
    required this.retirementAnnual,
    required this.ptoAnnual,
    required this.totalBenefits,
    required this.totalComp,
    required this.currencySymbol,
    required this.dateStr,
    required this.federalLabel,
    required this.ficaLabel,
    required this.stateLabel,
    required this.retLabel,
    required this.titleText,
    required this.hasFica,
    required this.hasState,
    required this.isUK,
    required this.fr,
    required this.es,
  });
}

Future<Uint8List> _buildTotalCompPdfBytes(_TotalCompPdfParams p) async {
  final fmtCur = NumberFormat.currency(symbol: p.currencySymbol, decimalDigits: 0);
  final fmtCur2 = NumberFormat.currency(symbol: p.currencySymbol, decimalDigits: 2);

  pw.Widget pdfRow(String label, String value, {bool bold = false}) =>
      pw.Padding(
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
        pw.Divider(height: 20),
        pw.Text(
          p.fr
              ? 'Analyse salariale'
              : (p.es ? 'Análisis salarial' : 'Salary Breakdown'),
          style: pw.TextStyle(
              fontSize: AppTextSize.sm, fontWeight: pw.FontWeight.bold),
        ),
        pw.SizedBox(height: 6),
        pdfRow(
            p.fr
                ? 'Salaire brut'
                : (p.es ? 'Salario bruto' : 'Gross Salary'),
            fmtCur.format(p.grossAnnual)),
        pdfRow(p.federalLabel, fmtCur.format(p.federalTax)),
        if (p.hasFica) pdfRow(p.ficaLabel, fmtCur.format(p.ficaTax)),
        if (p.hasState) pdfRow(p.stateLabel, fmtCur.format(p.stateTax)),
        pdfRow(
            p.fr
                ? 'Total impôts'
                : (p.es ? 'Total impuestos' : 'Total Tax'),
            fmtCur.format(p.totalTax)),
        pdfRow(
            p.fr ? 'Salaire net' : (p.es ? 'Salario neto' : 'Net Salary'),
            fmtCur2.format(p.netAnnual)),
        pw.Divider(height: 20),
        pw.Text(
          p.fr
              ? 'Avantages (hypothèses par défaut)'
              : p.es
                  ? 'Beneficios (hipótesis por defecto)'
                  : 'Benefits (default assumptions)',
          style: pw.TextStyle(
              fontSize: AppTextSize.sm, fontWeight: pw.FontWeight.bold),
        ),
        pw.SizedBox(height: 6),
        pdfRow(
            p.fr
                ? 'Assurance santé (annuelle)'
                : p.es
                    ? 'Seguro de salud (anual)'
                    : (p.isUK
                        ? 'Private Health Insurance (annual)'
                        : 'Health Insurance (annual)'),
            fmtCur.format(p.healthAnnual)),
        pdfRow(p.retLabel, fmtCur.format(p.retirementAnnual)),
        pdfRow(
            p.fr
                ? 'Valeur congés payés (15 j)'
                : p.es
                    ? 'Valor vacaciones (15 días)'
                    : (p.isUK
                        ? 'Annual Leave Value (15 days)'
                        : 'PTO Value (15 days)'),
            fmtCur.format(p.ptoAnnual)),
        pw.Divider(height: 20),
        pdfRow(
            p.fr
                ? 'Total des avantages sociaux'
                : p.es
                    ? 'Total beneficios'
                    : 'Total Benefits Value',
            fmtCur.format(p.totalBenefits),
            bold: true),
        pdfRow(
            p.fr
                ? 'Rémunération globale'
                : p.es
                    ? 'Compensación total'
                    : 'Total Compensation',
            fmtCur.format(p.totalComp),
            bold: true),
        pw.SizedBox(height: 20),
        pw.Text(
          p.fr
              ? '* Avantages basés sur des hypothèses moyennes du marché. Pour des valeurs exactes, utilisez le Calculateur d\'avantages sociaux.'
              : p.es
                  ? '* Beneficios basados en supuestos promedio del mercado. Para valores exactos usa la Calculadora de beneficios.'
                  : '* Benefits based on mid-market assumptions. For exact values, use the Benefits Value Calculator.',
          style: const pw.TextStyle(fontSize: 8),
        ),
      ],
    ),
  ));
  return await doc.save();
}

// ─── Shared formatters (flavor-constant, allocated once) ─────────────────────

// These are module-level finals: FlavorConfig values are constant per app
// flavor so a single formatter instance is safe to reuse across rebuilds.
final _currencyFmt2 = NumberFormat.currency(
  symbol: FlavorConfig.currencySymbol,
  decimalDigits: 2,
);
final _currencyFmt0 = NumberFormat.currency(
  symbol: FlavorConfig.currencySymbol,
  decimalDigits: 0,
);
// Flavor-aware currency formatter — used by COL comparison
final _dollarFmt0 = NumberFormat.currency(symbol: FlavorConfig.currencySymbol, decimalDigits: 0);

// RegExp used in _calculate() — allocated once instead of on every call
final _nonDigitDot = RegExp(r'[^\d.]');

// ─── Screen ───────────────────────────────────────────────────────────────────

class CalculatorScreen extends StatefulWidget {
  const CalculatorScreen({super.key});
  @override
  State<CalculatorScreen> createState() => _CalculatorScreenState();
}

class _CalculatorScreenState extends State<CalculatorScreen>
    with CalcwiseAutoCalcMixin {
  final _formKey = GlobalKey<FormState>();
  final _salaryCtrl = TextEditingController(text: '75,000');
  final _scrollCtrl = ScrollController();
  final _salarySacrificeCtrl = TextEditingController(text: '0');
  final _secondIncomeCtrl = TextEditingController(text: '0');
  // UK HMRC tax code — defaults to the standard 2025/26 code (1257L).
  final _ukTaxCodeCtrl = TextEditingController(text: '1257L');

  static const _kProvinceKey = 'salary_ca_province';

  PayFrequency _frequency = PayFrequency.annual;
  String _usState = 'CA';
  // Loaded from SharedPreferences or detected from device locale in initState.
  String _caProvince = 'ON';
  String? _usCity; // local-tax city key (see local_taxes.dart)
  SalaryResult? _result;
  double _localTax = 0; // computed local-tax amount (US only)
  bool _showResults = false;

  // CA reverse-calculation mode
  bool _caReverseMode = false; // false = gross→net, true = net→gross
  double? _caRequiredGross; // result of reverse calc

  // UK reverse-calculation mode (net → gross), mirroring the CA feature.
  bool _ukReverseMode = false;
  double? _ukRequiredGross; // result of UK reverse calc

  // UK HMRC tax code (parsed in _calculate); defaults to standard 1257L.
  UkTaxCode _ukTaxCode = UkTaxCode.standard;

  // UK salary sacrifice
  double _salarySacrifice = 0; // £/year pre-tax deduction

  // UK student-loan plan selection (1, 2, 4, 5) — used when student loan is on.
  int _ukLoanPlan = 2;
  // UK Postgraduate (Plan 3) loan — cumulable with a main plan.
  bool _ukPostgrad = false;
  // UK auto-enrolment pension (qualifying earnings, 5% employee min).
  bool _ukAutoEnrolment = false;

  // Multi-jobs / second income (premium feature, all flavors).
  bool _addSecondIncome = false;
  double _secondIncome = 0; // annual gross of the additional job

  Timer? _saveDebounce;

  @override
  void initState() {
    super.initState();
    analyticsService.logScreenView('calculator');
    _salaryCtrl.addListener(() => _scheduleCalcAndSave());

    // Load saved province (or auto-detect from device locale on first install).
    if (FlavorConfig.isCA) _loadSavedProvince();

    // Trigger initial calculation only — skip save to avoid paywall on cold start.
    WidgetsBinding.instance
        .addPostFrameCallback((_) => scheduleCalc(_calculate));
  }

  /// Loads the saved province from SharedPreferences.
  /// Falls back to device locale detection on first install (fr → QC, else → ON).
  Future<void> _loadSavedProvince() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_kProvinceKey);
    if (!mounted) return;
    if (saved != null && saved.isNotEmpty) {
      setState(() => _caProvince = saved);
    } else {
      // First install: detect from device locale
      final locale = WidgetsBinding.instance.platformDispatcher.locale;
      final detected = locale.languageCode == 'fr' ? 'QC' : 'ON';
      setState(() => _caProvince = detected);
      await prefs.setString(_kProvinceKey, detected);
    }
    // Re-trigger calc with the correct province
    scheduleCalc(_calculate);
  }

  /// Persists the selected province so it's remembered across sessions.
  Future<void> _saveProvince(String province) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kProvinceKey, province);
  }

  /// Schedule calc (via mixin) + SmartHistory auto-save (debounced internally).
  /// Called from user interactions (listener, chips, toggles) — never from initState.
  void _scheduleCalcAndSave() {
    scheduleCalc(_calculate);
    // SmartHistory debounces the auto-save itself (ring buffer). We just need
    // the latest result available — _calculate() runs synchronously above so
    // schedule the auto-save after a short delay using the freshest _result.
    _saveDebounce?.cancel();
    _saveDebounce = Timer(const Duration(milliseconds: 300), () {
      if (mounted && _result != null) _scheduleAutoSave(_result!);
    });
  }

  @override
  void dispose() {
    _saveDebounce?.cancel();
    historyService.cancelPendingSave('salaryapp', 'calculator');
    _salaryCtrl.removeListener(() => _scheduleCalcAndSave());
    _salaryCtrl.dispose();
    _salarySacrificeCtrl.dispose();
    _secondIncomeCtrl.dispose();
    _ukTaxCodeCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  // ── SmartHistory: hash + payload builders ──────────────────────────────────

  String get _region =>
      FlavorConfig.isUS ? _usState : (FlavorConfig.isCA ? _caProvince : '');

  /// Deterministic hash of the key scenario inputs (rounded).
  String _scenarioHash(SalaryResult res) {
    final inputs = <String, dynamic>{
      'flavor': FlavorConfig.flavor,
      'region': _region,
      'gross': ResultHasher.roundTo(res.grossAnnual, 100),
    };
    if (FlavorConfig.isUS && _usCity != null) inputs['city'] = _usCity;
    if (FlavorConfig.isUK) {
      inputs['scotland'] = ukScotlandNotifier.value;
      inputs['sl'] = ukStudentLoanNotifier.value ? _ukLoanPlan : 0;
      inputs['pg'] = _ukPostgrad;
      inputs['ae'] = _ukAutoEnrolment;
      inputs['sacrifice'] = ResultHasher.roundTo(_salarySacrifice, 100);
      inputs['taxcode'] = _ukTaxCodeCtrl.text.trim().toUpperCase();
      inputs['reverse'] = _ukReverseMode;
    }
    if (FlavorConfig.isCA) inputs['reverse'] = _caReverseMode;
    if (_addSecondIncome) {
      inputs['second'] = ResultHasher.roundTo(_secondIncome, 100);
    }
    return ResultHasher.hashMixed(inputs);
  }

  Map<String, dynamic> _buildL1(SalaryResult res) => {
        'gross': res.grossAnnual,
        'net': res.netAnnual,
        'region': _region,
        'effective_rate': res.effectiveRate,
        'total_tax': res.totalTax,
      };

  Map<String, dynamic> _buildL2(SalaryResult res) => {
        'inputs': {
          'gross': res.grossAnnual,
          'flavor': FlavorConfig.flavor,
          'region': _region,
        },
        'results': res.toMap(),
      };

  /// Debounced ring-buffer auto-save via SmartHistoryService.
  void _scheduleAutoSave(SalaryResult res) {
    historyService.scheduleAutoSave(
      appKey: 'salaryapp',
      screenId: 'calculator',
      inputHash: _scenarioHash(res),
      l1: _buildL1(res),
      l2: _buildL2(res),
      onSaved: () {
        if (mounted) setState(() {});
        HistoryScreen.refreshNotifier.value++;
      },
    );
    adService.onSave();
    try {
      analyticsService.logSave();
      analyticsService.logResultSaved();
    } catch (_) {}
    paywallSession.recordAction().ignore();
  }

  /// Pin the current scenario (Save Scenario button).
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
    final res = _result;
    if (res == null) return;
    await historyService.saveScenario(
      appKey: 'salaryapp',
      screenId: 'calculator',
      inputHash: _scenarioHash(res),
      l1: _buildL1(res),
      l2: _buildL2(res),
      label: label,
    );
    try {
      analyticsService.logResultSaved();
    } catch (_) {}
    paywallSession.recordAction().ignore();
  }

  // ── Actions ──────────────────────────────────────────────────────────────

  void _calculate() {
    if (!_formKey.currentState!.validate()) return;

    final rawText = _salaryCtrl.text;
    // Strip ALL thousand-separator variants: ASCII comma, non-breaking space (fr_CA),
    // narrow non-breaking space. Never replace ',' with '.' — dot stays decimal.
    final raw = rawText.replaceAll(RegExp(r'[,    ]'), '');
    final input = double.tryParse(raw.replaceAll(_nonDigitDot, '')) ?? 0;
    final inputAnnual = _frequency.toAnnual(input);

    if (inputAnnual <= 0) return;

    // Second income (premium) — cumulated for tax across all flavors.
    final secondIncome = _addSecondIncome ? _secondIncome : 0.0;

    SalaryResult res;
    double? requiredGross;

    if (FlavorConfig.isUS) {
      res = UsSalaryEngine.calculate(inputAnnual, _usState,
          secondIncome: secondIncome);
    } else if (FlavorConfig.isUK) {
      // Parse the HMRC tax code (defaults to 1257L on empty/invalid input).
      final taxCode = UkTaxCode.parse(_ukTaxCodeCtrl.text);
      _ukTaxCode = taxCode;
      if (_ukReverseMode) {
        // Reverse: the entered amount is the desired take-home; solve for gross.
        // No second income in reverse mode (the target net is for one income).
        final targetNet = inputAnnual;
        final gross = UkSalaryEngine.grossFromNet(
          targetNet,
          studentLoan: ukStudentLoanNotifier.value,
          loanPlan: _ukLoanPlan,
          postgradLoan: _ukPostgrad,
          scotland: ukScotlandNotifier.value,
          salarySacrifice: _salarySacrifice,
          autoEnrolment: _ukAutoEnrolment,
          taxCode: taxCode,
        );
        res = UkSalaryEngine.calculate(
          gross,
          studentLoan: ukStudentLoanNotifier.value,
          loanPlan: _ukLoanPlan,
          postgradLoan: _ukPostgrad,
          scotland: ukScotlandNotifier.value,
          salarySacrifice: _salarySacrifice,
          autoEnrolment: _ukAutoEnrolment,
          taxCode: taxCode,
        );
        requiredGross = gross;
      } else {
        res = UkSalaryEngine.calculate(
          inputAnnual,
          studentLoan: ukStudentLoanNotifier.value,
          loanPlan: _ukLoanPlan,
          postgradLoan: _ukPostgrad,
          scotland: ukScotlandNotifier.value,
          salarySacrifice: _salarySacrifice,
          autoEnrolment: _ukAutoEnrolment,
          secondIncome: secondIncome,
          taxCode: taxCode,
        );
      }
    } else {
      // CA: reverse mode computes the gross needed to achieve target net
      if (_caReverseMode) {
        final targetNet = inputAnnual;
        final gross = CaSalaryEngine.grossFromNet(targetNet, _caProvince);
        res = CaSalaryEngine.calculate(gross, _caProvince);
        requiredGross = gross;
      } else {
        res = CaSalaryEngine.calculate(inputAnnual, _caProvince,
            secondIncome: secondIncome);
      }
    }

    // Local (city) tax — US only, applied flat to gross.
    double localTax = 0;
    if (FlavorConfig.isUS && _usCity != null && localTaxes[_usCity] != null) {
      localTax = res.grossAnnual * localTaxes[_usCity]!.rate;
    }

    salaryNotifier.value = res.grossAnnual;

    setState(() {
      _result = res;
      _localTax = localTax;
      _showResults = true;
      _caRequiredGross = FlavorConfig.isCA ? requiredGross : null;
      _ukRequiredGross = FlavorConfig.isUK ? requiredGross : null;
    });

    // Emotional trigger: good annual net salary → ask for review
    if (res.netAnnual > 50000) {
      CalcwiseReviewService.instance.requestAfterPremium();
    }

    // Log analytics calculation event
    analyticsService.logCalculation(
      grossSalary: res.grossAnnual,
      netSalary: res.netAnnual,
      frequency: _frequency.name,
    );
    analyticsService.logCalculationCompleted(params: {
      'gross_salary': res.grossAnnual.round(),
      'net_salary': res.netAnnual.round(),
      'frequency': _frequency.name,
    });
    analyticsService.maybeLogFirstCalculate();

    // No auto-scroll: the results section appears below the input card;
    // the user scrolls manually. Auto-scrolling caused results to go off-screen.
  }

  void _reset() {
    setState(() {
      _salaryCtrl.clear();
      _result = null;
      _showResults = false;
      _frequency = PayFrequency.annual;
      _caRequiredGross = null;
      _ukRequiredGross = null;
      _ukReverseMode = false;
      _ukTaxCode = UkTaxCode.standard;
      _ukTaxCodeCtrl.text = '1257L';
      _salarySacrifice = 0;
      _salarySacrificeCtrl.text = '0';
      _addSecondIncome = false;
      _secondIncome = 0;
      _secondIncomeCtrl.text = '0';
      _ukPostgrad = false;
      _ukAutoEnrolment = false;
    });
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: isSpanishNotifier,
      builder: (context, useAlt, _) {
        final es = FlavorConfig.isUS && useAlt;
        final fr = FlavorConfig.isCA && useAlt;

        String resetLabel, resultsLabel;
        if (fr) {
          resetLabel = AppStringsFR.reset;
          resultsLabel = AppStringsFR.results;
        } else if (es) {
          resetLabel = AppStringsES.reset;
          resultsLabel = AppStringsES.results;
        } else {
          resetLabel = AppStringsEN.reset;
          resultsLabel = AppStringsEN.results;
        }

        final appBarTitle = FlavorConfig.isUK
            ? 'UK Salary Calculator'
            : (FlavorConfig.isCA
                ? (fr ? 'Calculateur de salaire CA' : 'CA Salary Calculator')
                : (es ? 'Calculadora US' : 'US Salary Calculator'));

        return Scaffold(
          appBar: AppBar(
            title: Text(appBarTitle),
            actions: [
              IconButton(
                icon: const Icon(Icons.refresh_rounded),
                tooltip: resetLabel,
                onPressed: _showResults ? _reset : null,
              ),
            ],
          ),
          body: GestureDetector(
            onTap: () => FocusScope.of(context).unfocus(),
            child: Column(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    controller: _scrollCtrl,
                    padding: const EdgeInsets.all(AppSpacing.lg),
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 600),
                        child: Form(
                          key: _formKey,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              AnimatedSwitcher(
                                duration: AppDuration.base,
                                switchInCurve: Curves.easeOut,
                                transitionBuilder: (child, animation) =>
                                    FadeTransition(
                                  opacity: animation,
                                  child: SlideTransition(
                                    position: Tween<Offset>(
                                      begin: const Offset(0, 0.04),
                                      end: Offset.zero,
                                    ).animate(animation),
                                    child: child,
                                  ),
                                ),
                                child: (_showResults && _result != null)
                                    ? KeyedSubtree(
                                        key: const ValueKey('results'),
                                        child: CalcwisePageEntrance(child: Padding(
                                          padding:
                                              const EdgeInsets.only(top: 24),
                                          child: _ResultsSection(
                                            result: _result!,
                                            localTax: _localTax,
                                            localTaxLabel: (_usCity != null &&
                                                    localTaxes[_usCity] != null)
                                                ? localTaxes[_usCity]!.name
                                                : null,
                                            label: resultsLabel,
                                            useAlt: useAlt,
                                            es: es,
                                            fr: fr,
                                            caReverseMode: _caReverseMode,
                                            caRequiredGross: _caRequiredGross,
                                            ukReverseMode: _ukReverseMode,
                                            ukRequiredGross: _ukRequiredGross,
                                            ukTaxCode: _ukTaxCode,
                                            ukSalarySacrifice: _salarySacrifice,
                                            onSaveScenario: _saveScenario,
                                          ),
                                        )),
                                      )
                                    : const KeyedSubtree(
                                        key: ValueKey('empty'),
                                        child: SizedBox.shrink(),
                                      ),
                              ),
                              CalcwiseStaggerItem(
                                  index: 0,
                                  child: _SalaryInputCard(
                                    controller: _salaryCtrl,
                                    frequency: _frequency,
                                    useAlt: useAlt,
                                    es: es,
                                    fr: fr,
                                  )),
                              SizedBox(height: AppSpacing.md),
                              CalcwiseStaggerItem(
                                  index: 1,
                                  child: Column(children: [
                                    _FrequencyChips(
                                      selected: _frequency,
                                      useAlt: useAlt,
                                      onChanged: (f) {
                                        HapticFeedback.selectionClick();
                                        setState(() => _frequency = f);
                                        _scheduleCalcAndSave();
                                      },
                                    ),
                                    if (FlavorConfig.isUS) ...[
                                      SizedBox(height: AppSpacing.md),
                                      Row(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Expanded(
                                            child: _StateDropdown(
                                              value: _usState,
                                              useAlt: useAlt,
                                              onChanged: (v) {
                                                setState(() {
                                                  _usState = v!;
                                                  // Reset city when state changes; new
                                                  // state may not have the previously-
                                                  // selected city.
                                                  _usCity = null;
                                                });
                                                _scheduleCalcAndSave();
                                              },
                                            ),
                                          ),
                                          const SizedBox(width: 12),
                                          Expanded(
                                            child: stateHasLocalTax(_usState)
                                                ? _CityDropdown(
                                                    state: _usState,
                                                    value: _usCity,
                                                    useAlt: useAlt,
                                                    onChanged: (v) {
                                                      setState(
                                                          () => _usCity = v);
                                                      _scheduleCalcAndSave();
                                                    },
                                                  )
                                                : const SizedBox.shrink(),
                                          ),
                                        ],
                                      ),
                                    ],
                                    if (FlavorConfig.isCA) ...[
                                      SizedBox(height: AppSpacing.md),
                                      _ProvinceDropdown(
                                        value: _caProvince,
                                        useAlt: useAlt,
                                        onChanged: (v) {
                                          setState(() => _caProvince = v!);
                                          _saveProvince(v!);
                                          _scheduleCalcAndSave();
                                        },
                                      ),
                                      SizedBox(height: AppSpacing.sm),
                                      // Reverse-calculation toggle (net → gross)
                                      _CaReverseModeToggle(
                                        reverseMode: _caReverseMode,
                                        onChanged: (v) {
                                          setState(() {
                                            _caReverseMode = v;
                                            _caRequiredGross = null;
                                            _showResults = false;
                                          });
                                          _scheduleCalcAndSave();
                                        },
                                      ),
                                    ],
                                    if (FlavorConfig.isUK) ...[
                                      SizedBox(height: AppSpacing.sm),
                                      // Reverse-calculation toggle (net → gross)
                                      _UkReverseModeToggle(
                                        reverseMode: _ukReverseMode,
                                        onChanged: (v) {
                                          setState(() {
                                            _ukReverseMode = v;
                                            _ukRequiredGross = null;
                                            _showResults = false;
                                          });
                                          _scheduleCalcAndSave();
                                        },
                                      ),
                                      // HMRC tax code field (default 1257L)
                                      SizedBox(height: AppSpacing.sm),
                                      _UkTaxCodeField(
                                        controller: _ukTaxCodeCtrl,
                                        onChanged: () => _scheduleCalcAndSave(),
                                      ),
                                      SizedBox(height: AppSpacing.sm),
                                      // Scotland toggle
                                      ValueListenableBuilder<bool>(
                                        valueListenable: ukScotlandNotifier,
                                        builder: (context, isScotland, _) =>
                                            SwitchListTile.adaptive(
                                          contentPadding: EdgeInsets.zero,
                                          dense: true,
                                          title: Text(
                                            'Scotland',
                                            style: Theme.of(context)
                                                .textTheme
                                                .bodyMedium,
                                          ),
                                          subtitle: Text(
                                            'Scottish income tax rates 2026/27',
                                            style: Theme.of(context)
                                                .textTheme
                                                .bodySmall,
                                          ),
                                          value: isScotland,
                                          activeColor: AppTheme.primary,
                                          onChanged: (v) {
                                            ukScotlandNotifier.value = v;
                                            _scheduleCalcAndSave();
                                          },
                                        ),
                                      ),
                                      // Student loan plan selector
                                      // None / Plan 1 / 2 / 4 / 5 — drives the
                                      // ukStudentLoanNotifier (on when not None).
                                      SizedBox(height: AppSpacing.sm),
                                      _UkLoanPlanDropdown(
                                        plan: ukStudentLoanNotifier.value
                                            ? _ukLoanPlan
                                            : 0,
                                        onChanged: (plan) {
                                          setState(() {
                                            if (plan == 0) {
                                              ukStudentLoanNotifier.value =
                                                  false;
                                            } else {
                                              ukStudentLoanNotifier.value = true;
                                              _ukLoanPlan = plan;
                                            }
                                          });
                                          _scheduleCalcAndSave();
                                        },
                                      ),
                                      // Postgraduate (Plan 3) loan toggle — 6%
                                      SwitchListTile.adaptive(
                                        contentPadding: EdgeInsets.zero,
                                        dense: true,
                                        title: Text(
                                          'Postgraduate Loan (Plan 3)',
                                          style: Theme.of(context)
                                              .textTheme
                                              .bodyMedium,
                                        ),
                                        subtitle: Text(
                                          '£21,000 threshold — 6% (cumulable)',
                                          style: Theme.of(context)
                                              .textTheme
                                              .bodySmall,
                                        ),
                                        value: _ukPostgrad,
                                        activeColor: AppTheme.primary,
                                        onChanged: (v) {
                                          setState(() => _ukPostgrad = v);
                                          _scheduleCalcAndSave();
                                        },
                                      ),
                                      // Salary sacrifice / SMART pension field
                                      SizedBox(height: AppSpacing.sm),
                                      _SalarySacrificeField(
                                        controller: _salarySacrificeCtrl,
                                        onChanged: (v) {
                                          setState(() => _salarySacrifice = v);
                                          _scheduleCalcAndSave();
                                        },
                                      ),
                                      // Auto-enrolment (qualifying earnings)
                                      SwitchListTile.adaptive(
                                        contentPadding: EdgeInsets.zero,
                                        dense: true,
                                        title: Text(
                                          'Auto-enrolment pension',
                                          style: Theme.of(context)
                                              .textTheme
                                              .bodyMedium,
                                        ),
                                        subtitle: Text(
                                          'Qualifying earnings £6,240–£50,270, 5% employee',
                                          style: Theme.of(context)
                                              .textTheme
                                              .bodySmall,
                                        ),
                                        value: _ukAutoEnrolment,
                                        activeColor: AppTheme.primary,
                                        onChanged: (v) {
                                          setState(
                                              () => _ukAutoEnrolment = v);
                                          _scheduleCalcAndSave();
                                        },
                                      ),
                                    ],
                                    // ── Second income (all flavors) ────────
                                    SizedBox(height: AppSpacing.sm),
                                    _SecondIncomeSection(
                                      enabled: _addSecondIncome,
                                      controller: _secondIncomeCtrl,
                                      es: es,
                                      fr: fr,
                                      onToggle: (on) {
                                        if (on &&
                                            !freemiumService.hasFullAccess) {
                                          PaywallHard.show(
                                            context,
                                            isSpanish: es,
                                            isFrench: fr,
                                            priceLabel: IAPService
                                                .instance.localizedPrice.value,
                                            onPurchase: IAPService.instance.buy,
                                          );
                                          return;
                                        }
                                        setState(() {
                                          _addSecondIncome = on;
                                          if (!on) {
                                            _secondIncome = 0;
                                            _secondIncomeCtrl.text = '0';
                                          }
                                        });
                                        _scheduleCalcAndSave();
                                      },
                                      onAmountChanged: (v) {
                                        setState(() => _secondIncome = v);
                                        _scheduleCalcAndSave();
                                      },
                                    ),
                                  ])),
                              SizedBox(height: AppSpacing.md),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const CalcwiseAdFooter(),
              ],
            ),
          ),
        );
      },
    );
  }
}

// ─── Salary input card ────────────────────────────────────────────────────────

class _SalaryInputCard extends StatelessWidget {
  final TextEditingController controller;
  final PayFrequency frequency;
  final bool useAlt, es, fr;

  const _SalaryInputCard({
    required this.controller,
    required this.frequency,
    required this.useAlt,
    required this.es,
    required this.fr,
  });

  String get _hintLabel {
    if (fr) return 'Entrez votre salaire';
    if (es) return 'Ingrese su salario';
    return 'Enter your salary';
  }

  String get _fieldLabel {
    if (fr) return 'Montant';
    if (es) return 'Monto';
    return 'Amount';
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.xl),
        side: BorderSide(color: CalcwiseTheme.of(context).cardBorder),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(
            _hintLabel,
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(color: AppTheme.primary),
          ),
          const SizedBox(height: AppSpacing.md),
          TextFormField(
            controller: controller,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              CurrencyInputFormatter(
                  locale: FlavorConfig.isCA
                      ? 'en_CA'
                      : (FlavorConfig.isUK ? 'en_GB' : 'en_US')),
            ],
            decoration: InputDecoration(
              prefixText: '${FlavorConfig.currencySymbol} ',
              prefixStyle: TextStyle(
                  fontSize: AppTextSize.subtitle, fontWeight: FontWeight.w600),
              labelText: _fieldLabel,
              hintText: '0.00',
            ),
            style: TextStyle(
                fontSize: AppTextSize.subtitle, fontWeight: FontWeight.w600),
            validator: (v) {
              if (v == null || v.trim().isEmpty) {
                return fr
                    ? 'Veuillez entrer un montant'
                    : (es ? 'Ingrese un monto' : 'Please enter an amount');
              }
              // Commas are thousand separators — strip them, never swap with '.'
              final val = double.tryParse(v.replaceAll(',', ''));
              if (val == null || val <= 0) {
                return fr
                    ? 'Montant invalide'
                    : (es ? 'Monto inválido' : 'Invalid amount');
              }
              return null;
            },
          ),
        ]),
      ),
    );
  }
}

// ─── Frequency chips ──────────────────────────────────────────────────────────

class _FrequencyChips extends StatelessWidget {
  final PayFrequency selected;
  final bool useAlt;
  final ValueChanged<PayFrequency> onChanged;

  const _FrequencyChips({
    required this.selected,
    required this.useAlt,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: FlavorConfig.isCA && useAlt
          ? 'Fréquence de paie'
          : (FlavorConfig.isUS && useAlt ? 'Frecuencia de pago' : 'Pay frequency'),
      container: true,
      child: Wrap(
        spacing: 8,
        runSpacing: 6,
        children: PayFrequency.values.map((f) {
          final isSelected = f == selected;
          return Semantics(
            inMutuallyExclusiveGroup: true,
            selected: isSelected,
            child: ChoiceChip(
              label: Text(f.label(useAlt)),
              selected: isSelected,
              selectedColor: AppTheme.primary,
              materialTapTargetSize: MaterialTapTargetSize.padded,
              labelStyle: TextStyle(
                color: isSelected ? Colors.white : AppTheme.labelGray,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
              ),
              onSelected: (_) => onChanged(f),
            ),
          );
        }).toList(),
      ),
    );
  }
}

// ─── State dropdown (US) ──────────────────────────────────────────────────────

class _StateDropdown extends StatelessWidget {
  final String value;
  final bool useAlt;
  final ValueChanged<String?> onChanged;

  const _StateDropdown({
    required this.value,
    required this.useAlt,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final es = FlavorConfig.isUS && useAlt;
    return DropdownButtonFormField<String>(
      initialValue: value,
      decoration: InputDecoration(
        labelText: es ? 'Estado' : 'State',
        prefixIcon: Icon(Icons.location_on_rounded),
      ),
      items: UsSalaryEngine.states
          .map((s) => DropdownMenuItem(value: s, child: Text(s)))
          .toList(),
      onChanged: onChanged,
    );
  }
}

// ─── Province dropdown (CA) ───────────────────────────────────────────────────

class _ProvinceDropdown extends StatelessWidget {
  final String value;
  final bool useAlt;
  final ValueChanged<String?> onChanged;

  const _ProvinceDropdown({
    required this.value,
    required this.useAlt,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final fr = FlavorConfig.isCA && useAlt;
    return DropdownButtonFormField<String>(
      initialValue: value,
      decoration: InputDecoration(
        labelText: fr ? 'Province' : 'Province',
        prefixIcon: Icon(Icons.location_on_rounded),
      ),
      items: CaSalaryEngine.provinces
          .map((p) => DropdownMenuItem(value: p, child: Text(p)))
          .toList(),
      onChanged: onChanged,
    );
  }
}

// ─── City dropdown (US local-tax) ─────────────────────────────────────────────

class _CityDropdown extends StatelessWidget {
  final String state;
  final String? value;
  final bool useAlt;
  final ValueChanged<String?> onChanged;

  const _CityDropdown({
    required this.state,
    required this.value,
    required this.useAlt,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final es = FlavorConfig.isUS && useAlt;
    final cities = stateCities[state] ?? const <String>[];
    return DropdownButtonFormField<String?>(
      initialValue: value,
      decoration: InputDecoration(
        labelText: es ? 'Ciudad (impuesto local)' : 'City (local tax)',
        prefixIcon: const Icon(Icons.location_city_rounded),
        helperText: es
            ? 'Opcional — aplica impuesto municipal'
            : 'Optional — applies municipal/local tax',
      ),
      items: [
        DropdownMenuItem<String?>(
          value: null,
          child: Text(es ? 'Ninguna' : 'None'),
        ),
        ...cities.map((key) {
          final lt = localTaxes[key]!;
          final pct = (lt.rate * 100).toStringAsFixed(2);
          return DropdownMenuItem<String?>(
            value: key,
            child: Text('${lt.name}  ($pct%)'),
          );
        }),
      ],
      onChanged: onChanged,
    );
  }
}

// ─── COL dataset ─────────────────────────────────────────────────────────────

const Map<String, double> _colIndexUS = {
  'New York, NY': 1.87,
  'San Francisco, CA': 1.79,
  'Los Angeles, CA': 1.53,
  'Boston, MA': 1.47,
  'Seattle, WA': 1.38,
  'Miami, FL': 1.22,
  'Austin, TX': 1.18,
  'Denver, CO': 1.16,
  'Chicago, IL': 1.09,
  'Phoenix, AZ': 1.04,
  'Dallas, TX': 1.02,
  'Atlanta, GA': 0.98,
  'Nashville, TN': 0.96,
  'Columbus, OH': 0.90,
  'Detroit, MI': 0.85,
};

const Map<String, double> _colIndexCA = {
  'Toronto, ON': 1.35,
  'Vancouver, BC': 1.32,
  'Calgary, AB': 1.10,
  'Ottawa, ON': 1.05,
  'Montreal, QC': 1.03,
  'Edmonton, AB': 1.00,
  'Winnipeg, MB': 0.95,
  'Halifax, NS': 0.93,
  'Victoria, BC': 1.20,
  'Quebec City, QC': 0.98,
};

// ─── Results section ──────────────────────────────────────────────────────────

class _ResultsSection extends StatefulWidget {
  final SalaryResult result;
  final double localTax;
  final String? localTaxLabel;
  final String label;
  final bool useAlt, es, fr;
  final bool caReverseMode;
  final double? caRequiredGross;
  final bool ukReverseMode;
  final double? ukRequiredGross;
  final UkTaxCode ukTaxCode;
  final double ukSalarySacrifice;
  final Future<void> Function(String? label) onSaveScenario;

  const _ResultsSection({
    required this.result,
    required this.localTax,
    required this.localTaxLabel,
    required this.label,
    required this.useAlt,
    required this.es,
    required this.fr,
    required this.onSaveScenario,
    this.caReverseMode = false,
    this.caRequiredGross,
    this.ukReverseMode = false,
    this.ukRequiredGross,
    this.ukTaxCode = UkTaxCode.standard,
    this.ukSalarySacrifice = 0,
  });

  @override
  State<_ResultsSection> createState() => _ResultsSectionState();
}

class _ResultsSectionState extends State<_ResultsSection> {
  String? _targetCity;

  // Delegate to the module-level cached formatter — no allocation per call.
  String _fmt(double v) => _currencyFmt2.format(v);

  String _pct(double v) => '${v.toStringAsFixed(1)}%';

  @override
  Widget build(BuildContext context) {
    final es = widget.es;
    final fr = widget.fr;
    final result = widget.result;
    final localTax = widget.localTax;
    // Adjusted net after subtracting the local (city) tax. When no city is
    // selected localTax == 0 and these match the engine output.
    final adjustedNetAnnual = result.netAnnual - localTax;
    final adjustedNetMonthly = adjustedNetAnnual / 12;
    final adjustedNetBiWeekly = adjustedNetAnnual / 26;
    final adjustedNetWeekly = adjustedNetAnnual / 52;
    final adjustedTotalTax = result.totalTax + localTax;
    final adjustedEffectiveRate = result.grossAnnual > 0
        ? adjustedTotalTax / result.grossAnnual * 100
        : result.effectiveRate;

    final netLabel = fr
        ? 'Salaire net annuel'
        : (es ? 'Salario neto anual' : 'Annual Take-Home');
    final monthlyLabel =
        fr ? 'Mensuel' : (es ? 'Mensual' : 'Monthly Take-Home');
    final biWeeklyLabel =
        fr ? 'Bimensuel' : (es ? 'Quincenal' : 'Bi-Weekly Take-Home');
    final weeklyLabel =
        fr ? 'Hebdomadaire' : (es ? 'Semanal' : 'Weekly Take-Home');
    final breakdownLabel =
        fr ? 'Répartition fiscale' : (es ? 'Desglose fiscal' : 'Tax Breakdown');
    final effectiveLabel =
        fr ? 'Taux effectif' : (es ? 'Tasa efectiva' : 'Effective Tax Rate');

    final federalLabel = FlavorConfig.isUK
        ? (fr ? 'Impôt sur le revenu' : 'Income Tax')
        : (fr ? 'Impôt fédéral' : (es ? 'Impuesto federal' : 'Federal Tax'));

    final ficaLabel = FlavorConfig.isUS
        ? 'FICA (SS + Medicare)'
        : (FlavorConfig.isUK
            ? (ukStudentLoanNotifier.value
                ? 'NI + Student Loan'
                : 'National Insurance')
            : (fr ? 'RPC + AE' : 'CPP + EI'));

    final stateLabel = FlavorConfig.isUS
        ? (es ? 'Impuesto estatal' : 'State Tax')
        : (fr ? 'Impôt provincial' : 'Provincial Tax');

    final grossLabel =
        fr ? 'Salaire brut' : (es ? 'Salario bruto' : 'Gross Salary');
    final totalTaxLabel =
        fr ? 'Total impôts' : (es ? 'Total impuestos' : 'Total Tax');
    final localLabel = widget.localTaxLabel ??
        (fr ? 'Impôt local' : (es ? 'Impuesto local' : 'Local Tax'));
    final flowLabel =
        fr ? 'Flux du salaire' : (es ? 'Flujo del salario' : 'Paycheck Flow');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(widget.label,
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(color: AppTheme.primary)),
        const SizedBox(height: AppSpacing.md),

        // Net take-home hero card
        CalcwiseHeroCard(
          label: netLabel,
          value: _fmt(adjustedNetAnnual),
          secondary: fr
              ? 'Après impôts'
              : (es ? 'Después de impuestos' : 'After taxes'),
          backgroundColor: AppTheme.primary,
          rawValue: adjustedNetAnnual,
          valueFormatter: (v) => AmountFormatter.ui(v, FlavorConfig.currencyCode),
          rawStats: [
            (label: monthlyLabel, value: adjustedNetMonthly, formatter: (v) => AmountFormatter.ui(v, FlavorConfig.currencyCode)),
            (label: totalTaxLabel, value: adjustedTotalTax, formatter: (v) => AmountFormatter.ui(v, FlavorConfig.currencyCode)),
            (label: effectiveLabel, value: adjustedEffectiveRate, formatter: (v) => '${v.toStringAsFixed(1)}%'),
          ],
          stats: [
            (label: monthlyLabel, value: _fmt(adjustedNetMonthly)),
            (label: totalTaxLabel, value: _fmt(adjustedTotalTax)),
            (label: effectiveLabel, value: _pct(adjustedEffectiveRate)),
          ],
        ),
        const SizedBox(height: AppSpacing.md),

        // CA reverse-mode: show required gross to achieve the target net
        if (FlavorConfig.isCA &&
            widget.caReverseMode &&
            widget.caRequiredGross != null) ...[
          _CaReverseResultBanner(
            requiredGross: widget.caRequiredGross!,
            targetNet: adjustedNetAnnual,
            fr: fr,
          ),
          const SizedBox(height: AppSpacing.md),
        ],

        // UK reverse-mode: show required gross to achieve the target net
        if (FlavorConfig.isUK &&
            widget.ukReverseMode &&
            widget.ukRequiredGross != null) ...[
          _CaReverseResultBanner(
            requiredGross: widget.ukRequiredGross!,
            targetNet: adjustedNetAnnual,
            fr: false,
          ),
          const SizedBox(height: AppSpacing.md),
        ],

        // UK salary sacrifice savings banner
        if (FlavorConfig.isUK && widget.ukSalarySacrifice > 0) ...[
          _UkSalarySacrificeSavingsBanner(
            grossAnnual: result.grossAnnual,
            salarySacrifice: widget.ukSalarySacrifice,
            scotland: ukScotlandNotifier.value,
          ),
          const SizedBox(height: AppSpacing.md),
        ],

        // Bi-weekly / Weekly row
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                  child: ResultCard(
                      label: biWeeklyLabel, value: _fmt(adjustedNetBiWeekly))),
              SizedBox(width: 8),
              Expanded(
                  child: ResultCard(
                      label: weeklyLabel, value: _fmt(adjustedNetWeekly))),
            ],
          ),
        ),
        SizedBox(height: AppSpacing.xl),

        // ── Sankey paycheck flow ─────────────────────────────────────────
        Card(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.xl),
            side: BorderSide(color: CalcwiseTheme.of(context).cardBorder),
          ),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(flowLabel,
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontSize: AppTextSize.bodyMd)),
                const SizedBox(height: AppSpacing.md),
                Semantics(
                  label: 'Salary breakdown: '
                      'Gross ${_currencyFmt0.format(result.grossAnnual)}, '
                      '${federalLabel} ${_currencyFmt0.format(result.federalTax)}, '
                      'Net ${_currencyFmt0.format(result.netAnnual)}',
                  child: SankeyChart(
                    gross: result.grossAnnual,
                    currencySymbol: FlavorConfig.currencySymbol,
                    grossLabel: fr
                        ? 'Brut'
                        : (es ? 'Bruto' : 'Gross'),
                    outflows: [
                      if (result.federalTax > 0)
                        SankeyFlow(
                          label: federalLabel,
                          value: result.federalTax,
                          color: CalcwiseTheme.of(context).errorRed,
                        ),
                      if (result.ficaTax > 0)
                        SankeyFlow(
                          label: ficaLabel,
                          value: result.ficaTax,
                          color: Theme.of(context).colorScheme.tertiary,
                        ),
                      if (!FlavorConfig.isUK && result.stateTax > 0)
                        SankeyFlow(
                          label: stateLabel,
                          value: result.stateTax,
                          color: Theme.of(context).colorScheme.secondary,
                        ),
                      if (localTax > 0)
                        SankeyFlow(
                          label: localLabel,
                          value: localTax,
                          color: AppTheme.gold, // yellow/gold
                        ),
                      SankeyFlow(
                        label: netLabel,
                        value: adjustedNetAnnual > 0 ? adjustedNetAnnual : 0,
                        color: AppTheme.success,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        SizedBox(height: AppSpacing.md),

        // Pie chart
        Card(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.xl),
            side: BorderSide(color: CalcwiseTheme.of(context).cardBorder),
          ),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(breakdownLabel,
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontSize: AppTextSize.bodyMd)),
                SizedBox(height: AppSpacing.md),
                SizedBox(
                  height: 200,
                  child: _TaxPieChart(
                    result: result,
                    federalLabel: federalLabel,
                    ficaLabel: ficaLabel,
                    stateLabel: stateLabel,
                  ),
                ),
                SizedBox(height: AppSpacing.md),
                Divider(color: AppTheme.divider),
                const SizedBox(height: AppSpacing.sm),
                MetricRow(label: grossLabel, value: _fmt(result.grossAnnual)),
                MetricRow(
                    label: federalLabel,
                    value: _fmt(result.federalTax),
                    valueColor: CalcwiseTheme.of(context).errorRed),
                if (result.ficaTax > 0)
                  MetricRow(
                      label: ficaLabel,
                      value: _fmt(result.ficaTax),
                      valueColor: CalcwiseTheme.of(context).warningOrange),
                if (!FlavorConfig.isUK && result.stateTax > 0)
                  MetricRow(
                      label: stateLabel,
                      value: _fmt(result.stateTax),
                      valueColor: CalcwiseTheme.of(context).warningOrange),
                if (localTax > 0)
                  MetricRow(
                      label: localLabel,
                      value: _fmt(localTax),
                      valueColor: AppTheme.gold),
                MetricRow(
                    label: totalTaxLabel,
                    value: _fmt(adjustedTotalTax),
                    valueColor: CalcwiseTheme.of(context).errorRed),
                MetricRow(
                    label: effectiveLabel, value: _pct(adjustedEffectiveRate)),
                MetricRow(
                    label: netLabel,
                    value: _fmt(adjustedNetAnnual),
                    valueColor: AppTheme.success),
              ],
            ),
          ),
        ),

        SizedBox(height: AppSpacing.md),

        // ── City-to-City COL Comparison ──────────────────────────────────
        if (!FlavorConfig.isUK)
          _CityComparisonCard(
            result: result,
            es: es,
            fr: fr,
            targetCity: _targetCity,
            onCityChanged: (city) => setState(() => _targetCity = city),
          ),

        SizedBox(height: AppSpacing.md),

        // Smart Insights
        if (FlavorConfig.isUS)
          InsightCard(
            insights: InsightEngine.generate(
              grossAnnual: result.grossAnnual,
              netAnnual: result.netAnnual,
              federalTax: result.federalTax,
              stateTax: result.stateTax,
              ficaTax: result.ficaTax,
              federalBracketPct:
                  InsightEngine.usFederalBracketPct(result.grossAnnual),
              isEs: es,
              isFr: fr,
            ),
            isSpanish: es,
          ),

        SizedBox(height: AppSpacing.md),

        // Benefits & deductions estimator
        _BenefitsCard(result: result, fr: fr, es: es),

        SizedBox(height: AppSpacing.md),

        // Pay Rate Converter
        _PayRateConverter(result: result, fr: fr, es: es),

        SizedBox(height: AppSpacing.md),

        // Premium gate if user is free
        ValueListenableBuilder<bool>(
          valueListenable: freemiumService.hasFullAccessNotifier,
          builder: (_, isPremium, __) => isPremium
              ? const SizedBox.shrink()
              : CalcwisePremiumGate(
                  title: fr
                      ? 'Historique illimité & PDF'
                      : (es
                          ? 'Historial ilimitado y PDF'
                          : 'Unlimited History & PDF'),
                  description: fr
                      ? 'Sauvegardez vos calculs et exportez en PDF.'
                      : (es
                          ? 'Guarda tus cálculos y exporta en PDF.'
                          : 'Save your calculations and export to PDF.'),
                  onUnlock: () => IAPService.instance.buy(),
                  price: IAPService.instance.localizedPrice,
                ),
        ),

        const SizedBox(height: AppSpacing.md),

        // Secondary export actions — compact icon row
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _PdfExportButton(result: result, fr: fr, es: es, iconOnly: true),
            _TotalCompReportButton(result: result, fr: fr, es: es, iconOnly: true),
            _CsvExportButton(result: result, fr: fr, es: es, iconOnly: true),
          ],
        ),

        const SizedBox(height: AppSpacing.sm),

        // Save Scenario (pin) — always visible; paywall is gated inside _saveScenario.
        SaveScenarioButton(onSave: widget.onSaveScenario),

        const SizedBox(height: AppSpacing.md),
        Text(
          fr
              ? 'À titre informatif seulement. Ce n\'est pas un conseil financier.'
              : (es
                  ? 'Solo para fines informativos. No es asesoramiento financiero.'
                  : 'For informational purposes only. Not financial advice.'),
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: AppTextSize.xs,
            color: AppTheme.labelGray,
          ),
        ),
      ],
    );
  }
}

// ─── City-to-City COL Comparison ─────────────────────────────────────────────

class _CityComparisonCard extends StatelessWidget {
  final SalaryResult result;
  final bool es, fr;
  final String? targetCity;
  final ValueChanged<String?> onCityChanged;

  const _CityComparisonCard({
    required this.result,
    required this.es,
    required this.fr,
    required this.targetCity,
    required this.onCityChanged,
  });

  String _fmtCurrency(double v) => _dollarFmt0.format(v);

  Map<String, double> get _cityIndex =>
      FlavorConfig.isCA ? _colIndexCA : _colIndexUS;

  @override
  Widget build(BuildContext context) {
    final title = fr
        ? 'Comparer avec une autre ville'
        : (es ? 'Comparar con otra ciudad' : 'Compare to Another City');
    final hintLabel = fr
        ? 'Sélectionner une ville…'
        : (es ? 'Seleccionar ciudad…' : 'Select a city…');

    // Determine current city COL index.
    // We use 1.00 as baseline (national average) when user's city is not in dataset.
    const double currentCOL = 1.00;

    double? equivalentGross;
    double? pctDiff;
    bool needsMore = false;

    if (targetCity != null && _cityIndex[targetCity] != null) {
      final targetCOL = _cityIndex[targetCity]!;
      // equivalentSalary (net purchasing power equivalent) based on net pay
      final equivalentNet = result.netAnnual * targetCOL / currentCOL;
      // Scale back to gross using same effective rate
      final effRate = result.effectiveRate / 100;
      equivalentGross =
          effRate < 1 ? equivalentNet / (1 - effRate) : equivalentNet;
      pctDiff =
          ((equivalentGross - result.grossAnnual) / result.grossAnnual * 100);
      needsMore = equivalentGross > result.grossAnnual;
    }

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.xl),
        side: BorderSide(color: CalcwiseTheme.of(context).cardBorder),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(Icons.compare_arrows_rounded,
                  size: 18, color: AppTheme.primary),
              SizedBox(width: 8),
              Text(title,
                  style: TextStyle(
                      fontSize: AppTextSize.bodyMd,
                      fontWeight: FontWeight.w600)),
            ]),
            const SizedBox(height: AppSpacing.md),
            DropdownButtonFormField<String>(
              value: targetCity,
              decoration: InputDecoration(
                labelText: hintLabel,
                prefixIcon: Icon(Icons.location_city_rounded),
              ),
              items: _cityIndex.keys
                  .map((city) =>
                      DropdownMenuItem(value: city, child: Text(city)))
                  .toList(),
              onChanged: onCityChanged,
            ),
            if (targetCity != null &&
                _cityIndex[targetCity] != null &&
                equivalentGross != null) ...[
              SizedBox(height: AppSpacing.md),
              // Result pill
              Container(
                padding: const EdgeInsets.all(AppSpacing.lg),
                decoration: BoxDecoration(
                  color: needsMore
                      ? CalcwiseTheme.of(context)
                          .errorRed
                          .withValues(alpha: 0.07)
                      : AppTheme.success.withValues(alpha: 0.07),
                  borderRadius: BorderRadius.circular(AppRadius.lg),
                  border: Border.all(
                    color: needsMore
                        ? CalcwiseTheme.of(context)
                            .errorRed
                            .withValues(alpha: 0.30)
                        : AppTheme.success.withValues(alpha: 0.30),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      fr
                          ? 'Pour maintenir votre niveau de vie actuel à $targetCity :'
                          : (es
                              ? 'Para mantener tu estilo de vida actual en $targetCity:'
                              : 'To maintain your current lifestyle in $targetCity:'),
                      style: TextStyle(
                          fontSize: AppTextSize.sm,
                          color: CalcwiseTheme.of(context).textSecondary),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      fr
                          ? 'Vous auriez besoin de ${_fmtCurrency(equivalentGross)}/an brut'
                          : (es
                              ? 'Necesitarías ${_fmtCurrency(equivalentGross)}/año bruto'
                              : "You'd need ${_fmtCurrency(equivalentGross)}/yr gross"),
                      style: TextStyle(
                          fontSize: AppTextSize.bodyXl,
                          fontWeight: FontWeight.bold,
                          color: needsMore
                              ? CalcwiseTheme.of(context).errorRed
                              : AppTheme.success),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Row(children: [
                      Icon(
                        needsMore ? Icons.trending_up : Icons.trending_down,
                        size: 16,
                        color: needsMore
                            ? CalcwiseTheme.of(context).errorRed
                            : AppTheme.success,
                      ),
                      SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          needsMore
                              ? (fr
                                  ? "Vous auriez besoin de ${pctDiff!.abs().toStringAsFixed(1)}% de plus"
                                  : (es
                                      ? 'Necesitarías ${pctDiff!.abs().toStringAsFixed(1)}% más'
                                      : "You'd need ${pctDiff!.abs().toStringAsFixed(1)}% more"))
                              : (fr
                                  ? "Vous pourriez gagner ${pctDiff!.abs().toStringAsFixed(1)}% de moins et maintenir votre niveau de vie"
                                  : (es
                                      ? 'Podrías ganar ${pctDiff!.abs().toStringAsFixed(1)}% menos y mantener tu estilo de vida'
                                      : "You could earn ${pctDiff!.abs().toStringAsFixed(1)}% less and maintain lifestyle")),
                          style: TextStyle(
                              fontSize: AppTextSize.sm,
                              fontWeight: FontWeight.w600,
                              color: needsMore
                                  ? CalcwiseTheme.of(context).errorRed
                                  : AppTheme.success),
                        ),
                      ),
                    ]),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                fr
                    ? "Estimation basée sur les moyennes nationales du coût de la vie. Les taxes locales varient."
                    : (es
                        ? 'Estimación basada en promedios nacionales del costo de vida. Los impuestos locales varían.'
                        : 'Cost-of-living estimate based on national averages. Local taxes vary.'),
                style: TextStyle(
                    fontSize: AppTextSize.xs,
                    fontStyle: FontStyle.italic,
                    color: CalcwiseTheme.of(context).textSecondary),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ─── Benefits & deductions estimator ─────────────────────────────────────────

class _BenefitsCard extends StatefulWidget {
  final SalaryResult result;
  final bool fr, es;
  const _BenefitsCard(
      {required this.result, required this.fr, required this.es});
  @override
  State<_BenefitsCard> createState() => _BenefitsCardState();
}

class _BenefitsCardState extends State<_BenefitsCard> {
  late double _insurancePct;
  late double _retirementPct;
  late double _unionPct;
  late TextEditingController _insCtrl, _retCtrl, _uniCtrl;

  @override
  void initState() {
    super.initState();
    if (FlavorConfig.isCA) {
      _insurancePct = 3.0;
      _retirementPct = 5.0;
      _unionPct = 1.0;
    } else if (FlavorConfig.isUK) {
      _insurancePct = 2.0;
      _retirementPct = 5.0;
      _unionPct = 0.5;
    } else {
      _insurancePct = 5.0;
      _retirementPct = 6.0;
      _unionPct = 1.0;
    }
    _insCtrl = TextEditingController(text: _insurancePct.toStringAsFixed(1));
    _retCtrl = TextEditingController(text: _retirementPct.toStringAsFixed(1));
    _uniCtrl = TextEditingController(text: _unionPct.toStringAsFixed(1));
  }

  @override
  void dispose() {
    _insCtrl.dispose();
    _retCtrl.dispose();
    _uniCtrl.dispose();
    super.dispose();
  }

  double get _gross => widget.result.grossAnnual;
  double get _insAmt => _gross * _insurancePct / 100;
  double get _retAmt => _gross * _retirementPct / 100;
  double get _uniAmt => _gross * _unionPct / 100;
  double get _netAfter => widget.result.netAnnual - _insAmt - _retAmt - _uniAmt;

  String _fmt(double v) => _currencyFmt0.format(v);

  void _update(TextEditingController ctrl, void Function(double) setter) {
    final v = double.tryParse(ctrl.text);
    if (v != null && v >= 0 && v <= 50) setState(() => setter(v));
  }

  @override
  Widget build(BuildContext context) {
    final fr = widget.fr;
    final es = widget.es;
    final title = fr
        ? 'Avantages sociaux (estimatif)'
        : (es
            ? 'Beneficios sociales (estimativo)'
            : 'Benefits & Deductions (estimate)');
    final insLabel = FlavorConfig.isCA
        ? (fr ? 'Assurance collective' : 'Group Insurance')
        : FlavorConfig.isUK
            ? 'Private Health / Dental'
            : 'Health Insurance';
    final retLabel = FlavorConfig.isCA
        ? (fr ? 'REER' : 'RRSP')
        : FlavorConfig.isUK
            ? 'Pension (employee)'
            : '401(k)';
    final uniLabel =
        fr ? 'Cotisation syndicale' : (es ? 'Cuota sindical' : 'Union Dues');
    final netLabel = fr
        ? 'Net estimé après déductions'
        : (es ? 'Neto estimado tras deducciones' : 'Est. Net After Benefits');
    final pctHint = fr ? '% du brut' : (es ? '% del bruto' : '% of gross');

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.xl),
        side: BorderSide(color: CalcwiseTheme.of(context).cardBorder),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(Icons.health_and_safety_rounded,
                  size: 18, color: AppTheme.primary),
              SizedBox(width: 8),
              Expanded(
                  child: Text(title,
                      style: TextStyle(
                          fontSize: AppTextSize.body,
                          fontWeight: FontWeight.w600))),
            ]),
            const SizedBox(height: AppSpacing.xs),
            Text(pctHint,
                style: TextStyle(
                    fontSize: AppTextSize.xs, color: AppTheme.labelGray)),
            const SizedBox(height: AppSpacing.md),
            _BenefitRow(
                label: insLabel,
                controller: _insCtrl,
                amount: _insAmt,
                onChanged: () => _update(_insCtrl, (v) => _insurancePct = v)),
            const SizedBox(height: AppSpacing.sm),
            _BenefitRow(
                label: retLabel,
                controller: _retCtrl,
                amount: _retAmt,
                onChanged: () => _update(_retCtrl, (v) => _retirementPct = v)),
            const SizedBox(height: AppSpacing.sm),
            _BenefitRow(
                label: uniLabel,
                controller: _uniCtrl,
                amount: _uniAmt,
                onChanged: () => _update(_uniCtrl, (v) => _unionPct = v)),
            Divider(height: 20),
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Flexible(
                child: Text(netLabel,
                    style: TextStyle(
                        fontWeight: FontWeight.w600, fontSize: AppTextSize.md)),
              ),
              const SizedBox(width: 8),
              Text(
                _fmt(_netAfter),
                style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: AppTextSize.bodyMd,
                    color: _netAfter > 0
                        ? AppTheme.success
                        : CalcwiseSemanticColors.error(
                            Theme.of(context).brightness)),
              ),
            ]),
            const SizedBox(height: AppSpacing.xs),
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Flexible(child: Text(fr ? 'Mensuel' : (es ? 'Mensual' : 'Monthly'),
                  style: TextStyle(
                      fontSize: AppTextSize.sm, color: AppTheme.labelGray),
                  overflow: TextOverflow.ellipsis)),
              const SizedBox(width: 8),
              Text(_fmt(_netAfter / 12),
                  style: TextStyle(
                      fontSize: AppTextSize.sm,
                      color: AppTheme.labelGray,
                      fontWeight: FontWeight.w500)),
            ]),
          ],
        ),
      ),
    );
  }
}

class _BenefitRow extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  final double amount;
  final VoidCallback onChanged;
  const _BenefitRow(
      {required this.label,
      required this.controller,
      required this.amount,
      required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      Expanded(
          flex: 4,
          child: Text(label, style: TextStyle(fontSize: AppTextSize.sm))),
      SizedBox(
        width: 60,
        child: TextFormField(
          controller: controller,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: AppTextSize.md),
          decoration: const InputDecoration(
            suffixText: '%',
            contentPadding: EdgeInsets.symmetric(
                horizontal: AppSpacing.sm, vertical: AppSpacing.xs),
            isDense: true,
          ),
          onChanged: (_) => onChanged(),
        ),
      ),
      SizedBox(width: 8),
      SizedBox(
        width: 80,
        child: Text(
          _currencyFmt0.format(amount),
          textAlign: TextAlign.right,
          style: TextStyle(fontSize: AppTextSize.sm, color: AppTheme.labelGray),
        ),
      ),
    ]);
  }
}

// ─── Tax pie chart ────────────────────────────────────────────────────────────

class _TaxPieChart extends StatefulWidget {
  final SalaryResult result;
  final String federalLabel, ficaLabel, stateLabel;

  const _TaxPieChart({
    required this.result,
    required this.federalLabel,
    required this.ficaLabel,
    required this.stateLabel,
  });

  @override
  State<_TaxPieChart> createState() => _TaxPieChartState();
}

class _TaxPieChartState extends State<_TaxPieChart> {
  int _touched = -1;

  @override
  Widget build(BuildContext context) {
    final r = widget.result;
    final gross = r.grossAnnual;

    final cs = Theme.of(context).colorScheme;
    final sections = <_Slice>[
      _Slice(
          label: widget.federalLabel,
          value: r.federalTax,
          color: cs.error),
      if (r.ficaTax > 0)
        _Slice(
            label: widget.ficaLabel,
            value: r.ficaTax,
            color: CalcwiseTheme.of(context).warningOrange,
            borderSide: BorderSide(color: Theme.of(context).colorScheme.surface, width: 2)),
      if (!FlavorConfig.isUK && r.stateTax > 0)
        _Slice(
            label: widget.stateLabel,
            value: r.stateTax,
            color: cs.tertiary),
      _Slice(label: 'Net pay', value: r.netAnnual, color: AppTheme.success),
    ];

    return Row(
      children: [
        Expanded(
          flex: 5,
          child: PieChart(
            PieChartData(
              pieTouchData: PieTouchData(
                touchCallback: (event, response) {
                  setState(() {
                    _touched = (event.isInterestedForInteractions &&
                            response?.touchedSection != null)
                        ? response!.touchedSection!.touchedSectionIndex
                        : -1;
                  });
                },
              ),
              borderData: FlBorderData(show: false),
              sectionsSpace: 2,
              centerSpaceRadius: CalcwiseChartTokens.donutCenterR,
              sections: sections.asMap().entries.map((e) {
                final idx = e.key;
                final s = e.value;
                final pct = s.value / gross * 100;
                final isTouched = idx == _touched;
                final money = NumberFormat.currency(
                  symbol: FlavorConfig.currencySymbol,
                  decimalDigits: 0,
                ).format(s.value);
                return PieChartSectionData(
                  color: s.color,
                  value: s.value,
                  title: isTouched
                      ? '$money\n${pct.toStringAsFixed(1)}%'
                      : (pct < 5.0 ? '' : '${pct.toStringAsFixed(1)}%'),
                  radius: isTouched ? CalcwiseChartTokens.donutSectionR + 10 : CalcwiseChartTokens.donutSectionR,
                  titleStyle: TextStyle(
                    fontSize: isTouched ? 12 : 11,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                  borderSide: s.borderSide,
                );
              }).toList(),
            ),
            swapAnimationDuration: CalcwiseChartTokens.swapDuration,
          ),
        ),
        SizedBox(width: 12),
        Expanded(
          flex: 4,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: sections.map((s) {
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration:
                        BoxDecoration(color: s.color, shape: BoxShape.circle),
                  ),
                  SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      s.label,
                      style: TextStyle(
                          fontSize: AppTextSize.xs, color: AppTheme.labelGray),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ]),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }
}

class _Slice {
  final String label;
  final double value;
  final Color color;
  final BorderSide borderSide;
  const _Slice({
    required this.label,
    required this.value,
    required this.color,
    this.borderSide = BorderSide.none,
  });
}

// ─── PDF Export Button ────────────────────────────────────────────────────────

class _PdfExportButton extends StatelessWidget {
  final SalaryResult result;
  final bool fr, es;
  final bool iconOnly;

  const _PdfExportButton({
    required this.result,
    required this.fr,
    required this.es,
    this.iconOnly = false,
  });

  String get _label =>
      fr ? 'Exporter PDF' : (es ? 'Exportar PDF' : 'Export PDF');

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: freemiumService.hasFullAccessNotifier,
      builder: (context, isPremium, _) {
        Future<void> onPressed() async {
          HapticFeedback.mediumImpact();
          if (!isPremium) {
            await PdfExportService.showUnlockOrPay(
              context,
              () => _exportPdf(context),
            );
            return;
          }
          await _exportPdf(context);
        }
        if (iconOnly) {
          return Tooltip(
            message: _label,
            child: IconButton(
              icon: Icon(isPremium
                  ? Icons.picture_as_pdf_rounded
                  : Icons.lock_outline_rounded),
              color: AppTheme.primary,
              onPressed: onPressed,
            ),
          );
        }
        return SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            icon: Icon(isPremium
                ? Icons.picture_as_pdf_rounded
                : Icons.lock_outline_rounded),
            label: Text(_label),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppTheme.primary,
              side: BorderSide(color: AppTheme.primary),
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppRadius.xl)),
            ),
            onPressed: onPressed,
          ),
        );
      },
    );
  }

  Future<void> _exportPdf(BuildContext context) async {
    final federalLabel = FlavorConfig.isUK
        ? 'Income Tax'
        : (fr ? 'Impôt fédéral' : (es ? 'Impuesto federal' : 'Federal Tax'));
    final ficaLabel = FlavorConfig.isUS
        ? 'FICA (SS + Medicare)'
        : (FlavorConfig.isUK
            ? (ukStudentLoanNotifier.value
                ? 'NI + Student Loan'
                : 'National Insurance')
            : (fr ? 'RPC + AE' : 'CPP + EI'));
    final stateLabel = FlavorConfig.isUS
        ? (es ? 'Impuesto estatal' : 'State Tax')
        : (fr ? 'Impôt provincial' : 'Provincial Tax');

    try {
      final bytes = await Isolate.run(() => _buildSalaryAnalysisPdfBytes(
            _SalaryAnalysisPdfParams(
              grossAnnual: result.grossAnnual,
              federalTax: result.federalTax,
              ficaTax: result.ficaTax,
              stateTax: result.stateTax,
              totalTax: result.totalTax,
              netAnnual: result.netAnnual,
              netMonthly: result.netMonthly,
              effectiveRate: result.effectiveRate,
              currencySymbol: FlavorConfig.currencySymbol,
              dateStr: DateFormat('MMMM d, yyyy').format(DateTime.now()),
              federalLabel: federalLabel,
              ficaLabel: ficaLabel,
              stateLabel: stateLabel,
              grossLabel:
                  fr ? 'Salaire brut' : (es ? 'Salario bruto' : 'Gross Salary'),
              netLabel: fr
                  ? 'Salaire net'
                  : (es ? 'Salario neto' : 'Net Salary (Annual)'),
              totalLabel:
                  fr ? 'Total impôts' : (es ? 'Total impuestos' : 'Total Tax'),
              rateLabel: fr
                  ? 'Taux effectif'
                  : (es ? 'Tasa efectiva' : 'Effective Tax Rate'),
              monthLabel: fr ? 'Mensuel' : (es ? 'Mensual' : 'Monthly'),
              titleText: fr
                  ? 'Analyse salariale'
                  : (es ? 'Análisis salarial' : 'Salary Analysis'),
              hasFica: result.ficaTax > 0,
              hasState: !FlavorConfig.isUK && result.stateTax > 0,
            ),
          ));
      await Printing.sharePdf(
          bytes: bytes,
          filename:
              'salary_summary_${DateTime.now().millisecondsSinceEpoch}.pdf');
      analyticsService.logPdfExported();
      analyticsService.logResultShared();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(fr
                ? 'PDF exporté avec succès'
                : es
                    ? 'PDF exportado con éxito'
                    : 'PDF exported successfully'),
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(fr
                ? 'Erreur lors de l\'export'
                : es
                    ? 'Error al exportar'
                    : 'Export failed'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }
}

// ─── Total Compensation Report Button ────────────────────────────────────────

class _TotalCompReportButton extends StatelessWidget {
  final SalaryResult result;
  final bool fr, es;
  final bool iconOnly;

  const _TotalCompReportButton({
    required this.result,
    required this.fr,
    required this.es,
    this.iconOnly = false,
  });

  String get _label => fr
      ? 'Rapport de rémunération globale'
      : (es ? 'Informe de compensación total' : 'Total Compensation Report');

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: freemiumService.hasFullAccessNotifier,
      builder: (context, isPremium, _) {
        Future<void> onPressed() async {
          HapticFeedback.mediumImpact();
          if (!isPremium) {
            PaywallHard.show(
              context,
              isSpanish: es,
              isFrench: fr,
              priceLabel: IAPService.instance.localizedPrice.value,
              onPurchase: IAPService.instance.buy,
            );
            return;
          }
          await _exportTotalCompPdf(context);
        }
        if (iconOnly) {
          return Tooltip(
            message: _label,
            child: IconButton(
              icon: Icon(isPremium
                  ? Icons.volunteer_activism_rounded
                  : Icons.lock_outline_rounded),
              color: AppTheme.primary,
              onPressed: onPressed,
            ),
          );
        }
        return SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            icon: Icon(isPremium
                ? Icons.volunteer_activism_rounded
                : Icons.lock_outline_rounded),
            label: Text(_label),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppTheme.primary,
              side: BorderSide(color: AppTheme.primary),
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppRadius.xl)),
            ),
            onPressed: onPressed,
          ),
        );
      },
    );
  }

  Future<void> _exportTotalCompPdf(BuildContext context) async {
    // Default benefit assumptions (mid-market)
    final healthMonthly = FlavorConfig.isUK ? 120.0 : 450.0;
    final retirementPct = FlavorConfig.isCA ? 5.0 : 4.0;
    const ptoDays = 15.0;
    final gross = result.grossAnnual;

    final healthAnnual = healthMonthly * 12;
    final retirementAnnual = gross * retirementPct / 100;
    final ptoAnnual = gross / 260.0 * ptoDays;
    final totalBenefits = healthAnnual + retirementAnnual + ptoAnnual;
    final totalComp = gross + totalBenefits;

    final retLabel = FlavorConfig.isCA
        ? (fr ? 'Cotisation REER employeur' : 'RRSP Match')
        : (FlavorConfig.isUK ? 'Pension Contribution' : '401(k) Match');
    final federalLabel = FlavorConfig.isUK
        ? 'Income Tax'
        : (fr ? 'Impôt fédéral' : (es ? 'Impuesto federal' : 'Federal Tax'));
    final ficaLabel = FlavorConfig.isUS
        ? 'FICA (SS + Medicare)'
        : (FlavorConfig.isUK
            ? (ukStudentLoanNotifier.value
                ? 'NI + Student Loan'
                : 'National Insurance')
            : (fr ? 'RPC + AE' : 'CPP + EI'));
    final stateLabel = FlavorConfig.isUS
        ? (es ? 'Impuesto estatal' : 'State Tax')
        : (fr ? 'Impôt provincial' : 'Provincial Tax');

    try {
      final bytes = await Isolate.run(() => _buildTotalCompPdfBytes(
            _TotalCompPdfParams(
              grossAnnual: result.grossAnnual,
              federalTax: result.federalTax,
              ficaTax: result.ficaTax,
              stateTax: result.stateTax,
              totalTax: result.totalTax,
              netAnnual: result.netAnnual,
              healthAnnual: healthAnnual,
              retirementAnnual: retirementAnnual,
              ptoAnnual: ptoAnnual,
              totalBenefits: totalBenefits,
              totalComp: totalComp,
              currencySymbol: FlavorConfig.currencySymbol,
              dateStr: DateFormat('MMMM d, yyyy').format(DateTime.now()),
              federalLabel: federalLabel,
              ficaLabel: ficaLabel,
              stateLabel: stateLabel,
              retLabel: retLabel,
              titleText: fr
                  ? 'Rapport de rémunération globale'
                  : es
                      ? 'Informe de compensación total'
                      : 'Total Compensation Report',
              hasFica: result.ficaTax > 0,
              hasState: !FlavorConfig.isUK && result.stateTax > 0,
              isUK: FlavorConfig.isUK,
              fr: fr,
              es: es,
            ),
          ));
      await Printing.sharePdf(
          bytes: bytes,
          filename:
              'total_compensation_${DateTime.now().millisecondsSinceEpoch}.pdf');
      analyticsService.logPdfExported();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(fr
                ? 'Rapport exporté avec succès'
                : es
                    ? 'Informe exportado con éxito'
                    : 'Report exported successfully'),
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(fr
                ? 'Erreur lors de l\'export'
                : es
                    ? 'Error al exportar'
                    : 'Export failed'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }
}

// ─── CSV Export Button ────────────────────────────────────────────────────────

class _CsvExportButton extends StatelessWidget {
  final SalaryResult result;
  final bool fr, es;
  final bool iconOnly;

  const _CsvExportButton({
    required this.result,
    required this.fr,
    required this.es,
    this.iconOnly = false,
  });

  String get _label =>
      fr ? 'Exporter CSV' : (es ? 'Exportar CSV' : 'Export CSV');

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: freemiumService.hasFullAccessNotifier,
      builder: (context, isPremium, _) {
        Future<void> onPressed() async {
          HapticFeedback.mediumImpact();
          if (!isPremium) {
            await PdfExportService.showUnlockOrPay(
              context,
              () => _exportCsv(context),
            );
            return;
          }
          await _exportCsv(context);
        }
        if (iconOnly) {
          return Tooltip(
            message: _label,
            child: IconButton(
              icon: Icon(isPremium
                  ? Icons.table_chart_outlined
                  : Icons.lock_outline_rounded),
              color: AppTheme.primary,
              onPressed: onPressed,
            ),
          );
        }
        return SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            icon: Icon(isPremium
                ? Icons.table_chart_outlined
                : Icons.lock_outline_rounded),
            label: Text(_label),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppTheme.primary,
              side: BorderSide(color: AppTheme.primary),
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppRadius.xl)),
            ),
            onPressed: onPressed,
          ),
        );
      },
    );
  }

  Future<void> _exportCsv(BuildContext context) async {
    final symbol = FlavorConfig.currencySymbol;
    String fmt(double v) =>
        NumberFormat.currency(symbol: symbol, decimalDigits: 2).format(v);

    final federalLabel = FlavorConfig.isUK
        ? 'Income Tax'
        : (fr ? 'Impôt fédéral' : (es ? 'Impuesto federal' : 'Federal Tax'));
    final ficaLabel = FlavorConfig.isUS
        ? 'FICA (SS + Medicare)'
        : (FlavorConfig.isUK
            ? (ukStudentLoanNotifier.value
                ? 'NI + Student Loan'
                : 'National Insurance')
            : (fr ? 'RPC + AE' : 'CPP + EI'));
    final stateLabel = FlavorConfig.isUS
        ? (es ? 'Impuesto estatal' : 'State Tax')
        : (fr ? 'Impôt provincial' : 'Provincial Tax');
    final grossLabel =
        fr ? 'Salaire brut' : (es ? 'Salario bruto' : 'Gross Salary');
    final totalLabel =
        fr ? 'Total impôts' : (es ? 'Total impuestos' : 'Total Tax');
    final rateLabel =
        fr ? 'Taux effectif' : (es ? 'Tasa efectiva' : 'Effective Tax Rate');
    final netAnnualLabel =
        fr ? 'Salaire net annuel' : (es ? 'Salario neto anual' : 'Net Annual');
    final netMonthlyLabel =
        fr ? 'Net mensuel' : (es ? 'Neto mensual' : 'Net Monthly');
    final netBiWeeklyLabel =
        fr ? 'Net bimensuel' : (es ? 'Neto quincenal' : 'Net Bi-Weekly');
    final netWeeklyLabel =
        fr ? 'Net hebdomadaire' : (es ? 'Neto semanal' : 'Net Weekly');
    final labelHeader = fr ? 'Catégorie' : (es ? 'Categoría' : 'Category');
    final valueHeader = fr ? 'Montant' : (es ? 'Monto' : 'Amount');

    final rows = <String>[
      '$labelHeader,$valueHeader',
      '$grossLabel,${fmt(result.grossAnnual)}',
      '$federalLabel,${fmt(result.federalTax)}',
      if (result.ficaTax > 0) '$ficaLabel,${fmt(result.ficaTax)}',
      if (!FlavorConfig.isUK && result.stateTax > 0)
        '$stateLabel,${fmt(result.stateTax)}',
      '$totalLabel,${fmt(result.totalTax)}',
      '$rateLabel,${result.effectiveRate.toStringAsFixed(2)}%',
      '$netAnnualLabel,${fmt(result.netAnnual)}',
      '$netMonthlyLabel,${fmt(result.netMonthly)}',
      '$netBiWeeklyLabel,${fmt(result.netBiWeekly)}',
      '$netWeeklyLabel,${fmt(result.netWeekly)}',
    ];

    final csv = rows.join('\n');
    final filename =
        'salary_summary_${DateTime.now().millisecondsSinceEpoch}.csv';

    try {
      final bytes = Uint8List.fromList(csv.codeUnits);
      await Share.shareXFiles(
        [XFile.fromData(bytes, name: filename, mimeType: 'text/csv')],
        subject: filename,
      );
      analyticsService.logResultShared();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(fr
                ? 'CSV exporté avec succès'
                : es
                    ? 'CSV exportado con éxito'
                    : 'CSV exported successfully'),
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(fr
                ? 'Erreur lors de l\'export'
                : es
                    ? 'Error al exportar'
                    : 'Export failed'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }
}

// ─── Pay Rate Converter ───────────────────────────────────────────────────────

class _PayRateConverter extends StatelessWidget {
  final SalaryResult result;
  final bool fr, es;

  const _PayRateConverter({
    required this.result,
    required this.fr,
    required this.es,
  });

  static const _workingDays = 260.0;
  static const _workingHours = 2080.0;

  String _fmt(double v) => _currencyFmt2.format(v);

  @override
  Widget build(BuildContext context) {
    final gross = result.grossAnnual;
    // Use the actual calculated effective tax rate instead of a flat 25% estimate
    final effRate = result.effectiveRate / 100.0;
    final effPct = result.effectiveRate.toStringAsFixed(1);
    final title = fr
        ? 'Répartition salariale'
        : (es ? 'Desglose de salario' : 'Pay Rate Breakdown');
    final grossLabel = fr ? 'Brut' : (es ? 'Bruto' : 'Gross');
    final netLabel = fr ? 'Net estimé*' : (es ? 'Neto estimado*' : 'Est. Net*');
    final periodLabel = fr ? 'Période' : (es ? 'Período' : 'Period');
    final taxNote = fr
        ? '* Estimation après $effPct % de taux effectif'
        : (es
            ? '* Estimación con tasa efectiva de $effPct %'
            : '* Estimated after $effPct% effective tax rate');

    final rows = <_RateRow>[
      _RateRow(
        period: fr ? 'Annuel' : (es ? 'Anual' : 'Annual'),
        gross: gross,
        net: gross * (1 - effRate),
      ),
      _RateRow(
        period: fr ? 'Mensuel' : (es ? 'Mensual' : 'Monthly'),
        gross: gross / 12,
        net: gross * (1 - effRate) / 12,
      ),
      _RateRow(
        period: fr ? 'Bimensuel' : (es ? 'Quincenal' : 'Bi-weekly'),
        gross: gross / 26,
        net: gross * (1 - effRate) / 26,
      ),
      _RateRow(
        period: fr ? 'Hebdomadaire' : (es ? 'Semanal' : 'Weekly'),
        gross: gross / 52,
        net: gross * (1 - effRate) / 52,
      ),
      _RateRow(
        period:
            fr ? 'Journalier (÷260)' : (es ? 'Diario (÷260)' : 'Daily (÷260)'),
        gross: gross / _workingDays,
        net: gross * (1 - effRate) / _workingDays,
      ),
      _RateRow(
        period: fr
            ? 'Horaire (÷2080)'
            : (es ? 'Por hora (÷2080)' : 'Hourly (÷2080)'),
        gross: gross / _workingHours,
        net: gross * (1 - effRate) / _workingHours,
      ),
    ];

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.xl),
        side: BorderSide(color: CalcwiseTheme.of(context).cardBorder),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(Icons.swap_horiz_rounded, size: 18, color: AppTheme.primary),
              SizedBox(width: 8),
              Text(title,
                  style: TextStyle(
                      fontSize: AppTextSize.bodyMd,
                      fontWeight: FontWeight.w600)),
            ]),
            SizedBox(height: AppSpacing.md),
            Table(
              columnWidths: const {
                0: FlexColumnWidth(3),
                1: FlexColumnWidth(3),
                2: FlexColumnWidth(3),
              },
              children: [
                TableRow(
                  decoration: BoxDecoration(
                      border:
                          Border(bottom: BorderSide(color: AppTheme.divider))),
                  children: [
                    _th(periodLabel),
                    _th(grossLabel),
                    _th(netLabel),
                  ],
                ),
                for (final row in rows)
                  TableRow(children: [
                    _td(row.period),
                    _td(_fmt(row.gross)),
                    _td(_fmt(row.net), color: AppTheme.success),
                  ]),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(taxNote,
                style: TextStyle(
                    fontSize: AppTextSize.xs,
                    color: AppTheme.labelGray,
                    fontStyle: FontStyle.italic)),
          ],
        ),
      ),
    );
  }

  Widget _th(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(text,
            style: TextStyle(
                fontSize: AppTextSize.xs,
                fontWeight: FontWeight.w700,
                color: AppTheme.labelGray)),
      );

  Widget _td(String text, {Color? color}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 7),
        child: Text(text,
            style: TextStyle(
                fontSize: AppTextSize.sm,
                fontWeight: FontWeight.w600,
                color: color)),
      );
}

class _RateRow {
  final String period;
  final double gross, net;
  const _RateRow(
      {required this.period, required this.gross, required this.net});
}

// ─── CA: Reverse-calculation mode toggle ─────────────────────────────────────

class _CaReverseModeToggle extends StatelessWidget {
  final bool reverseMode;
  final ValueChanged<bool> onChanged;

  const _CaReverseModeToggle({
    required this.reverseMode,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: isSpanishNotifier,
      builder: (context, useAlt, _) {
        final fr = FlavorConfig.isCA && useAlt;
        return SwitchListTile.adaptive(
          contentPadding: EdgeInsets.zero,
          dense: true,
          title: Text(
            reverseMode
                ? (fr ? 'Calculer depuis le net' : 'Calculate from net')
                : (fr ? 'Calculer depuis le brut' : 'Calculate from gross'),
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          subtitle: Text(
            reverseMode
                ? (fr
                    ? 'Entrez le salaire net souhaité — obtenez le brut requis'
                    : 'Enter desired take-home — get required gross')
                : (fr
                    ? 'Entrez le salaire brut — obtenez le net'
                    : 'Enter gross salary — get take-home pay'),
            style: Theme.of(context).textTheme.bodySmall,
          ),
          value: reverseMode,
          activeColor: AppTheme.primary,
          onChanged: onChanged,
        );
      },
    );
  }
}

// ─── CA: Reverse-calculation result banner ────────────────────────────────────

class _CaReverseResultBanner extends StatelessWidget {
  final double requiredGross;
  final double targetNet;
  final bool fr;

  const _CaReverseResultBanner({
    required this.requiredGross,
    required this.targetNet,
    required this.fr,
  });

  @override
  Widget build(BuildContext context) {
    final grossFmt = _currencyFmt0.format(requiredGross);
    final netFmt = _currencyFmt0.format(targetNet);
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppTheme.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppTheme.primary.withValues(alpha: 0.30)),
      ),
      child: Row(
        children: [
          Icon(Icons.swap_vert_rounded, color: AppTheme.primary, size: 22),
          SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  fr ? 'Salaire brut requis' : 'Required gross salary',
                  style: TextStyle(
                      fontSize: AppTextSize.sm, color: AppTheme.labelGray),
                ),
                Text(
                  grossFmt,
                  style: TextStyle(
                      fontSize: AppTextSize.bodyXl,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.primary),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  fr
                      ? 'Pour obtenir un net de $netFmt'
                      : 'To achieve a take-home of $netFmt',
                  style: TextStyle(
                      fontSize: AppTextSize.sm, color: AppTheme.labelGray),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── UK: Salary sacrifice savings banner ─────────────────────────────────────

class _UkSalarySacrificeSavingsBanner extends StatelessWidget {
  final double grossAnnual;
  final double salarySacrifice;
  final bool scotland;

  const _UkSalarySacrificeSavingsBanner({
    required this.grossAnnual,
    required this.salarySacrifice,
    required this.scotland,
  });

  @override
  Widget build(BuildContext context) {
    final (taxSaving, niSaving) = UkSalaryEngine.salarySacrificeSavings(
      grossAnnual,
      salarySacrifice,
      scotland: scotland,
    );
    final totalSaving = taxSaving + niSaving;
    if (totalSaving <= 0) return const SizedBox.shrink();

    final taxFmt = _currencyFmt0.format(taxSaving);
    final niFmt = _currencyFmt0.format(niSaving);
    final totalFmt = _currencyFmt0.format(totalSaving);
    final sacrificeFmt = _currencyFmt0.format(salarySacrifice);

    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppTheme.success.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppTheme.success.withValues(alpha: 0.30)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(Icons.savings_rounded, color: AppTheme.success, size: 18),
            SizedBox(width: 8),
            Text(
              'Salary Sacrifice / SMART Pension Savings',
              style: TextStyle(
                  fontSize: AppTextSize.bodyMd,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.success),
            ),
          ]),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'On $sacrificeFmt sacrifice you save:',
            style:
                TextStyle(fontSize: AppTextSize.sm, color: AppTheme.labelGray),
          ),
          SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(child: Text('Income tax saved',
                  style: TextStyle(fontSize: AppTextSize.sm),
                  overflow: TextOverflow.ellipsis)),
              const SizedBox(width: 8),
              Text(taxFmt,
                  style: TextStyle(
                      fontSize: AppTextSize.sm,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.success)),
            ],
          ),
          SizedBox(height: 2),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(child: Text('NI saved',
                  style: TextStyle(fontSize: AppTextSize.sm),
                  overflow: TextOverflow.ellipsis)),
              const SizedBox(width: 8),
              Text(niFmt,
                  style: TextStyle(
                      fontSize: AppTextSize.sm,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.success)),
            ],
          ),
          Divider(height: 16, color: AppTheme.success.withValues(alpha: 0.20)),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(child: Text('Total savings',
                  style: TextStyle(
                      fontSize: AppTextSize.bodyMd,
                      fontWeight: FontWeight.w700),
                  overflow: TextOverflow.ellipsis)),
              const SizedBox(width: 8),
              Text(totalFmt,
                  style: TextStyle(
                      fontSize: AppTextSize.bodyMd,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.success)),
            ],
          ),
        ],
      ),
    );
  }
}

// ─── UK: Salary sacrifice input field ────────────────────────────────────────

class _SalarySacrificeField extends StatelessWidget {
  final TextEditingController controller;
  final ValueChanged<double> onChanged;

  const _SalarySacrificeField({
    required this.controller,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: InputDecoration(
        labelText: 'Salary Sacrifice / SMART Pension',
        prefixText: '£ ',
        prefixIcon: const Icon(Icons.savings_outlined),
        helperText: 'Pre-tax, pre-NI annual deduction',
        hintText: '0',
      ),
      onChanged: (v) {
        final parsed = double.tryParse(v.replaceAll(',', '')) ?? 0;
        onChanged(parsed);
      },
    );
  }
}

// ─── UK: Reverse-calculation toggle (net → gross) ────────────────────────────

class _UkReverseModeToggle extends StatelessWidget {
  final bool reverseMode;
  final ValueChanged<bool> onChanged;

  const _UkReverseModeToggle({
    required this.reverseMode,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return SwitchListTile.adaptive(
      contentPadding: EdgeInsets.zero,
      dense: true,
      title: Text(
        reverseMode ? 'Calculate from take-home' : 'Calculate from gross',
        style: Theme.of(context).textTheme.bodyMedium,
      ),
      subtitle: Text(
        reverseMode
            ? 'Enter desired take-home — get required gross'
            : 'Enter gross salary — get take-home pay',
        style: Theme.of(context).textTheme.bodySmall,
      ),
      value: reverseMode,
      activeColor: AppTheme.primary,
      onChanged: onChanged,
    );
  }
}

// ─── UK: HMRC tax code field ─────────────────────────────────────────────────

class _UkTaxCodeField extends StatelessWidget {
  final TextEditingController controller;
  final VoidCallback onChanged;

  const _UkTaxCodeField({
    required this.controller,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      textCapitalization: TextCapitalization.characters,
      inputFormatters: [
        UpperCaseTextFormatter(),
        LengthLimitingTextInputFormatter(7),
      ],
      decoration: const InputDecoration(
        labelText: 'HMRC Tax Code',
        prefixIcon: Icon(Icons.badge_outlined),
        helperText: '1257L · BR · D0 · D1 · NT · 0T · K… (default 1257L)',
        hintText: '1257L',
      ),
      onChanged: (_) => onChanged(),
    );
  }
}

/// Uppercases tax-code input as the user types (HMRC codes are upper-case).
class UpperCaseTextFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) =>
      TextEditingValue(
        text: newValue.text.toUpperCase(),
        selection: newValue.selection,
      );
}

// ─── UK student-loan plan dropdown ───────────────────────────────────────────

class _UkLoanPlanDropdown extends StatelessWidget {
  /// 0 = None, otherwise the plan number (1, 2, 4, 5).
  final int plan;
  final ValueChanged<int> onChanged;

  const _UkLoanPlanDropdown({required this.plan, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<int>(
      initialValue: plan,
      decoration: const InputDecoration(
        labelText: 'Student Loan Plan',
        prefixIcon: Icon(Icons.school_outlined),
        helperText: 'Plans 1/2/4/5 repay 9% above threshold',
      ),
      items: const [
        DropdownMenuItem(value: 0, child: Text('None')),
        DropdownMenuItem(value: 1, child: Text('Plan 1 (£24,990)')),
        DropdownMenuItem(value: 2, child: Text('Plan 2 (£27,295)')),
        DropdownMenuItem(value: 4, child: Text('Plan 4 — Scotland (£31,395)')),
        DropdownMenuItem(value: 5, child: Text('Plan 5 (£25,000)')),
      ],
      onChanged: (v) => onChanged(v ?? 0),
    );
  }
}

// ─── Second-income section (multi-jobs, premium) ─────────────────────────────

class _SecondIncomeSection extends StatelessWidget {
  final bool enabled;
  final TextEditingController controller;
  final bool es, fr;
  final ValueChanged<bool> onToggle;
  final ValueChanged<double> onAmountChanged;

  const _SecondIncomeSection({
    required this.enabled,
    required this.controller,
    required this.es,
    required this.fr,
    required this.onToggle,
    required this.onAmountChanged,
  });

  @override
  Widget build(BuildContext context) {
    final isPremium = freemiumService.hasFullAccess;
    final title = fr
        ? 'Ajouter un 2ᵉ revenu'
        : (es ? 'Agregar 2.º ingreso' : 'Add second income');
    final subtitle = fr
        ? 'L\'impôt est calculé sur le revenu total cumulé'
        : (es
            ? 'El impuesto se calcula sobre el ingreso total combinado'
            : 'Tax is calculated on the combined total income');
    final fieldLabel = fr
        ? 'Revenu annuel du 2ᵉ emploi'
        : (es ? 'Ingreso anual del 2.º empleo' : 'Second job annual income');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SwitchListTile.adaptive(
          contentPadding: EdgeInsets.zero,
          dense: true,
          secondary: isPremium
              ? null
              : const Icon(Icons.lock_outline_rounded, size: 18),
          title: Text(title,
              style: Theme.of(context).textTheme.bodyMedium),
          subtitle: Text(subtitle,
              style: Theme.of(context).textTheme.bodySmall),
          value: enabled,
          activeColor: AppTheme.primary,
          onChanged: onToggle,
        ),
        if (enabled) ...[
          SizedBox(height: AppSpacing.xs),
          TextFormField(
            controller: controller,
            keyboardType:
                const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              CurrencyInputFormatter(
                  locale: FlavorConfig.isCA
                      ? 'en_CA'
                      : (FlavorConfig.isUK ? 'en_GB' : 'en_US')),
            ],
            decoration: InputDecoration(
              labelText: fieldLabel,
              prefixText: '${FlavorConfig.currencySymbol} ',
              prefixIcon: const Icon(Icons.work_outline_rounded),
              hintText: '0',
            ),
            onChanged: (v) {
              final parsed =
                  double.tryParse(v.replaceAll(RegExp(r'[,\s]'), '')) ?? 0;
              onAmountChanged(parsed);
            },
          ),
        ],
      ],
    );
  }
}
