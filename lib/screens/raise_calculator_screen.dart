import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'history_screen.dart' show HistoryScreen;
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import 'package:calcwise_core/calcwise_core.dart';

import '../core/flavor_config.dart';
import '../core/analytics/analytics_service.dart';
import '../core/theme/app_theme.dart';
import '../core/freemium/freemium_service.dart';
import '../core/freemium/iap_service.dart';
import '../core/services/pdf_export_service.dart';
import '../main.dart' show isSpanishNotifier, salaryNotifier, historyService, paywallSession, adService;
import '../widgets/result_card.dart';
import '../widgets/save_scenario_button.dart';

// ─── Raise Calculator Screen ──────────────────────────────────────────────────
//
// Key insight: "A 10% raise doesn't mean 10% more take-home" (taxes eat part
// of it). This "aha moment" makes the screen highly shareable.
//
// Progressive tax buckets (US federal approximation):
//   0 –  11,925  →  10%
//  11,925 –  48,475  →  12%
//  48,475 – 103,350  →  22%
// 103,350 – 197,300  →  24%
// 197,300 – 250,525  →  32%
// 250,525 – 626,350  →  35%
//        > 626,350  →  37%

class RaiseCalculatorScreen extends StatefulWidget {
  /// Optional pre-fill from the main calculator.
  final double? initialSalary;

  const RaiseCalculatorScreen({super.key, this.initialSalary});

  @override
  State<RaiseCalculatorScreen> createState() => _RaiseCalculatorScreenState();
}

class _RaiseCalculatorScreenState extends State<RaiseCalculatorScreen> {
  final _formKey = GlobalKey<FormState>();
  final _salaryCtrl = TextEditingController();

  bool _isPercent = true;
  double _raisePct = 10.0; // slider value when isPercent
  final _flatCtrl = TextEditingController();

  _RaiseCalcResult? _result;

  @override
  void initState() {
    super.initState();
    // Pre-fill from explicit param or last-used salary from main calc
    final _fmt = NumberFormat('#,###');
    if (widget.initialSalary != null && widget.initialSalary! > 0) {
      _salaryCtrl.text = _fmt.format(widget.initialSalary!.round());
    } else if (salaryNotifier.value > 0) {
      _salaryCtrl.text = _fmt.format(salaryNotifier.value.round());
    } else {
      _salaryCtrl.text = '75,000';
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      AnalyticsService.instance.logScreenView('raise_calculator');
      _calculate();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkPaywall());
    _salaryCtrl.addListener(() { if (mounted) _calculate(); });
    _flatCtrl.addListener(() { if (mounted) _calculate(); });
  }

  @override
  void dispose() {
    historyService.cancelPendingSave('salaryapp', 'raise');
    _salaryCtrl.dispose();
    _flatCtrl.dispose();
    super.dispose();
  }

  // ── SmartHistory helpers ──────────────────────────────────────────────────

  double _roundTo(double v, double step) => (v / step).round() * step;

  String _buildHash() {
    final current = _parse(_salaryCtrl.text);
    return ResultHasher.hashMixed({
      'flavor': FlavorConfig.flavor,
      'salary': _roundTo(current, 1000),
      'raise_pct': _isPercent ? _roundTo(_raisePct, 0.25) : null,
      'flat': !_isPercent ? _roundTo(_parse(_flatCtrl.text), 500) : null,
    });
  }

  Map<String, dynamic> _buildL1() {
    final r = _result;
    if (r == null) return {};
    return {
      'current_salary': r.currentSalary,
      'new_salary': r.newAnnual,
      'raise_pct': r.raisePct,
      'new_monthly_net': r.newMonthlyNet,
    };
  }

  Map<String, dynamic> _buildL2() {
    final r = _result;
    if (r == null) return {};
    return {
      'inputs': {
        'current_salary': r.currentSalary,
        'raise_pct': r.raisePct,
        'is_percent': _isPercent,
        'flavor': FlavorConfig.flavor,
      },
      'results': {
        'new_annual': r.newAnnual,
        'raise_gross': r.raiseGross,
        'raise_net': r.raiseNet,
        'tax_increase': r.taxIncrease,
        'old_monthly_net': r.oldMonthlyNet,
        'new_monthly_net': r.newMonthlyNet,
        'effective_pct': r.effectivePct,
        'marginal_rate': r.marginalRate,
      },
    };
  }

  Future<void> _scheduleAutoSave() async {
    if (_result == null) return;
    historyService.scheduleAutoSave(
      appKey: 'salaryapp',
      screenId: 'raise',
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
      screenId: 'raise',
      inputHash: _buildHash(),
      l1: _buildL1(),
      l2: _buildL2(),
      label: label,
    );
    HistoryScreen.refreshNotifier.value++;
    adService.onSave();
  }

