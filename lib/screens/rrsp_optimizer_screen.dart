import 'dart:math' show min, pow;

import 'package:flutter/material.dart';
import 'history_screen.dart' show HistoryScreen;
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../core/flavor_config.dart';
import '../core/salary_engine.dart';
import '../core/theme/app_theme.dart';
import '../core/analytics/analytics_service.dart';
import '../core/freemium/freemium_service.dart';
import '../core/freemium/iap_service.dart';
import '../core/services/pdf_export_service.dart';
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
        PaywallTrigger,
        AppSpacing,
        AppRadius,
        AppTextSize,
        ResultHasher;

// ─── RRSP Optimizer (CA flavor only) ────────────────────────────────────────
//
// How much RRSP contribution minimizes tax to reach a target federal bracket.
// 2025 RRSP hard cap: $32,490 (18% of prior year earned income, max $32,490).
// Basic Personal Amount 2025: $16,129.


// ─── Federal bracket ceilings 2025 (post-BPA taxable income) ─────────────────
// These are the tops of each bracket applied to (grossIncome - BPA).
// 15%  → up to $57,375 taxable    (ceiling relative to BPA-adjusted income)
// 20.5%→ up to $114,750 taxable
// 26%  → up to $158,519 taxable
// 29%  → up to $220,000 taxable
// 33%  → above $220,000

class _Bracket {
  final String label;
  final double rate;
  final double taxableMax; // top of bracket in BPA-adjusted taxable income

  const _Bracket(this.label, this.rate, this.taxableMax);
}

const _brackets = [
  _Bracket('15%', 0.15, 57375),
  _Bracket('20.5%', 0.205, 114750),
  _Bracket('26%', 0.26, 177882),
  _Bracket('29%', 0.29, 253414),
  _Bracket('33%', 0.33, double.infinity),
];

const _provinces = [
  'AB',
  'BC',
  'MB',
  'NB',
  'NL',
  'NS',
  'ON',
  'PE',
  'QC',
  'SK',
];

const _provinceNames = {
  'AB': 'Alberta',
  'BC': 'British Columbia',
  'MB': 'Manitoba',
  'NB': 'New Brunswick',
  'NL': 'Newfoundland',
  'NS': 'Nova Scotia',
  'ON': 'Ontario',
  'PE': 'PEI',
  'QC': 'Québec',
  'SK': 'Saskatchewan',
};

class _RrspResult {
  final double grossIncome;
  final double rrspRoom;
  final double contribution;
  final double taxSaving;
  final double netCost;
  final double remainingRoom;
  final double taxableAfterRrsp;
  final String bracketLabel;
  final double marginalRate;

  const _RrspResult({
    required this.grossIncome,
    required this.rrspRoom,
    required this.contribution,
    required this.taxSaving,
    required this.netCost,
    required this.remainingRoom,
    required this.taxableAfterRrsp,
    required this.bracketLabel,
    required this.marginalRate,
  });
}

class _RrspEngine {
  _RrspEngine._();

  static const double _bpa2025 = 16129;

  static double calcRrspToReachBracket(
      double grossIncome, double targetBracketCeiling, double rrspRoom) {
    final taxableAfterBPA = grossIncome - _bpa2025;
    if (taxableAfterBPA <= targetBracketCeiling) return 0;
    return min(taxableAfterBPA - targetBracketCeiling, rrspRoom);
  }

  static double _marginalRate(double grossIncome, [String province = '']) {
    // Federal marginal rate on gross - BPA
    final taxable = (grossIncome - _bpa2025).clamp(0.0, double.infinity);
    if (taxable <= 57375) return 0.15;
    if (taxable <= 114750) return 0.205;
    if (taxable <= 177882) return 0.26;
    if (taxable <= 253414) return 0.29;
    return 0.33;
  }

