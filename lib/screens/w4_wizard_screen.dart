import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:printing/printing.dart';
import 'package:pdf/widgets.dart' as pw;

import '../core/flavor_config.dart';
import '../core/freemium/freemium_service.dart';
import '../core/freemium/iap_service.dart';
import '../core/theme/app_theme.dart';
import '../core/analytics/analytics_service.dart';
import '../main.dart' show isSpanishNotifier, salaryNotifier, historyService, paywallSession;
import '../widgets/paywall_hard.dart';
import '../widgets/result_card.dart';
import '../widgets/save_scenario_button.dart';
import 'package:calcwise_core/calcwise_core.dart' show CalcwiseAdFooter;
import 'package:calcwise_core/calcwise_core.dart';

// ─── W-4 Withholding Wizard (US flavor only) ──────────────────────────────────
//
// Multi-step wizard implementing IRS 2025 Publication 15-T / W-4 worksheet:
//   Step 1 → Filing status & multiple-jobs income
//   Step 2 → Dependents, other deductions, extra withholding
//   Step 3 → Results with recommended W-4 amounts + refund estimate

// ─── Data model ───────────────────────────────────────────────────────────────

enum _FilingStatus { single, marriedJointly, headOfHousehold }

class _W4Result {
  /// IRS W-4 Step 3 amount: dependent credits
  final double step3DependentCredit;

  /// IRS W-4 Step 4(b): additional deductions beyond standard deduction
  final double step4bDeductions;

  /// IRS W-4 Step 4(c): extra withholding per paycheck
  final double step4cExtra;

  /// Estimated total annual federal income tax liability
  final double estimatedAnnualTax;

  /// Estimated annual withholding with these W-4 settings
  final double estimatedWithholding;

  /// Positive = expected refund; negative = expected owed
  final double refundOrOwed;

  const _W4Result({
    required this.step3DependentCredit,
    required this.step4bDeductions,
    required this.step4cExtra,
    required this.estimatedAnnualTax,
    required this.estimatedWithholding,
    required this.refundOrOwed,
  });
}

// ─── IRS 2025 W-4 worksheet logic ─────────────────────────────────────────────

class _W4Engine {
  _W4Engine._();

  /// 2025 standard deductions
  static double standardDeduction(_FilingStatus status) {
    switch (status) {
      case _FilingStatus.single:
        return 15000;
      case _FilingStatus.marriedJointly:
        return 30000;
      case _FilingStatus.headOfHousehold:
        return 22500;
    }
  }

  /// 2025 federal tax using the correct brackets for each filing status.
  /// [taxableIncome] is income AFTER subtracting the standard deduction.
  static double federalTaxForStatus(
      double taxableIncome, _FilingStatus status) {
    if (taxableIncome <= 0) return 0;
    switch (status) {
      case _FilingStatus.single:
        // 2025 single brackets applied to taxable income
        if (taxableIncome <= 11925) return taxableIncome * 0.10;
        if (taxableIncome <= 48475)
          return 1192.5 + (taxableIncome - 11925) * 0.12;
        if (taxableIncome <= 103350)
          return 5578.5 + (taxableIncome - 48475) * 0.22;
        if (taxableIncome <= 197300)
          return 17651 + (taxableIncome - 103350) * 0.24;
        if (taxableIncome <= 250525)
          return 40199 + (taxableIncome - 197300) * 0.32;
        if (taxableIncome <= 626350)
          return 57231 + (taxableIncome - 250525) * 0.35;
        return 188769.75 + (taxableIncome - 626350) * 0.37;
      case _FilingStatus.marriedJointly:
        // MFJ 2025 brackets (taxable income after $30,000 standard deduction)
        if (taxableIncome <= 23850) return taxableIncome * 0.10;
        if (taxableIncome <= 96950)
          return 2385 + (taxableIncome - 23850) * 0.12;
        if (taxableIncome <= 206700)
          return 11157 + (taxableIncome - 96950) * 0.22;
        if (taxableIncome <= 394600)
          return 35302 + (taxableIncome - 206700) * 0.24;
        if (taxableIncome <= 501050)
          return 80398 + (taxableIncome - 394600) * 0.32;
        if (taxableIncome <= 751600)
          return 114462 + (taxableIncome - 501050) * 0.35;
        return 202154.5 + (taxableIncome - 751600) * 0.37;
      case _FilingStatus.headOfHousehold:
        // HoH 2025 brackets (taxable income after $22,500 standard deduction)
        if (taxableIncome <= 17000) return taxableIncome * 0.10;
        if (taxableIncome <= 64850)
          return 1700 + (taxableIncome - 17000) * 0.12;
        if (taxableIncome <= 103350)
          return 7442 + (taxableIncome - 64850) * 0.22;
        if (taxableIncome <= 197300)
          return 15912 + (taxableIncome - 103350) * 0.24;
        if (taxableIncome <= 250500)
          return 38460 + (taxableIncome - 197300) * 0.32;
        if (taxableIncome <= 626350)
          return 55484 + (taxableIncome - 250500) * 0.35;
        return 187031.5 + (taxableIncome - 626350) * 0.37;
    }
  }