  // ── Tax engine ──────────────────────────────────────────────────────────────

  /// Returns estimated annual federal tax using progressive US brackets.
  /// CA/UK flavors use a simplified flat-ish approach since brackets differ.
  double _calcTax(double annual) {
    if (FlavorConfig.isUS) {
      // 2025 single filer brackets (approximate)
      const brackets = [
        (11925.0, 0.10),
        (48475.0, 0.12),
        (103350.0, 0.22),
        (197300.0, 0.24),
        (250525.0, 0.32),
        (626350.0, 0.35),
        (double.infinity, 0.37),
      ];
      double tax = 0;
      double prev = 0;
      for (final (limit, rate) in brackets) {
        if (annual <= prev) break;
        final taxable = (annual < limit ? annual : limit) - prev;
        tax += taxable * rate;
        prev = limit;
        if (annual <= limit) break;
      }
      return tax;
    }
    if (FlavorConfig.isCA) {
      // Simplified Canadian federal + provincial est. (~25–33%)
      // Apply Basic Personal Amount (BPA = $15,705 for 2025) as a non-refundable
      // federal tax credit at the lowest federal bracket rate (15%).
      const double bpa = 15705.0;
      const double bpaCredit = bpa * 0.15; // = $2,355.75
      double grossTax;
      if (annual < 57375) {
        grossTax = annual * 0.205;
      } else if (annual < 114750) {
        grossTax = annual * 0.260;
      } else if (annual < 177882) {
        grossTax = annual * 0.290;
      } else if (annual < 253414) {
        grossTax = annual * 0.330;
      } else {
        grossTax = annual * 0.353;
      }
      return (grossTax - bpaCredit).clamp(0.0, double.infinity);
    }
    // UK — simplified basic/higher rate
    final personalAllowance = 12570.0;
    final basicThreshold = 50270.0;
    if (annual <= personalAllowance) return 0;
    if (annual <= basicThreshold) return (annual - personalAllowance) * 0.20;
    return (basicThreshold - personalAllowance) * 0.20 +
        (annual - basicThreshold) * 0.40;
  }

  /// Marginal rate at the top bracket reached.
  double _marginalRate(double annual) {
    if (FlavorConfig.isUS) {
      if (annual <= 11925) return 0.10;
      if (annual <= 48475) return 0.12;
      if (annual <= 103350) return 0.22;
      if (annual <= 197300) return 0.24;
      if (annual <= 250525) return 0.32;
      if (annual <= 626350) return 0.35;
      return 0.37;
    }
    if (FlavorConfig.isCA) {
      if (annual < 57375) return 0.205;
      if (annual < 114750) return 0.260;
      if (annual < 177882) return 0.290;
      if (annual < 253414) return 0.330;
      return 0.353;
    }
    // UK
    if (annual <= 12570) return 0.0;
    if (annual <= 50270) return 0.20;
    return 0.40;
  }

  // ── Marginal table data ──────────────────────────────────────────────────────

  List<_MarginalRow> _buildMarginalRows(_RaiseCalcResult r) {
    const steps = [1000.0, 5000.0, 10000.0, 15000.0, 20000.0];
    final baseTax = _calcTax(r.newAnnual);
    final baseNet = r.newAnnual - baseTax;
    return steps.map((step) {
      final gross = r.newAnnual + step;
      final net = gross - _calcTax(gross);
      final gain = net - baseNet;
      final keepPct = step > 0 ? (gain / step * 100).clamp(0.0, 100.0) : 0.0;
      return _MarginalRow(step: step, gain: gain, keepPct: keepPct);
    }).toList();
  }

  // ── Calculation ─────────────────────────────────────────────────────────────