  static _RrspResult calculate({
    required double grossIncome,
    required double rrspRoom,
    required int targetBracketIndex,
    required String province,
  }) {
    final bracket = _brackets[targetBracketIndex];
    final contribution =
        calcRrspToReachBracket(grossIncome, bracket.taxableMax, rrspRoom);

    final marginalRate = _marginalRate(grossIncome, province);
    // Also fold in approximate provincial rate
    final provRate = _estimateProvincialMarginalRate(grossIncome, province);
    final effectiveMarginal = marginalRate + provRate;

    final taxSaving = contribution * effectiveMarginal;
    final netCost = contribution - taxSaving;
    final remainingRoom = (rrspRoom - contribution).clamp(0.0, double.infinity);
    final taxableAfterRrsp =
        ((grossIncome - _bpa2025 - contribution).clamp(0.0, double.infinity));

    // Determine actual bracket after RRSP
    String finalBracket = '33%';
    if (taxableAfterRrsp <= 57375) {
      finalBracket = '15%';
    } else if (taxableAfterRrsp <= 114750) {
      finalBracket = '20.5%';
    } else if (taxableAfterRrsp <= 177882) {
      finalBracket = '26%';
    } else if (taxableAfterRrsp <= 253414) {
      finalBracket = '29%';
    }

    return _RrspResult(
      grossIncome: grossIncome,
      rrspRoom: rrspRoom,
      contribution: contribution,
      taxSaving: taxSaving,
      netCost: netCost,
      remainingRoom: remainingRoom,
      taxableAfterRrsp: taxableAfterRrsp,
      bracketLabel: finalBracket,
      marginalRate: effectiveMarginal,
    );
  }

  static double _estimateProvincialMarginalRate(
      double grossIncome, String province) {
    // Approximate provincial marginal rate at this income level
    switch (province) {
      case 'QC':
        if (grossIncome > 126000) return 0.2575;
        if (grossIncome > 103545) return 0.24;
        if (grossIncome > 51780) return 0.19;
        return 0.14;
      case 'ON':
        if (grossIncome > 220000) return 0.1316;
        if (grossIncome > 150000) return 0.1216;
        if (grossIncome > 102894) return 0.1116;
        if (grossIncome > 51446) return 0.0915;
        return 0.0505;
      case 'BC':
        if (grossIncome > 172602) return 0.1680;
        if (grossIncome > 127299) return 0.1470;
        if (grossIncome > 104835) return 0.1229;
        if (grossIncome > 91310) return 0.1050;
        if (grossIncome > 45654) return 0.0770;
        return 0.0506;
      default:
        return 0.10;
    }
  }
}

// ─── Screen ───────────────────────────────────────────────────────────────────

class RrspOptimizerScreen extends StatefulWidget {
  const RrspOptimizerScreen({super.key});

  @override
  State<RrspOptimizerScreen> createState() => _RrspOptimizerScreenState();
}

class _RrspOptimizerScreenState extends State<RrspOptimizerScreen> {
  final _grossCtrl = TextEditingController();
  final _rrspRoomCtrl = TextEditingController(text: '32490');

  String _province = 'ON';
  int _targetBracketIndex = 1; // 20.5% default

  _RrspResult? _result;
  bool _hasCalculated = false;