  /// Pay periods per year for common frequencies.
  static int payPeriods(String frequency) {
    switch (frequency) {
      case 'weekly':
        return 52;
      case 'biweekly':
        return 26;
      case 'semimonthly':
        return 24;
      case 'monthly':
        return 12;
      default:
        return 26;
    }
  }

  static _W4Result calculate({
    required double grossAnnual,
    required double spouseAnnual,
    required _FilingStatus status,
    required bool multipleJobs,
    required int qualifyingChildren,
    required int otherDependents,
    required double otherDeductions,
    required double extraWithholdingPerPaycheck,
    required String payFrequency,
  }) {
    // Combined household income for MFJ / multiple-jobs
    final totalIncome = grossAnnual +
        (multipleJobs && status == _FilingStatus.marriedJointly
            ? spouseAnnual
            : 0);

    // W-4 Step 3: dependent credits
    final childCredit = qualifyingChildren * 2000.0;
    final otherCredit = otherDependents * 500.0;
    final step3 = childCredit + otherCredit;

    // W-4 Step 4(b): itemized / other deductions above standard deduction
    final stdDed = standardDeduction(status);
    final step4b = otherDeductions > stdDed ? otherDeductions - stdDed : 0.0;

    // W-4 Step 4(c): extra per paycheck
    final step4c = extraWithholdingPerPaycheck;

    // ── Estimate actual tax liability ────────────────────────────────────────
    final taxableIncome =
        (totalIncome - stdDed - step4b).clamp(0.0, double.infinity);
    final rawTax = federalTaxForStatus(taxableIncome, status);
    // Subtract child/other dependent credits (limited to tax owed)
    final estimatedTax = (rawTax - step3).clamp(0.0, double.infinity);

    // ── Estimate annual withholding with these W-4 settings ──────────────────
    // With a properly filled W-4 (step 3 + step 4b + step 4c applied),
    // the employer withholds ≈ estimated tax.  Any extra per paycheck is on top.
    final periods = payPeriods(payFrequency);
    final extraAnnual = step4c * periods;
    // Withholding ≈ estimatedTax + any voluntary extra
    final estimatedWithholding = estimatedTax + extraAnnual;

    // Refund (positive) or owed (negative):
    // With correct W-4 settings the refund should be ~$0 plus any extra.
    // We expose this as the extra annual contribution so users see the impact.
    final refundOrOwed = extraAnnual; // positive = refund from over-withholding

    return _W4Result(
      step3DependentCredit: step3,
      step4bDeductions: step4b,
      step4cExtra: step4c,
      estimatedAnnualTax: estimatedTax,
      estimatedWithholding: estimatedWithholding,
      refundOrOwed: refundOrOwed,
    );
  }
}

// ─── Screen ───────────────────────────────────────────────────────────────────

class W4WizardScreen extends StatefulWidget {
  const W4WizardScreen({super.key});

  @override
  State<W4WizardScreen> createState() => _W4WizardScreenState();
}

class _W4WizardScreenState extends State<W4WizardScreen> {
  final _pageCtrl = PageController();
  int _step = 0; // 0, 1, 2

  // ── Step 1 state ────────────────────────────────────────────────────────────
  _FilingStatus _filingStatus = _FilingStatus.single;
  bool _multipleJobs = false;
  final _salaryCtrl = TextEditingController();
  final _spouseCtrl = TextEditingController();
  String _payFrequency = 'biweekly';

  // ── Step 2 state ────────────────────────────────────────────────────────────
  int _qualifyingChildren = 0;
  int _otherDependents = 0;
  final _deductionsCtrl = TextEditingController(text: '0');
  final _extraCtrl = TextEditingController(text: '0');

  // ── Result ──────────────────────────────────────────────────────────────────
  _W4Result? _result;