  void _calculate() {
    if (!_formKey.currentState!.validate()) return;
    HapticFeedback.mediumImpact();
    FocusScope.of(context).unfocus();

    final current = _parse(_salaryCtrl.text);
    if (current <= 0) return;

    AnalyticsService.instance.maybeLogFirstCalculate();

    final double raisePct;
    final double newAnnual;
    if (_isPercent) {
      raisePct = _raisePct;
      newAnnual = current * (1 + raisePct / 100);
    } else {
      final flat = _parse(_flatCtrl.text);
      if (flat <= 0) return;
      raisePct = flat / current * 100;
      newAnnual = current + flat;
    }

    final oldTax = _calcTax(current);
    final newTax = _calcTax(newAnnual);
    final taxIncrease = newTax - oldTax;
    final raiseGross = newAnnual - current;
    final raiseNet = raiseGross - taxIncrease;
    final oldTakeHome = current - oldTax;
    final newTakeHome = newAnnual - newTax;
    final effectivePct = oldTakeHome > 0 ? raiseNet / oldTakeHome * 100 : 0.0;
    final marginalRate = _marginalRate(newAnnual);

    setState(() {
      _result = _RaiseCalcResult(
        currentSalary: current,
        newAnnual: newAnnual,
        raisePct: raisePct,
        raiseGross: raiseGross,
        raiseNet: raiseNet,
        oldTax: oldTax,
        newTax: newTax,
        taxIncrease: taxIncrease,
        oldMonthlyNet: oldTakeHome / 12,
        newMonthlyNet: newTakeHome / 12,
        effectivePct: effectivePct,
        marginalRate: marginalRate,
      );
    });
    adService.onAction();
    _scheduleAutoSave();

    AnalyticsService.instance.logCalculation(
      grossSalary: newAnnual,
      netSalary: newTakeHome,
      frequency: 'annual',
    );
  }

  Future<void> _checkPaywall() async {
    final trigger = await paywallSession.recordAction();
    if (!mounted) return;
    if (trigger == PaywallTrigger.soft) PaywallSoft.show(context);
    if (trigger == PaywallTrigger.hard) PaywallHard.show(context);
  }

  double _parse(String text) {
    if (text.isEmpty) return 0;
    // Strip all thousand-separator variants (comma, non-breaking space, narrow NBSP)
    return double.tryParse(
            text.replaceAll(RegExp('[,   ]'), '').replaceAll(RegExp(r'[^\d.]'), '')) ??
        0;
  }

  // ── PDF export ───────────────────────────────────────────────────────────────

  Future<void> _exportPdf(bool es, bool fr) async {
    final r = _result;
    if (r == null) return;
    await PdfExportService.exportRaise(
      context: context,
      currentSalary: r.currentSalary,
      newAnnual: r.newAnnual,
      raisePct: r.raisePct,
      raiseGross: r.raiseGross,
      raiseNet: r.raiseNet,
      taxIncrease: r.taxIncrease,
      oldMonthlyNet: r.oldMonthlyNet,
      newMonthlyNet: r.newMonthlyNet,
      effectivePct: r.effectivePct,
      marginalRate: r.marginalRate,
      fr: fr,
      es: es,
    );
    analyticsService.logPdfExported();
  }

  // ── Share ────────────────────────────────────────────────────────────────────

  void _share(_RaiseCalcResult r, bool es) {
    final sym = FlavorConfig.currencySymbol;
    final text = es
        ? 'Mi aumento de ${r.raisePct.toStringAsFixed(1)}% (${sym}${r.raiseGross.toStringAsFixed(0)})\n'
            'Solo recibo +${sym}${(r.raiseNet / 12).toStringAsFixed(0)}/mes después de impuestos.\n'
            'Tasa marginal: ${(r.marginalRate * 100).toStringAsFixed(0)}%\n'
            'Calculado con Salary Calculator'
        : '${r.raisePct.toStringAsFixed(1)}% raise = +${sym}${r.raiseGross.toStringAsFixed(0)}/yr gross\n'
            'But taxes take ${sym}${r.taxIncrease.toStringAsFixed(0)} — so my real take-home gain is '
            '+${sym}${(r.raiseNet / 12).toStringAsFixed(0)}/mo (${r.effectivePct.toStringAsFixed(1)}% effective).\n'
            'Marginal rate: ${(r.marginalRate * 100).toStringAsFixed(0)}%\n'
            'Calculated with Salary Calculator';
    try {
      Share.share(text);
    } catch (_) {}
  }