  @override
  void initState() {
    super.initState();
    analyticsService.logScreenView('rrsp_optimizer');
    final salary = salaryNotifier.value;
    _grossCtrl.text = salary > 0 ? salary.toStringAsFixed(0) : '75000';

    // Auto-calculate on load for all users (free users see gated results)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _calculate();
    });
    _grossCtrl.addListener(() { if (mounted) _calculate(); });
    _rrspRoomCtrl.addListener(() { if (mounted) _calculate(); });
  }

  @override
  void dispose() {
    historyService.cancelPendingSave('salaryapp', 'rrsp_optimizer');
    _grossCtrl.dispose();
    _rrspRoomCtrl.dispose();
    super.dispose();
  }

  // ── SmartHistory helpers ──────────────────────────────────────────────────

  double _roundTo(double v, double step) => (v / step).round() * step;

  String _buildHash() {
    final gross = _parse(_grossCtrl);
    final room = _parse(_rrspRoomCtrl);
    return ResultHasher.hashMixed({
      'flavor': 'ca',
      'gross': _roundTo(gross, 1000),
      'room': _roundTo(room, 1000),
      'bracket': _targetBracketIndex,
      'province': _province,
    });
  }

  Map<String, dynamic> _buildL1() {
    final r = _result;
    if (r == null) return {};
    return {
      'gross': r.grossIncome,
      'contribution': r.contribution,
      'tax_saving': r.taxSaving,
      'bracket': r.bracketLabel,
    };
  }

  Map<String, dynamic> _buildL2() {
    final r = _result;
    if (r == null) return {};
    return {
      'inputs': {
        'gross': r.grossIncome,
        'rrsp_room': r.rrspRoom,
        'target_bracket_index': _targetBracketIndex,
        'province': _province,
      },
      'results': {
        'contribution': r.contribution,
        'tax_saving': r.taxSaving,
        'net_cost': r.netCost,
        'remaining_room': r.remainingRoom,
        'taxable_after_rrsp': r.taxableAfterRrsp,
        'bracket_label': r.bracketLabel,
        'marginal_rate': r.marginalRate,
      },
    };
  }

  Future<void> _scheduleAutoSave() async {
    if (_result == null) return;
    historyService.scheduleAutoSave(
      appKey: 'salaryapp',
      screenId: 'rrsp_optimizer',
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
      final fr = FlavorConfig.isCA && isSpanishNotifier.value;
      await PaywallSoft.show(
        context,
        isFrench: fr,
        featureTitle: fr ? 'Sauvegarder le scénario' : 'Save Scenario',
        featureSubtitle: fr
            ? 'Épinglez vos calculs pour les retrouver plus tard'
            : 'Pin your calculations to revisit them later',
        priceLabel: IAPService.instance.localizedPrice.value,
        onUnlock: () => PaywallHard.show(context),
      );
      return;
    }
    if (_result == null) return;
    await historyService.saveScenario(
      appKey: 'salaryapp',
      screenId: 'rrsp_optimizer',
      inputHash: _buildHash(),
      l1: _buildL1(),
      l2: _buildL2(),
      label: label,
    );
    HistoryScreen.refreshNotifier.value++;
    adService.onSave();
    final trigger = await paywallSession.recordAction();
    if (!mounted) return;
    if (trigger == PaywallTrigger.soft) PaywallSoft.show(context);
    if (trigger == PaywallTrigger.hard) PaywallHard.show(context);
  }

  Future<void> _exportPdf(bool fr) async {
    final r = _result;
    if (r == null) return;
    await PdfExportService.exportRrsp(
      context: context,
      grossIncome: r.grossIncome,
      rrspRoom: r.rrspRoom,
      contribution: r.contribution,
      taxSaving: r.taxSaving,
      netCost: r.netCost,
      remainingRoom: r.remainingRoom,
      marginalRate: r.marginalRate,
      bracketLabel: r.bracketLabel,
      province: _province,
      fr: fr,
    );
    analyticsService.logPdfExported();
  }

  double _parse(TextEditingController c) {
    final raw = c.text.replaceAll(',', '').replaceAll(RegExp(r'[^\d.]'), '');
    return double.tryParse(raw) ?? 0;
  }

  void _calculate() {
    final gross = _parse(_grossCtrl);
    final room = _parse(_rrspRoomCtrl);
    if (gross <= 0) return;

    AnalyticsService.instance.maybeLogFirstCalculate();

    final result = _RrspEngine.calculate(
      grossIncome: gross,
      rrspRoom: room.clamp(0, 32490),
      targetBracketIndex: _targetBracketIndex,
      province: _province,
    );

    setState(() {
      _result = result;
      _hasCalculated = true;
    });
    _scheduleAutoSave();
    adService.onAction();

    analyticsService.logRrspImpactCalculated();
  }

  String _fmt(double v) =>
      NumberFormat.currency(symbol: 'CA\$', decimalDigits: 0).format(v);

  String _pct(double v) => '${(v * 100).toStringAsFixed(1)}%';

  @override
  Widget build(BuildContext context) {
    if (!FlavorConfig.isCA) {
      return const Scaffold(body: Center(child: Text('CA flavor only')));
    }

    return ValueListenableBuilder<bool>(
      valueListenable: isSpanishNotifier,
      builder: (context, useAlt, _) {
        final fr = FlavorConfig.isCA && useAlt;

        final titleStr = fr ? 'Optimiseur REER' : 'RRSP Optimizer';
        final grossLabel = fr ? 'Revenu annuel brut' : 'Gross Annual Income';
        final rrspRoomLabel =
            fr ? 'Droits REER disponibles' : 'RRSP Contribution Room';
        final bracketLabel = fr ? 'Tranche cible' : 'Target Federal Bracket';
        final provinceLabel = fr ? 'Province' : 'Province';

        return Scaffold(
          appBar: AppBar(
            title: Text(titleStr),
          ),
          body: GestureDetector(
            onTap: () => FocusScope.of(context).unfocus(),
            child: CalcwisePageEntrance(
              child: Column(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        fr
                            ? 'Combien cotiser au REER pour réduire votre tranche d\'imposition ?'
                            : 'How much to contribute to RRSP to drop to your target tax bracket?',
                        style: TextStyle(
                          fontSize: AppTextSize.md,
                          color: AppTheme.labelGray,
                        ),
                      ),
                      const SizedBox(height: 20),

                      // ── Inputs ──────────────────────────────────────────────
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(AppSpacing.lg),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              TextFormField(
                                controller: _grossCtrl,
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                        decimal: true),
                                textInputAction: TextInputAction.next,
                                inputFormatters: [
                                  CurrencyInputFormatter(locale: 'en_CA'),
                                ],
                                decoration: InputDecoration(
                                  labelText: grossLabel,
                                  prefixText: 'CA\$ ',
                                  hintText: '85000',
                                ),
                                style: const TextStyle(
                                    fontSize: AppTextSize.bodyLg,
                                    fontWeight: FontWeight.w600),
                              ),
                              const SizedBox(height: 16),
                              TextFormField(
                                controller: _rrspRoomCtrl,
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                        decimal: true),
                                textInputAction: TextInputAction.done,
                                inputFormatters: [
                                  CurrencyInputFormatter(locale: 'en_CA'),
                                ],
                                decoration: InputDecoration(
                                  labelText: rrspRoomLabel,
                                  prefixText: 'CA\$ ',
                                  hintText: '32490',
                                  helperText: fr
                                      ? 'Max 2025 : 32 490 \$ (18% du revenu gagné)'
                                      : '2025 max: \$32,490 (18% of prior year earned income)',
                                ),
                                style: const TextStyle(
                                    fontSize: AppTextSize.bodyLg,
                                    fontWeight: FontWeight.w600),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),

                      // ── Province selector ────────────────────────────────────
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(AppSpacing.lg),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                provinceLabel,
                                style: TextStyle(
                                    fontSize: AppTextSize.md,
                                    fontWeight: FontWeight.w600,
                                    color: AppTheme.labelGray),
                              ),
                              const SizedBox(height: 8),
                              DropdownButtonFormField<String>(
                                value: _province,
                                decoration: const InputDecoration(
                                  isDense: true,
                                  contentPadding: EdgeInsets.symmetric(
                                      horizontal: 12, vertical: 8),
                                ),
                                items: _provinces
                                    .map((p) => DropdownMenuItem(
                                          value: p,
                                          child: Text(_provinceNames[p] ?? p,
                                              style: const TextStyle(
                                                  fontSize: AppTextSize.body)),
                                        ))
                                    .toList(),
                                onChanged: (v) {
                                  if (v == null) return;
                                  analyticsService.logProvinceSwitched(v);
                                  setState(() => _province = v);
                                  _calculate();
                                },
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),

                      // ── Target bracket ───────────────────────────────────────
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(AppSpacing.lg),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                bracketLabel,
                                style: TextStyle(
                                    fontSize: AppTextSize.md,
                                    fontWeight: FontWeight.w600,
                                    color: AppTheme.labelGray),
                              ),
                              const SizedBox(height: 8),
                              Builder(builder: (context) {
                                final gross = _parse(_grossCtrl);
                                final taxable = (gross - _RrspEngine._bpa2025)
                                    .clamp(0.0, double.infinity);
                                // Index of the bracket the user is currently in
                                int currentBracket = 0;
                                for (int k = 0; k < _brackets.length; k++) {
                                  if (taxable > _brackets[k].taxableMax) {
                                    currentBracket = k + 1;
                                  }
                                }
                                return Wrap(
                                  spacing: 8,
                                  runSpacing: 6,
                                  children: List.generate(
                                    _brackets.length,
                                    (i) {
                                      final isSelected =
                                          i == _targetBracketIndex;
                                      // Only grey out brackets at/above current
                                      // when there IS a lower bracket to target.
                                      // If already in 15% (currentBracket==0),
                                      // don't disable anything — all will show $0
                                      // with the "already in bracket" message.
                                      final isDisabled =
                                          currentBracket > 0 && i >= currentBracket;
                                      return ChoiceChip(
                                        label: Text(_brackets[i].label),
                                        selected: isSelected,
                                        selectedColor: AppTheme.primary,
                                        disabledColor: Colors.grey.shade200,
                                        labelStyle: TextStyle(
                                          color: isDisabled
                                              ? Colors.grey.shade400
                                              : isSelected
                                                  ? Colors.white
                                                  : AppTheme.labelGray,
                                          fontWeight: isSelected
                                              ? FontWeight.w600
                                              : FontWeight.normal,
                                          fontSize: AppTextSize.md,
                                        ),
                                        onSelected: isDisabled
                                            ? null
                                            : (_) {
                                                setState(() =>
                                                    _targetBracketIndex = i);
                                                _calculate();
                                              },
                                      );
                                    },
                                  ),
                                );
                              }),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),

                      // ── Results ──────────────────────────────────────────────
                      if (_hasCalculated && _result != null) ...[
                        const SizedBox(height: 24),
                        if (freemiumService.hasFullAccess)
                          _buildResults(context, _result!, fr)
                        else ...[
                          // Show hero card as preview
                          CalcwiseHeroCard(
                            label: fr
                                ? 'Cotisation REER recommandée'
                                : 'Recommended RRSP Contribution',
                            value: _fmt(_result!.contribution),
                            secondary: _result!.contribution == 0
                                ? (fr
                                    ? 'Vous êtes déjà dans la tranche cible'
                                    : 'You\'re already in the target bracket')
                                : null,
                            rawValue: _result!.contribution,
                            valueFormatter: (v) => AmountFormatter.ui(v, 'CAD'),
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
                          const SizedBox(height: 12),
                          CalcwisePremiumGate(
                            title: fr
                                ? 'Analyse REER complète'
                                : 'Full RRSP Analysis',
                            description: fr
                                ? 'Remboursement fiscal, coût net, taux marginal et droits restants.'
                                : 'Tax refund, net cost, marginal rate and remaining room.',
                            onUnlock: () => PaywallHard.show(context),
                            price: IAPService.instance.localizedPrice,
                          ),
                        ],
                      ],

                      const SizedBox(height: 16),
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

  Widget _buildResults(BuildContext context, _RrspResult r, bool fr) {
    final heroLabel =
        fr ? 'Cotisation REER recommandée' : 'Recommended RRSP Contribution';
    final heroValue = _fmt(r.contribution);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Hero card
        CalcwiseHeroCard(
          label: heroLabel,
          value: heroValue,
          secondary: r.contribution == 0
              ? (fr
                  ? 'Vous êtes déjà dans la tranche cible'
                  : 'You\'re already in the target bracket')
              : null,
          rawValue: r.contribution,
          valueFormatter: (v) => AmountFormatter.ui(v, 'CAD'),
          rawStats: [
            (label: fr ? 'Remboursement fiscal estimé' : 'Estimated Tax Refund', value: r.taxSaving, formatter: (v) => AmountFormatter.ui(v, 'CAD')),
            (label: fr ? 'Coût net après remboursement' : 'Net Cost After Refund', value: r.netCost, formatter: (v) => AmountFormatter.ui(v, 'CAD')),
          ],
          gradient: LinearGradient(
            colors: [
              AppTheme.primary,
              AppTheme.primary.withValues(alpha: 0.75)
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        const SizedBox(height: 12),

        Card(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Column(
                children: [
                  MetricRow(
                    label: fr
                        ? 'Remboursement fiscal estimé'
                        : 'Estimated Tax Refund',
                    value: _fmt(r.taxSaving),
                    valueColor: AppTheme.success,
                  ),
                  MetricRow(
                    label: fr
                        ? 'Coût net après remboursement'
                        : 'Net Cost After Refund',
                    value: _fmt(r.netCost),
                    valueColor: AppTheme.primary,
                  ),
                  MetricRow(
                    label:
                        fr ? 'Taux marginal combiné' : 'Combined Marginal Rate',
                    value: _pct(r.marginalRate),
                  ),
                  MetricRow(
                    label: fr
                        ? 'Tranche après cotisation'
                        : 'Bracket After Contribution',
                    value: r.bracketLabel,
                    valueColor: AppTheme.success,
                  ),
                  MetricRow(
                    label: fr ? 'Droits REER restants' : 'Remaining RRSP Room',
                    value: _fmt(r.remainingRoom),
                  ),
                ],
              ),
            ),
          ),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Text(
            fr
                ? '* Estimations basées sur les taux fédéraux 2025 et les taux provinciaux approximatifs. Consultez un conseiller fiscal pour un avis personnalisé.'
                : '* Estimates based on 2025 federal rates and approximate provincial rates. Consult a tax advisor for personalized advice.',
            style: TextStyle(
              fontSize: AppTextSize.xs,
              color: AppTheme.labelGray,
              fontStyle: FontStyle.italic,
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        SaveScenarioButton(onSave: _saveScenario),
        const SizedBox(height: AppSpacing.sm),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: () =>
                PdfExportService.showUnlockOrPay(context, () => _exportPdf(fr)),
            icon: const Icon(Icons.picture_as_pdf_rounded, size: 18),
            label: Text(fr ? 'Exporter PDF' : 'Export PDF'),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppTheme.primary,
              minimumSize: const Size(double.infinity, 48),
              side:
                  BorderSide(color: AppTheme.primary.withValues(alpha: 0.4)),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppRadius.lg)),
              padding:
                  const EdgeInsets.symmetric(vertical: AppSpacing.md),
            ),
          ),
        ),
      ],
    );
  }
}