  @override
  void initState() {
    super.initState();
    final salary = salaryNotifier.value;
    _salaryCtrl.text = salary > 0 ? salary.toStringAsFixed(0) : '75000';

    // Hard premium gate: show PaywallHard immediately if user is not premium.
    // The tools_screen already gates entry, but this guards direct/deep navigation.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      analyticsService.logScreenView('w4_wizard');
      if (!freemiumService.hasFullAccess) {
        final es = FlavorConfig.isUS && isSpanishNotifier.value;
        PaywallHard.show(
          context,
          isSpanish: es,
          priceLabel: IAPService.instance.localizedPrice.value,
          onPurchase: IAPService.instance.buy,
        );
      }
    });
  }

  @override
  void dispose() {
    historyService.cancelPendingSave('salaryapp', 'w4_wizard');
    _pageCtrl.dispose();
    _salaryCtrl.dispose();
    _spouseCtrl.dispose();
    _deductionsCtrl.dispose();
    _extraCtrl.dispose();
    super.dispose();
  }

  // ── SmartHistory helpers ──────────────────────────────────────────────────

  double _roundTo(double v, double step) => (v / step).round() * step;

  String _buildHash() {
    final salary = _parse(_salaryCtrl);
    return ResultHasher.hashMixed({
      'flavor': 'us',
      'salary': _roundTo(salary, 1000),
      'filing': _filingStatus.name,
      'children': _qualifyingChildren,
      'other_deps': _otherDependents,
    });
  }

  Map<String, dynamic> _buildL1() {
    final r = _result;
    if (r == null) return {};
    return {
      'salary': _parse(_salaryCtrl),
      'filing': _filingStatus.name,
      'step3_credit': r.step3DependentCredit,
      'est_annual_tax': r.estimatedAnnualTax,
    };
  }

  Map<String, dynamic> _buildL2() {
    final r = _result;
    if (r == null) return {};
    return {
      'inputs': {
        'salary': _parse(_salaryCtrl),
        'spouse': _parse(_spouseCtrl),
        'filing': _filingStatus.name,
        'multiple_jobs': _multipleJobs,
        'children': _qualifyingChildren,
        'other_deps': _otherDependents,
        'deductions': _parse(_deductionsCtrl),
        'extra_per_paycheck': _parse(_extraCtrl),
        'pay_frequency': _payFrequency,
      },
      'results': {
        'step3_credit': r.step3DependentCredit,
        'step4b_deductions': r.step4bDeductions,
        'step4c_extra': r.step4cExtra,
        'est_annual_tax': r.estimatedAnnualTax,
        'est_withholding': r.estimatedWithholding,
        'refund_or_owed': r.refundOrOwed,
      },
    };
  }

  void _scheduleAutoSave() {
    if (_result == null || _step != 2) return;
    historyService.scheduleAutoSave(
      appKey: 'salaryapp',
      screenId: 'w4_wizard',
      inputHash: _buildHash(),
      l1: _buildL1(),
      l2: _buildL2(),
      onSaved: () { if (mounted) setState(() {}); },
    );
  }

  Future<void> _saveScenario(String? label) async {
    if (_result == null) return;
    await historyService.saveScenario(
      appKey: 'salaryapp',
      screenId: 'w4_wizard',
      inputHash: _buildHash(),
      l1: _buildL1(),
      l2: _buildL2(),
      label: label,
    );
  }

  double _parse(TextEditingController c) {
    final raw = c.text.replaceAll(',', '').replaceAll(RegExp(r'[^\d.]'), '');
    return double.tryParse(raw) ?? 0;
  }

  void _nextStep() {
    if (_step < 2) {
      setState(() => _step++);
      _pageCtrl.animateToPage(
        _step,
        duration: AppDuration.page,
        curve: Curves.easeInOut,
      );
    }
  }

  void _prevStep() {
    if (_step > 0) {
      setState(() => _step--);
      _pageCtrl.animateToPage(
        _step,
        duration: AppDuration.page,
        curve: Curves.easeInOut,
      );
    }
  }

  void _calculate() {
    HapticFeedback.mediumImpact();
    FocusScope.of(context).unfocus();
    final result = _W4Engine.calculate(
      grossAnnual: _parse(_salaryCtrl),
      spouseAnnual: _parse(_spouseCtrl),
      status: _filingStatus,
      multipleJobs: _multipleJobs,
      qualifyingChildren: _qualifyingChildren,
      otherDependents: _otherDependents,
      otherDeductions: _parse(_deductionsCtrl),
      extraWithholdingPerPaycheck: _parse(_extraCtrl),
      payFrequency: _payFrequency,
    );
    setState(() => _result = result);
    _nextStep(); // advances _step to 2 — _scheduleAutoSave checks _step == 2
    _scheduleAutoSave();
    paywallSession.recordAction();
  }

  @override
  Widget build(BuildContext context) {
    // Defensive guard — W-4 is a US-only IRS form. Should not be reachable
    // on CA/UK flavors but guard here prevents any navigation bypass.
    if (!FlavorConfig.isUS) {
      return const Scaffold(
        body: Center(child: Text('W-4 is only available in the US version.')),
      );
    }
    return ValueListenableBuilder<bool>(
      valueListenable: isSpanishNotifier,
      builder: (context, useAlt, _) {
        final es = FlavorConfig.isUS && useAlt;

        final title = es ? 'Asistente W-4 2025' : 'W-4 Withholding Wizard 2025';
        final stepLabels = es
            ? ['Estado', 'Deducciones', 'Resultados']
            : ['Filing Status', 'Deductions', 'Results'];

        return Scaffold(
          appBar: AppBar(
            title: Text(title),
            leading: _step > 0
                ? IconButton(
                    icon: const Icon(Icons.arrow_back_rounded),
                    onPressed: _prevStep,
                  )
                : null,
          ),
          body: Column(
            children: [
              _StepIndicator(
                currentStep: _step,
                labels: stepLabels,
              ),
              Expanded(
                child: PageView(
                  controller: _pageCtrl,
                  physics: const NeverScrollableScrollPhysics(),
                  children: [
                    _Step1FilingStatus(
                      filingStatus: _filingStatus,
                      multipleJobs: _multipleJobs,
                      salaryCtrl: _salaryCtrl,
                      spouseCtrl: _spouseCtrl,
                      payFrequency: _payFrequency,
                      es: es,
                      onFilingStatusChanged: (v) =>
                          setState(() => _filingStatus = v),
                      onMultipleJobsChanged: (v) =>
                          setState(() => _multipleJobs = v),
                      onPayFrequencyChanged: (v) =>
                          setState(() => _payFrequency = v),
                      onNext: _nextStep,
                    ),
                    _Step2Deductions(
                      qualifyingChildren: _qualifyingChildren,
                      otherDependents: _otherDependents,
                      deductionsCtrl: _deductionsCtrl,
                      extraCtrl: _extraCtrl,
                      es: es,
                      onQualifyingChildrenChanged: (v) =>
                          setState(() => _qualifyingChildren = v),
                      onOtherDependentsChanged: (v) =>
                          setState(() => _otherDependents = v),
                      onCalculate: _calculate,
                    ),
                    _Step3Results(
                      result: _result,
                      payFrequency: _payFrequency,
                      es: es,
                      onSave: _result != null &&
                              (freemiumService.hasFullAccess ||
                                  freemiumService.isRewarded)
                          ? _saveScenario
                          : null,
                      onRestart: () {
                        setState(() {
                          _step = 0;
                          _result = null;
                        });
                        _pageCtrl.jumpToPage(0);
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

// ─── Step indicator ───────────────────────────────────────────────────────────

class _StepIndicator extends StatelessWidget {
  final int currentStep;
  final List<String> labels;

  const _StepIndicator({required this.currentStep, required this.labels});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(bottom: BorderSide(color: AppTheme.divider)),
      ),
      child: Row(
        children: List.generate(labels.length, (i) {
          final isActive = i == currentStep;
          final isDone = i < currentStep;
          return Expanded(
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            width: 28,
                            height: 28,
                            decoration: BoxDecoration(
                              color: isDone
                                  ? AppTheme.success
                                  : (isActive
                                      ? AppTheme.primary
                                      : AppTheme.divider),
                              shape: BoxShape.circle,
                            ),
                            child: Center(
                              child: isDone
                                  ? const Icon(Icons.check_rounded,
                                      color: Colors.white, size: 14)
                                  : Text(
                                      '${i + 1}',
                                      style: TextStyle(
                                        color: isActive
                                            ? Colors.white
                                            : AppTheme.labelGray,
                                        fontSize: AppTextSize.sm,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        labels[i],
                        style: TextStyle(
                          fontSize: AppTextSize.xs,
                          color:
                              isActive ? AppTheme.primary : AppTheme.labelGray,
                          fontWeight:
                              isActive ? FontWeight.w700 : FontWeight.normal,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
                if (i < labels.length - 1)
                  Container(
                    height: 2,
                    width: 20,
                    color: isDone ? AppTheme.success : AppTheme.divider,
                  ),
              ],
            ),
          );
        }),
      ),
    );
  }
}

// ─── Step 1: Filing Status & Income ──────────────────────────────────────────

class _Step1FilingStatus extends StatelessWidget {
  final _FilingStatus filingStatus;
  final bool multipleJobs;
  final TextEditingController salaryCtrl;
  final TextEditingController spouseCtrl;
  final String payFrequency;
  final bool es;
  final ValueChanged<_FilingStatus> onFilingStatusChanged;
  final ValueChanged<bool> onMultipleJobsChanged;
  final ValueChanged<String> onPayFrequencyChanged;
  final VoidCallback onNext;

  const _Step1FilingStatus({
    required this.filingStatus,
    required this.multipleJobs,
    required this.salaryCtrl,
    required this.spouseCtrl,
    required this.payFrequency,
    required this.es,
    required this.onFilingStatusChanged,
    required this.onMultipleJobsChanged,
    required this.onPayFrequencyChanged,
    required this.onNext,
  });

  static const _freqKeys = [
    'weekly',
    'biweekly',
    'semimonthly',
    'monthly',
  ];

  List<String> _freqLabels(bool es) => es
      ? ['Semanal', 'Quincenal', 'Semimensual', 'Mensual']
      : ['Weekly', 'Bi-weekly', 'Semi-monthly', 'Monthly'];

  List<String> _statusLabels(bool es) => es
      ? [
          'Soltero / Casado por separado',
          'Casado conjuntamente',
          'Cabeza de familia',
        ]
      : [
          'Single / Married filing separately',
          'Married filing jointly',
          'Head of household',
        ];

  @override
  Widget build(BuildContext context) {
    final title = es ? 'Estado civil y salario' : 'Filing Status & Income';
    final salaryLabel =
        es ? 'Su salario anual bruto' : 'Your gross annual salary';
    final multipleJobsLabel = es
        ? '¿Empleos múltiples o cónyuge trabaja?'
        : 'Multiple jobs or spouse works?';
    final spouseLabel = es
        ? 'Salario anual del cónyuge (estimado)'
        : 'Spouse annual income (estimate)';
    final irsNote = es
        ? 'Con empleos múltiples, use la calculadora IRS online para mayor precisión.'
        : 'With multiple jobs, the IRS online estimator gives the most accurate result.';
    final freqLabel = es ? 'Frecuencia de pago' : 'Pay frequency';
    final nextLabel = es ? 'Siguiente' : 'Next';

    final statusLabels = _statusLabels(es);
    final freqLabels = _freqLabels(es);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: TextStyle(
                  fontSize: AppTextSize.bodyXl,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.primary)),
          const SizedBox(height: 16),

          // Filing status card
          Card(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    es ? 'Estado civil' : 'Filing Status',
                    style: TextStyle(
                        fontSize: AppTextSize.md,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.labelGray),
                  ),
                  const SizedBox(height: 8),
                  ...List.generate(_FilingStatus.values.length, (i) {
                    final status = _FilingStatus.values[i];
                    return RadioListTile<_FilingStatus>(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      value: status,
                      groupValue: filingStatus,
                      title: Text(statusLabels[i],
                          style: const TextStyle(fontSize: AppTextSize.body)),
                      activeColor: AppTheme.primary,
                      onChanged: (v) {
                        if (v != null) onFilingStatusChanged(v);
                      },
                    );
                  }),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),

          // Salary input
          Card(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextFormField(
                    controller: salaryCtrl,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[\d.,]')),
                    ],
                    decoration: InputDecoration(
                      labelText: salaryLabel,
                      prefixText: '\$ ',
                      hintText: '75000',
                    ),
                    style: const TextStyle(
                        fontSize: AppTextSize.bodyLg,
                        fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    freqLabel,
                    style: TextStyle(
                        fontSize: AppTextSize.md,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.labelGray),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: List.generate(_freqKeys.length, (i) {
                      final isSelected = payFrequency == _freqKeys[i];
                      return ChoiceChip(
                        label: Text(freqLabels[i]),
                        selected: isSelected,
                        selectedColor: AppTheme.primary,
                        labelStyle: TextStyle(
                          color: isSelected ? Colors.white : AppTheme.labelGray,
                          fontWeight:
                              isSelected ? FontWeight.w600 : FontWeight.normal,
                          fontSize: AppTextSize.md,
                        ),
                        onSelected: (_) => onPayFrequencyChanged(_freqKeys[i]),
                      );
                    }),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),

          // Multiple jobs toggle
          Card(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Column(
                children: [
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(multipleJobsLabel,
                        style: const TextStyle(fontSize: AppTextSize.body)),
                    value: multipleJobs,
                    activeColor: AppTheme.primary,
                    onChanged: onMultipleJobsChanged,
                  ),
                  if (multipleJobs) ...[
                    Container(
                      padding: const EdgeInsets.all(AppSpacing.smPlus),
                      margin: const EdgeInsets.only(bottom: 8),
                      decoration: BoxDecoration(
                        color: AppTheme.primary.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(AppRadius.md),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.info_outline,
                              size: 16, color: AppTheme.primary),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              irsNote,
                              style: TextStyle(
                                  fontSize: AppTextSize.sm,
                                  color: AppTheme.primary),
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (filingStatus == _FilingStatus.marriedJointly)
                      TextFormField(
                        controller: spouseCtrl,
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(RegExp(r'[\d.,]')),
                        ],
                        decoration: InputDecoration(
                          labelText: spouseLabel,
                          prefixText: '\$ ',
                          hintText: '55000',
                        ),
                        style: const TextStyle(
                            fontSize: AppTextSize.bodyLg,
                            fontWeight: FontWeight.w600),
                      ),
                    const SizedBox(height: 8),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),

          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () {
                if (salaryCtrl.text.trim().isEmpty) return;
                onNext();
              },
              child: Text(nextLabel,
                  style: const TextStyle(
                      fontSize: AppTextSize.bodyLg,
                      fontWeight: FontWeight.w700)),
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

// ─── Step 2: Deductions & Credits ────────────────────────────────────────────

class _Step2Deductions extends StatelessWidget {
  final int qualifyingChildren;
  final int otherDependents;
  final TextEditingController deductionsCtrl;
  final TextEditingController extraCtrl;
  final bool es;
  final ValueChanged<int> onQualifyingChildrenChanged;
  final ValueChanged<int> onOtherDependentsChanged;
  final VoidCallback onCalculate;

  const _Step2Deductions({
    required this.qualifyingChildren,
    required this.otherDependents,
    required this.deductionsCtrl,
    required this.extraCtrl,
    required this.es,
    required this.onQualifyingChildrenChanged,
    required this.onOtherDependentsChanged,
    required this.onCalculate,
  });

  @override
  Widget build(BuildContext context) {
    final title = es ? 'Dependientes y deducciones' : 'Dependents & Deductions';
    final childrenLabel = es
        ? 'Hijos menores de 17 años (\$2,000 c/u)'
        : 'Qualifying children under 17 (\$2,000 each)';
    final otherLabel =
        es ? 'Otros dependientes (\$500 c/u)' : 'Other dependents (\$500 each)';
    final childCredit = qualifyingChildren * 2000.0;
    final otherCredit = otherDependents * 500.0;
    final totalCredit = childCredit + otherCredit;
    final deductionsLabel = es
        ? 'Deducciones adicionales (préstamos estudiantiles, etc.)'
        : 'Other deductions (student loan interest, itemized, etc.)';
    final extraLabel = es
        ? 'Retención adicional por cheque (\$)'
        : 'Extra withholding per paycheck (\$)';
    final calcLabel = es ? 'Ver resultados W-4' : 'See W-4 Recommendations';

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: TextStyle(
                  fontSize: AppTextSize.bodyXl,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.primary)),
          const SizedBox(height: 16),

          // Dependents card
          Card(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Qualifying children
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(childrenLabel,
                                style:
                                    const TextStyle(fontSize: AppTextSize.md)),
                            Text(
                              '\$${NumberFormat.currency(symbol: '', decimalDigits: 0).format(childCredit)} credit',
                              style: TextStyle(
                                  fontSize: AppTextSize.sm,
                                  color: AppTheme.success,
                                  fontWeight: FontWeight.w600),
                            ),
                          ],
                        ),
                      ),
                      _CounterButtons(
                        value: qualifyingChildren,
                        onDecrement: () {
                          if (qualifyingChildren > 0) {
                            onQualifyingChildrenChanged(qualifyingChildren - 1);
                          }
                        },
                        onIncrement: () =>
                            onQualifyingChildrenChanged(qualifyingChildren + 1),
                      ),
                    ],
                  ),
                  const Divider(height: 24),

                  // Other dependents
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(otherLabel,
                                style:
                                    const TextStyle(fontSize: AppTextSize.md)),
                            Text(
                              '\$${NumberFormat.currency(symbol: '', decimalDigits: 0).format(otherCredit)} credit',
                              style: TextStyle(
                                  fontSize: AppTextSize.sm,
                                  color: AppTheme.success,
                                  fontWeight: FontWeight.w600),
                            ),
                          ],
                        ),
                      ),
                      _CounterButtons(
                        value: otherDependents,
                        onDecrement: () {
                          if (otherDependents > 0) {
                            onOtherDependentsChanged(otherDependents - 1);
                          }
                        },
                        onIncrement: () =>
                            onOtherDependentsChanged(otherDependents + 1),
                      ),
                    ],
                  ),
                  if (totalCredit > 0) ...[
                    const Divider(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Flexible(
                          child: Text(
                            es
                                ? 'Total créditos (W-4 Paso 3)'
                                : 'Total credits (W-4 Step 3)',
                            style: const TextStyle(
                                fontSize: AppTextSize.md,
                                fontWeight: FontWeight.w600),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '\$${NumberFormat.currency(symbol: '', decimalDigits: 0).format(totalCredit)}',
                          style: TextStyle(
                              fontSize: AppTextSize.body,
                              fontWeight: FontWeight.bold,
                              color: AppTheme.success),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),

          // Deductions card
          Card(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextFormField(
                    controller: deductionsCtrl,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[\d.,]')),
                    ],
                    decoration: InputDecoration(
                      labelText: deductionsLabel,
                      prefixText: '\$ ',
                      hintText: '0',
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: extraCtrl,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[\d.,]')),
                    ],
                    decoration: InputDecoration(
                      labelText: extraLabel,
                      prefixText: '\$ ',
                      hintText: '0',
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),

          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: onCalculate,
              child: Text(calcLabel,
                  style: const TextStyle(
                      fontSize: AppTextSize.bodyLg,
                      fontWeight: FontWeight.w700)),
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

// ─── Step 3: Results ──────────────────────────────────────────────────────────

class _Step3Results extends StatelessWidget {
  final _W4Result? result;
  final String payFrequency;
  final bool es;
  final Future<void> Function(String?)? onSave;
  final VoidCallback onRestart;

  const _Step3Results({
    required this.result,
    required this.payFrequency,
    required this.es,
    this.onSave,
    required this.onRestart,
  });

  String _fmt(double v) =>
      NumberFormat.currency(symbol: '\$', decimalDigits: 2).format(v);

  String _fmt0(double v) =>
      NumberFormat.currency(symbol: '\$', decimalDigits: 0).format(v);

  @override
  Widget build(BuildContext context) {
    if (result == null) {
      return Center(
          child: Text(es ? 'Error de cálculo.' : 'Calculation error.'));
    }
    final r = result!;
    final isRefund = r.refundOrOwed >= 0;

    final title = es ? 'Recomendaciones W-4 2025' : 'W-4 Recommendations 2025';
    final step3Label = es
        ? 'Paso 3 — Créditos por dependientes'
        : 'Step 3 — Dependent Credits';
    final step4bLabel = es
        ? 'Paso 4(b) — Deducciones adicionales'
        : 'Step 4(b) — Other Deductions';
    final step4cLabel = es
        ? 'Paso 4(c) — Retención adicional por cheque'
        : 'Step 4(c) — Extra Withholding per Paycheck';
    final taxLabel =
        es ? 'Impuesto federal anual estimado' : 'Estimated Annual Tax';
    final withholdingLabel = es
        ? 'Retención estimada con estos ajustes'
        : 'Estimated Withholding with These Settings';
    final refundLabel = r.refundOrOwed == 0
        ? (es
            ? 'Resultado equilibrado (sin reembolso ni adeudo)'
            : 'Break-even — No Refund, No Tax Owed')
        : (isRefund
            ? (es
                ? 'Reembolso por retención extra'
                : 'Refund from Extra Withholding')
            : (es ? 'Monto a pagar estimado' : 'Estimated Amount Owed'));
    final restartLabel = es ? 'Reiniciar' : 'Start Over';
    final shareLabel = es ? 'Compartir / Guardar' : 'Share / Save';
    final irsNote = es
        ? '* Basado en el formulario W-4 del IRS 2025. Actualice su W-4 con su empleador con estos valores.'
        : '* Based on IRS 2025 W-4 worksheet. Submit an updated W-4 to your employer with these values.';

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: TextStyle(
                  fontSize: AppTextSize.bodyXl,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.primary)),
          const SizedBox(height: 16),

          // W-4 Summary Card (shareable)
          Card(
            elevation: 0,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadius.xl)),
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.xl),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.assignment_rounded,
                          color: AppTheme.primary, size: 20),
                      const SizedBox(width: 8),
                      Text(
                        es ? 'Resumen W-4 2025' : 'W-4 2025 Summary',
                        style: TextStyle(
                            fontSize: AppTextSize.bodyMd,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.primary),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _W4Row(
                    label: step3Label,
                    value: _fmt0(r.step3DependentCredit),
                    highlight: r.step3DependentCredit > 0,
                  ),
                  _W4Row(
                    label: step4bLabel,
                    value: _fmt0(r.step4bDeductions),
                    highlight: r.step4bDeductions > 0,
                  ),
                  _W4Row(
                    label: step4cLabel,
                    value: _fmt(r.step4cExtra),
                    highlight: r.step4cExtra > 0,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),

          // Refund / owed highlight
          Container(
            padding: const EdgeInsets.all(AppSpacing.xl),
            decoration: BoxDecoration(
              gradient: isRefund
                  ? LinearGradient(
                      colors: [
                        AppTheme.success,
                        CalcwiseSemanticColors.successDeep
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    )
                  : LinearGradient(
                      colors: [
                        AppTheme.error,
                        CalcwiseSemanticColors.errorDark
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
              borderRadius: BorderRadius.circular(AppRadius.xl),
              boxShadow: [
                BoxShadow(
                    color: (isRefund ? AppTheme.success : AppTheme.error)
                        .withValues(alpha: 0.25),
                    blurRadius: 10,
                    offset: const Offset(0, 4)),
              ],
            ),
            child: Row(
              children: [
                Icon(
                  isRefund
                      ? Icons.savings_rounded
                      : Icons.warning_amber_rounded,
                  color: Colors.white,
                  size: 28,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(refundLabel,
                          style: const TextStyle(
                              color: Colors.white70, fontSize: AppTextSize.md)),
                      Text(
                        _fmt(r.refundOrOwed.abs()),
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 26,
                            fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // Tax estimates card
          Card(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Column(
                children: [
                  MetricRow(
                      label: taxLabel,
                      value: _fmt(r.estimatedAnnualTax),
                      valueColor: Colors.redAccent),
                  MetricRow(
                      label: withholdingLabel,
                      value: _fmt(r.estimatedWithholding),
                      valueColor: AppTheme.primary),
                  MetricRow(
                      label: refundLabel,
                      value:
                          '${isRefund ? '+' : '-'}${_fmt(r.refundOrOwed.abs())}',
                      valueColor: isRefund ? AppTheme.success : AppTheme.error),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text(
              irsNote,
              style: TextStyle(
                  fontSize: AppTextSize.xs,
                  color: AppTheme.labelGray,
                  fontStyle: FontStyle.italic),
            ),
          ),
          const SizedBox(height: 20),

          // Share / Print button
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              icon: const Icon(Icons.share_rounded),
              label: Text(shareLabel),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppTheme.primary,
                side: BorderSide(color: AppTheme.primary),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppRadius.xl)),
              ),
              onPressed: () => _sharePdf(context, r),
            ),
          ),
          const SizedBox(height: 12),

          // Save Scenario button (premium/rewarded only, step 3)
          if (onSave != null) ...[
            const SizedBox(height: 12),
            SaveScenarioButton(onSave: onSave!),
          ],

          // Start over
          SizedBox(
            width: double.infinity,
            child: TextButton(
              onPressed: onRestart,
              child:
                  Text(restartLabel, style: TextStyle(color: AppTheme.primary)),
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Future<void> _sharePdf(BuildContext context, _W4Result r) async {
    final doc = pw.Document();
    doc.addPage(pw.Page(
      build: (ctx) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
              es
                  ? 'Asistente W-4 2025'
                  : 'W-4 Withholding Wizard — 2025',
              style: pw.TextStyle(
                  fontSize: AppTextSize.title, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 4),
          pw.Text(DateFormat('MMMM d, yyyy').format(DateTime.now()),
              style: const pw.TextStyle(fontSize: AppTextSize.xs)),
          pw.Divider(height: 24),
          pw.Text(
              es ? 'Valores recomendados W-4' : 'W-4 Recommended Values',
              style: pw.TextStyle(
                  fontSize: AppTextSize.body, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 8),
          _pdfRow(
              es
                  ? 'Paso 3 — Créditos por dependientes'
                  : 'Step 3 — Dependent Credits',
              '\$${r.step3DependentCredit.toStringAsFixed(0)}'),
          _pdfRow(
              es
                  ? 'Paso 4(b) — Deducciones adicionales'
                  : 'Step 4(b) — Other Deductions',
              '\$${r.step4bDeductions.toStringAsFixed(0)}'),
          _pdfRow(
              es
                  ? 'Paso 4(c) — Retención adicional por cheque'
                  : 'Step 4(c) — Extra per Paycheck',
              '\$${r.step4cExtra.toStringAsFixed(2)}'),
          pw.Divider(height: 24),
          pw.Text(
              es ? 'Estimaciones' : 'Estimates',
              style: pw.TextStyle(
                  fontSize: AppTextSize.body, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 8),
          _pdfRow(
              es
                  ? 'Impuesto federal anual estimado'
                  : 'Estimated Annual Tax',
              '\$${r.estimatedAnnualTax.toStringAsFixed(2)}'),
          _pdfRow(
              es
                  ? 'Retención estimada con estos ajustes'
                  : 'Estimated Annual Withholding',
              '\$${r.estimatedWithholding.toStringAsFixed(2)}'),
          _pdfRow(
              r.refundOrOwed >= 0
                  ? (es ? 'Reembolso esperado' : 'Expected Refund')
                  : (es ? 'Monto a pagar estimado' : 'Amount Owed'),
              '\$${r.refundOrOwed.abs().toStringAsFixed(2)}'),
          pw.SizedBox(height: 20),
          pw.Text(
              es
                  ? '* Basado en el formulario W-4 del IRS 2025. Actualice su W-4 con su empleador.'
                  : '* Estimates based on IRS 2025 W-4 worksheet. '
                      'Submit updated W-4 to your employer.',
              style: const pw.TextStyle(fontSize: 9)),
        ],
      ),
    ));
    await Printing.sharePdf(
        bytes: await doc.save(),
        filename: 'w4_wizard_${DateTime.now().millisecondsSinceEpoch}.pdf');
  }

  pw.Widget _pdfRow(String label, String value) => pw.Padding(
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
}

// ─── Small helpers ────────────────────────────────────────────────────────────

class _W4Row extends StatelessWidget {
  final String label;
  final String value;
  final bool highlight;

  const _W4Row(
      {required this.label, required this.value, this.highlight = false});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(
            child:
                Text(label, style: const TextStyle(fontSize: AppTextSize.md)),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: AppTextSize.body,
              fontWeight: FontWeight.bold,
              color: highlight ? AppTheme.primary : null,
            ),
          ),
        ],
      ),
    );
  }
}

class _CounterButtons extends StatelessWidget {
  final int value;
  final VoidCallback onDecrement;
  final VoidCallback onIncrement;

  const _CounterButtons({
    required this.value,
    required this.onDecrement,
    required this.onIncrement,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        IconButton(
          icon: Icon(Icons.remove_circle_outline,
              color: value > 0 ? AppTheme.primary : AppTheme.divider),
          onPressed: value > 0 ? onDecrement : null,
          splashRadius: 20,
        ),
        SizedBox(
          width: 28,
          child: Text(
            '$value',
            textAlign: TextAlign.center,
            style: const TextStyle(
                fontSize: AppTextSize.bodyLg, fontWeight: FontWeight.bold),
          ),
        ),
        IconButton(
          icon: Icon(Icons.add_circle_outline, color: AppTheme.primary),
          onPressed: onIncrement,
          splashRadius: 20,
        ),
      ],
    );
  }
}