  // ── Build ────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: isSpanishNotifier,
      builder: (context, useAlt, _) {
        final es = FlavorConfig.isUS && useAlt;
        final fr = FlavorConfig.isCA && useAlt;

        final titleText = fr
            ? 'Impact de votre augmentation'
            : (es ? 'Impacto de tu aumento' : 'Raise Impact Calculator');

        return Scaffold(
          appBar: AppBar(title: Text(titleText)),
          body: CalcwisePageEntrance(
              child: Column(children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _InputSection(
                        salaryCtrl: _salaryCtrl,
                        flatCtrl: _flatCtrl,
                        isPercent: _isPercent,
                        raisePct: _raisePct,
                        es: es,
                        fr: fr,
                        onTypeToggle: (v) { setState(() => _isPercent = v); _calculate(); },
                        onSliderChanged: (v) { setState(() => _raisePct = v); _calculate(); },
                      ),
                      const SizedBox(height: AppSpacing.xl),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: _calculate,
                          child: Text(
                            fr ? 'Calculer' : (es ? 'Calcular' : 'Calculate'),
                            style: const TextStyle(
                                fontSize: AppTextSize.bodyLg,
                                fontWeight: FontWeight.w700),
                          ),
                        ),
                      ),
                      if (_result != null) ...[
                        const SizedBox(height: AppSpacing.xxlPlus),
                        CalcwiseStaggerItem(
                          index: 0,
                          child: _ResultsSection(
                            result: _result!,
                            es: es,
                            fr: fr,
                            onShare: () => _share(_result!, es),
                          ),
                        ),
                        const SizedBox(height: AppSpacing.lg),
                        CalcwiseStaggerItem(
                          index: 1,
                          child: _MarginalTakeHomeCard(
                            rows: _buildMarginalRows(_result!),
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
                                    : Icons.lock_outline_rounded,
                                    size: 18),
                                label: Text(pdfLabel),
                                onPressed: () async {
                                  HapticFeedback.mediumImpact();
                                  if (!isPremium) {
                                    await PdfExportService.showUnlockOrPay(
                                        context, () => _exportPdf(es, fr));
                                  } else {
                                    await _exportPdf(es, fr);
                                  }
                                },
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: AppTheme.primary,
                                  minimumSize:
                                      const Size(double.infinity, 48),
                                  side: BorderSide(
                                      color: AppTheme.primary
                                          .withValues(alpha: 0.4)),
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(
                                          AppRadius.lg)),
                                  padding: const EdgeInsets.symmetric(
                                      vertical: AppSpacing.md),
                                ),
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
          ])),
        );
      },
    );
  }
}

// ─── Data model ───────────────────────────────────────────────────────────────

class _RaiseCalcResult {
  final double currentSalary;
  final double newAnnual;
  final double raisePct;
  final double raiseGross;
  final double raiseNet;
  final double oldTax;
  final double newTax;
  final double taxIncrease;
  final double oldMonthlyNet;
  final double newMonthlyNet;
  final double effectivePct;
  final double marginalRate;

  const _RaiseCalcResult({
    required this.currentSalary,
    required this.newAnnual,
    required this.raisePct,
    required this.raiseGross,
    required this.raiseNet,
    required this.oldTax,
    required this.newTax,
    required this.taxIncrease,
    required this.oldMonthlyNet,
    required this.newMonthlyNet,
    required this.effectivePct,
    required this.marginalRate,
  });
}

// ─── Input section ────────────────────────────────────────────────────────────

class _InputSection extends StatelessWidget {
  final TextEditingController salaryCtrl;
  final TextEditingController flatCtrl;
  final bool isPercent;
  final double raisePct;
  final bool es, fr;
  final ValueChanged<bool> onTypeToggle;
  final ValueChanged<double> onSliderChanged;

  const _InputSection({
    required this.salaryCtrl,
    required this.flatCtrl,
    required this.isPercent,
    required this.raisePct,
    required this.es,
    required this.fr,
    required this.onTypeToggle,
    required this.onSliderChanged,
  });

  @override
  Widget build(BuildContext context) {
    final sym = FlavorConfig.currencySymbol;
    final salaryLabel = fr
        ? 'Salaire actuel (annuel)'
        : (es ? 'Salario actual (anual)' : 'Current Annual Salary');
    final raiseTypeLabel =
        fr ? 'Type d\'augmentation' : (es ? 'Tipo de aumento' : 'Raise Type');
    final pctLabel =
        fr ? '% Pourcentage' : (es ? '% Porcentaje' : '% Percentage');
    final flatLabel = fr
        ? '$sym Montant fixe'
        : (es ? '$sym Monto fijo' : '$sym Flat amount');
    final flatHint = fr ? 'ex. 5000' : (es ? 'ej. 5000' : 'e.g. 5000');
    final flatField = fr
        ? 'Montant de l\'augmentation'
        : (es ? 'Valor del aumento' : 'Raise amount');
    final req = fr ? 'Requis' : (es ? 'Requerido' : 'Required');
    final invalid = fr ? 'Montant invalide' : (es ? 'Inválido' : 'Invalid');

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // Current salary
          TextFormField(
            controller: salaryCtrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              CurrencyInputFormatter(
                  locale: FlavorConfig.isCA
                      ? 'en_CA'
                      : (FlavorConfig.isUK ? 'en_GB' : 'en_US')),
            ],
            decoration: InputDecoration(
              prefixText: '$sym ',
              labelText: salaryLabel,
              hintText: '60,000',
            ),
            style: const TextStyle(
                fontSize: AppTextSize.bodyLg, fontWeight: FontWeight.w600),
            validator: (v) {
              if (v == null || v.trim().isEmpty) return req;
              final val = double.tryParse(
                  v.replaceAll(',', '').replaceAll(RegExp(r'[^\d.]'), ''));
              if (val == null || val <= 0) return invalid;
              return null;
            },
          ),
          const SizedBox(height: AppSpacing.xl),

          // Raise type toggle
          Text(raiseTypeLabel,
              style: TextStyle(
                  fontSize: AppTextSize.md,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.labelGray)),
          const SizedBox(height: AppSpacing.sm),
          Semantics(
            label: fr
                ? 'Type d\'augmentation'
                : (es ? 'Tipo de aumento' : 'Raise type'),
            container: true,
            child: Row(children: [
              Expanded(
                child: Semantics(
                  inMutuallyExclusiveGroup: true,
                  selected: isPercent,
                  child: ChoiceChip(
                    label: Text(pctLabel),
                    selected: isPercent,
                    selectedColor: AppTheme.primary,
                    labelStyle: TextStyle(
                      color: isPercent ? Colors.white : AppTheme.labelGray,
                      fontWeight:
                          isPercent ? FontWeight.w600 : FontWeight.normal,
                    ),
                    onSelected: (_) => onTypeToggle(true),
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Semantics(
                  inMutuallyExclusiveGroup: true,
                  selected: !isPercent,
                  child: ChoiceChip(
                    label: Text(flatLabel),
                    selected: !isPercent,
                    selectedColor: AppTheme.primary,
                    labelStyle: TextStyle(
                      color: !isPercent ? Colors.white : AppTheme.labelGray,
                      fontWeight:
                          !isPercent ? FontWeight.w600 : FontWeight.normal,
                    ),
                    onSelected: (_) => onTypeToggle(false),
                  ),
                ),
              ),
            ]),
          ),
          const SizedBox(height: AppSpacing.lg),

          // Raise value input
          if (isPercent) ...[
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Text(
                fr ? 'Augmentation' : (es ? 'Aumento' : 'Raise'),
                style: const TextStyle(
                    fontSize: AppTextSize.md, fontWeight: FontWeight.w600),
              ),
              Text(
                '${raisePct.toStringAsFixed(0)}%',
                style: TextStyle(
                    fontSize: AppTextSize.title,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.primary),
              ),
            ]),
            Semantics(
              slider: true,
              label: fr
                  ? 'Pourcentage d\'augmentation, 1 à 50 pourcent'
                  : (es
                      ? 'Porcentaje de aumento, 1 a 50 porciento'
                      : 'Raise percentage slider, 1 to 50 percent'),
              value: '${raisePct.toStringAsFixed(0)}%',
              child: Slider(
                value: raisePct,
                min: 1,
                max: 50,
                divisions: 49,
                activeColor: AppTheme.primary,
                label: '${raisePct.toStringAsFixed(0)}%',
                onChanged: onSliderChanged,
              ),
            ),
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Text('1%',
                  style: TextStyle(
                      fontSize: AppTextSize.xs, color: AppTheme.labelGray)),
              Text('50%',
                  style: TextStyle(
                      fontSize: AppTextSize.xs, color: AppTheme.labelGray)),
            ]),
          ] else ...[
            TextFormField(
              controller: flatCtrl,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                CurrencyInputFormatter(
                    locale: FlavorConfig.isCA
                        ? 'en_CA'
                        : (FlavorConfig.isUK ? 'en_GB' : 'en_US')),
              ],
              decoration: InputDecoration(
                prefixText: '$sym ',
                labelText: flatField,
                hintText: 'e.g. 5,000',
              ),
              style: const TextStyle(
                  fontSize: AppTextSize.bodyLg, fontWeight: FontWeight.w600),
              validator: (v) {
                if (!isPercent) {
                  if (v == null || v.trim().isEmpty) return req;
                  final val = double.tryParse(
                      v.replaceAll(',', '').replaceAll(RegExp(r'[^\d.]'), ''));
                  if (val == null || val <= 0) return invalid;
                }
                return null;
              },
            ),
          ],
        ]),
      ),
    );
  }
}

// ─── Results section ──────────────────────────────────────────────────────────

class _ResultsSection extends StatelessWidget {
  final _RaiseCalcResult result;
  final bool es, fr;
  final VoidCallback onShare;

  const _ResultsSection({
    required this.result,
    required this.es,
    required this.fr,
    required this.onShare,
  });

  String _fmt(double v) =>
      AmountFormatter.ui(v.round().toDouble(), FlavorConfig.currencyCode);

  String _fmt2(double v) =>
      AmountFormatter.ui(v, FlavorConfig.currencyCode);

  @override
  Widget build(BuildContext context) {
    final r = result;

    // Labels
    final newSalaryLabel = fr
        ? 'Nouveau salaire annuel'
        : (es ? 'Nuevo salario anual' : 'New Annual Salary');
    final oldNetLabel = fr
        ? 'Revenu mensuel net actuel'
        : (es ? 'Neto mensual actual' : 'Current Monthly Net');
    final newNetLabel = fr
        ? 'Revenu mensuel net après augmentation'
        : (es ? 'Nuevo neto mensual' : 'New Monthly Net');
    final taxHitLabel = fr
        ? 'Impôts supplémentaires'
        : (es ? 'Impuestos adicionales/año' : 'Extra Tax / Year');
    final realRaiseLabel = fr
        ? 'Vrai gain net annuel'
        : (es ? 'Ganancia neta real/año' : 'Real Net Gain / Year');
    final effectivePctLabel = fr
        ? 'Hausse effective du revenu net'
        : (es ? 'Aumento efectivo del neto' : 'Effective Take-Home Raise');
    final margLabel = fr
        ? 'Taux marginal sur le surplus'
        : (es
            ? 'Tasa marginal sobre el aumento'
            : 'Marginal Rate on New Income');
    final shareLabel = fr ? 'Partager' : (es ? 'Compartir' : 'Share');
    final taxNote = fr
        ? '* Estimation fiscale simplifiée — à titre indicatif uniquement.'
        : (es
            ? '* Estimación fiscal simplificada — solo orientativa.'
            : '* Simplified tax estimate — for illustration only.');

    // "Aha" motivating message
    final String ahaMsg;
    if (fr) {
      ahaMsg = 'Une augmentation de ${r.raisePct.toStringAsFixed(1)}% '
          '(${_fmt(r.raiseGross)}) rapporte seulement ${_fmt(r.raiseNet)} '
          'net après impôts (${(r.marginalRate * 100).toStringAsFixed(0)}% marginal). '
          'Maximisez vos cotisations REER pour récupérer une partie de cet impôt.';
    } else if (es) {
      ahaMsg = 'Tu aumento de ${r.raisePct.toStringAsFixed(1)}% '
          '(${_fmt(r.raiseGross)}) solo equivale a ${_fmt(r.raiseNet)} neto '
          'después de impuestos (${(r.marginalRate * 100).toStringAsFixed(0)}% marginal). '
          '¡Maximiza tu 401(k) para recuperar parte de ese impuesto!';
    } else if (FlavorConfig.isUK) {
      ahaMsg =
          'Your ${r.raisePct.toStringAsFixed(1)}% raise (${_fmt(r.raiseGross)}) '
          'nets you only ${_fmt(r.raiseNet)} after taxes '
          '(${(r.marginalRate * 100).toStringAsFixed(0)}% marginal rate). '
          'Salary sacrifice into your pension to claw back some of that tax.';
    } else {
      ahaMsg =
          'Your ${r.raisePct.toStringAsFixed(1)}% raise (${_fmt(r.raiseGross)}) '
          'nets you only ${_fmt(r.raiseNet)} after taxes '
          '(${(r.marginalRate * 100).toStringAsFixed(0)}% marginal rate). '
          'Max your 401(k)/RRSP to claw back some of that tax.';
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      // Hero card — new salary
      ResultCard(
        label: newSalaryLabel,
        value: _fmt(r.newAnnual),
        icon: Icons.trending_up_rounded,
        highlight: true,
      ),
      const SizedBox(height: AppSpacing.md),

      // Monthly before/after
      Row(children: [
        Expanded(
          child: ResultCard(label: oldNetLabel, value: _fmt2(r.oldMonthlyNet)),
        ),
        const SizedBox(width: AppSpacing.smPlus),
        Expanded(
          child: ResultCard(label: newNetLabel, value: _fmt2(r.newMonthlyNet)),
        ),
      ]),
      const SizedBox(height: AppSpacing.md),

      // Tax breakdown card
      Card(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(children: [
            Row(children: [
              Icon(Icons.account_balance_rounded,
                  size: 18, color: AppTheme.primary),
              const SizedBox(width: AppSpacing.sm),
              Text(
                fr
                    ? 'Détail fiscal'
                    : (es ? 'Detalle fiscal' : 'Tax Breakdown'),
                style: const TextStyle(
                    fontSize: AppTextSize.bodyMd, fontWeight: FontWeight.w600),
              ),
            ]),
            const SizedBox(height: AppSpacing.mdPlus),
            MetricRow(
                label: taxHitLabel,
                value: _fmt(r.taxIncrease),
                valueColor: AppTheme.error),
            MetricRow(
                label: realRaiseLabel,
                value: '+${_fmt(r.raiseNet)}',
                valueColor: AppTheme.success),
            MetricRow(
                label: effectivePctLabel,
                value: '+${r.effectivePct.toStringAsFixed(1)}%',
                valueColor: AppTheme.success),
            MetricRow(
                label: margLabel,
                value: '${(r.marginalRate * 100).toStringAsFixed(0)}%',
                valueColor: AppTheme.warning),
          ]),
        ),
      ),
      const SizedBox(height: AppSpacing.md),

      // Aha-moment motivating message
      Container(
        padding: const EdgeInsets.all(AppSpacing.mdPlus),
        decoration: BoxDecoration(
          color: AppTheme.primary.withValues(alpha: 0.06),
          border: Border.all(color: AppTheme.primary.withValues(alpha: 0.2)),
          borderRadius: BorderRadius.circular(AppRadius.lg),
        ),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(Icons.lightbulb_outline, color: AppTheme.primary, size: 18),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(ahaMsg,
                style: TextStyle(
                    fontSize: AppTextSize.sm,
                    color: AppTheme.primary,
                    height: 1.5)),
          ),
        ]),
      ),
      const SizedBox(height: 6),
      Text(taxNote,
          style: TextStyle(
              fontSize: AppTextSize.xs,
              color: AppTheme.labelGray,
              fontStyle: FontStyle.italic)),
      const SizedBox(height: AppSpacing.lg),

      // Share button
      OutlinedButton.icon(
        onPressed: onShare,
        icon: const Icon(Icons.share_rounded, size: 18),
        label: Text(shareLabel),
        style: OutlinedButton.styleFrom(
          foregroundColor: AppTheme.primary,
          minimumSize: const Size(double.infinity, 48),
          side: BorderSide(color: AppTheme.primary.withValues(alpha: 0.4)),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadius.lg)),
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
        ),
      ),
    ]);
  }
}

// ─── Marginal take-home data ──────────────────────────────────────────────────

class _MarginalRow {
  final double step;
  final double gain;
  final double keepPct;

  const _MarginalRow({
    required this.step,
    required this.gain,
    required this.keepPct,
  });
}

// ─── Marginal Take-Home Card ──────────────────────────────────────────────────

class _MarginalTakeHomeCard extends StatefulWidget {
  final List<_MarginalRow> rows;
  final bool es, fr;

  const _MarginalTakeHomeCard({
    required this.rows,
    required this.es,
    required this.fr,
  });

  @override
  State<_MarginalTakeHomeCard> createState() => _MarginalTakeHomeCardState();
}

class _MarginalTakeHomeCardState extends State<_MarginalTakeHomeCard> {
  bool _expanded = true;

  String _fmtStep(double step) {
    final sym = FlavorConfig.currencySymbol;
    if (step >= 1000) {
      final k = (step / 1000).toStringAsFixed(0);
      return '+${sym}${k}k';
    }
    return '+$sym${step.toStringAsFixed(0)}';
  }

  String _fmtGain(double gain) =>
      AmountFormatter.ui(gain.round().toDouble(), FlavorConfig.currencyCode);

  Color _barColor(double pct) {
    if (pct >= 65) return AppTheme.success;
    if (pct >= 45) return AppTheme.warning;
    return AppTheme.error;
  }

  @override
  Widget build(BuildContext context) {
    final ct = CalcwiseTheme.of(context);
    final title = widget.fr
        ? 'Que garde-t-on sur le prochain dollar ?'
        : (widget.es
            ? '¿Cuánto se queda del próximo dólar?'
            : 'What does your next dollar earn?');
    final cardTitle = widget.fr
        ? 'Gain net marginal'
        : (widget.es ? 'Ganancia neta marginal' : 'Marginal Take-Home');

    return Card(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        InkWell(
          borderRadius: const BorderRadius.vertical(
              top: Radius.circular(AppRadius.md)),
          onTap: () => setState(() => _expanded = !_expanded),
          child: Padding(
            padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.lg, vertical: AppSpacing.mdPlus),
            child: Row(children: [
              Icon(Icons.trending_up_rounded,
                  size: 18, color: AppTheme.primary),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  cardTitle,
                  style: const TextStyle(
                      fontSize: AppTextSize.bodyMd,
                      fontWeight: FontWeight.w600),
                ),
              ),
              Icon(
                _expanded
                    ? Icons.keyboard_arrow_up_rounded
                    : Icons.keyboard_arrow_down_rounded,
                size: 20,
                color: ct.textSecondary,
              ),
            ]),
          ),
        ),
        if (_expanded) ...[
          Padding(
            padding: const EdgeInsets.only(
                left: AppSpacing.lg,
                right: AppSpacing.lg,
                bottom: AppSpacing.sm),
            child: Text(
              title,
              style: TextStyle(
                  fontSize: AppTextSize.sm, color: ct.textSecondary),
            ),
          ),
          ValueListenableBuilder<bool>(
            valueListenable: freemiumService.hasFullAccessNotifier,
            builder: (context, isPremium, _) {
              const freeRows = 2;
              final rows = widget.rows;
              return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (int i = 0; i < rows.length; i++)
                      _buildRow(rows[i], ct, i < freeRows || isPremium),
                    if (!isPremium)
                      _GateOverlay(
                        es: widget.es,
                        fr: widget.fr,
                        onUnlock: () => PaywallHard.show(context),
                      ),
                    const SizedBox(height: AppSpacing.md),
                  ]);
            },
          ),
        ],
      ]),
    );
  }

  Widget _buildRow(_MarginalRow row, CalcwiseTheme ct, bool visible) {
    final sym = FlavorConfig.currencySymbol;
    final stepLabel = _fmtStep(row.step);
    final keepLabel = visible
        ? 'Keep ${_fmtGain(row.gain)} (${row.keepPct.toStringAsFixed(0)}%)'
        : '██████████ (██%)';
    final barColor = _barColor(row.keepPct);
    final barFraction = (row.keepPct / 100).clamp(0.0, 1.0);

    return Padding(
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg, vertical: AppSpacing.xs),
      child: Row(children: [
        SizedBox(
          width: 52,
          child: Text(stepLabel,
              style: TextStyle(
                  fontSize: AppTextSize.sm,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.primary)),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                visible
                    ? Text(keepLabel,
                        style: TextStyle(
                            fontSize: AppTextSize.sm,
                            color: ct.textPrimary))
                    : Container(
                        height: 13,
                        decoration: BoxDecoration(
                          color: ct.cardBorder,
                          borderRadius:
                              BorderRadius.circular(AppRadius.sm),
                        ),
                      ),
                const SizedBox(height: 4),
                ClipRRect(
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                  child: LinearProgressIndicator(
                    value: visible ? barFraction : 0.0,
                    minHeight: 6,
                    backgroundColor: ct.cardBorder,
                    valueColor:
                        AlwaysStoppedAnimation<Color>(barColor),
                  ),
                ),
              ]),
        ),
        if (visible) ...[
          const SizedBox(width: AppSpacing.sm),
          Text(
            '${row.keepPct.toStringAsFixed(0)}%',
            style: TextStyle(
                fontSize: AppTextSize.sm,
                fontWeight: FontWeight.w600,
                color: barColor),
          ),
        ],
      ]),
    );
  }
}

// ─── Gate overlay for locked rows ────────────────────────────────────────────

class _GateOverlay extends StatelessWidget {
  final bool es, fr;
  final VoidCallback onUnlock;

  const _GateOverlay({
    required this.es,
    required this.fr,
    required this.onUnlock,
  });

  @override
  Widget build(BuildContext context) {
    final label = fr
        ? 'Voir les 3 paliers suivants'
        : (es ? 'Ver los 3 niveles restantes' : 'See all 5 salary steps');
    final sub = fr
        ? 'Accès Premium requis'
        : (es ? 'Requiere Premium' : 'Premium required');

    return Padding(
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg, vertical: AppSpacing.sm),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 3, sigmaY: 3),
          child: Container(
            padding: const EdgeInsets.symmetric(
                vertical: AppSpacing.md, horizontal: AppSpacing.lg),
            decoration: BoxDecoration(
              color: AppTheme.primary.withValues(alpha: 0.06),
              border:
                  Border.all(color: AppTheme.primary.withValues(alpha: 0.2)),
              borderRadius: BorderRadius.circular(AppRadius.md),
            ),
            child: Row(children: [
              Icon(Icons.lock_outline_rounded,
                  size: 16, color: AppTheme.primary),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(label,
                          style: TextStyle(
                              fontSize: AppTextSize.sm,
                              fontWeight: FontWeight.w600,
                              color: AppTheme.primary)),
                      Text(sub,
                          style: TextStyle(
                              fontSize: AppTextSize.xs,
                              color: AppTheme.labelGray)),
                    ]),
              ),
              InkWell(
                onTap: onUnlock,
                borderRadius: BorderRadius.circular(AppRadius.lg),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.md, vertical: AppSpacing.xs),
                  decoration: BoxDecoration(
                    color: AppTheme.primary,
                    borderRadius: BorderRadius.circular(AppRadius.lg),
                  ),
                  child: Text(
                    fr ? 'Débloquer' : (es ? 'Desbloquear' : 'Unlock'),
                    style: const TextStyle(
                        fontSize: AppTextSize.sm,
                        fontWeight: FontWeight.w600,
                        color: Colors.white),
                  ),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}
