import 'dart:async';
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
        CalcwiseTax,
        CurrencyInputFormatter,
        PaywallHard,
        PaywallSoft,
        PaywallTrigger,
        AppSpacing,
        AppRadius,
        AppTextSize,
        ResultHasher,
        TaxBand;

// ─── RRSP Optimizer (CA flavor only) ────────────────────────────────────────
//
// How much RRSP contribution minimizes tax to reach a target federal bracket.
// 2025 RRSP hard cap: $32,490 (18% of prior year earned income, max $32,490).
//
// Federal brackets, Basic Personal Amount and provincial marginal rates are
// sourced from the shared CalcwiseTax registry (2026) — no longer hardcoded
// here — so this display can never diverge from the salary engine.

const int _kTaxYear = 2026;

// ─── Federal display bracket ─────────────────────────────────────────────────
// A purely-presentational row derived from the registry's federal bands. The
// registry's `bands[i].upTo` is already the top of the bracket expressed in
// BPA-adjusted *taxable* income, which is exactly what [taxableMax] means here.

class _Bracket {
  final String label;
  final double rate;
  final double taxableMax; // top of bracket in BPA-adjusted taxable income

  const _Bracket(this.label, this.rate, this.taxableMax);
}

String _trimPct(double pct) => pct == pct.roundToDouble()
    ? pct.toStringAsFixed(0)
    : pct.toStringAsFixed(1);

/// Federal display brackets, derived from the CalcwiseTax registry (2026).
List<_Bracket> _buildFederalBrackets() {
  final set = CalcwiseTax.registry.annual('ca_federal', _kTaxYear);
  if (set == null) return const [];
  return [
    for (final b in set.bands)
      _Bracket('${_trimPct(b.rate * 100)}%', b.rate, b.upTo),
  ];
}

final List<_Bracket> _brackets = _buildFederalBrackets();

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

  /// Maps a two-letter province postal code to its registry jurisdiction code.
  static const Map<String, String> _provinceJurisdiction = {
    'ON': 'ca_on',
    'QC': 'ca_qc',
    'BC': 'ca_bc',
    'AB': 'ca_ab',
    'MB': 'ca_mb',
    'SK': 'ca_sk',
    'NS': 'ca_ns',
    'NB': 'ca_nb',
    'NL': 'ca_nl',
    'PE': 'ca_pe',
  };

  /// Federal Basic Personal Amount, sourced from the registry (2026).
  static double get _bpa {
    final set = CalcwiseTax.registry.annual('ca_federal', _kTaxYear);
    return set?.basicPersonalAmount ?? 0;
  }

  /// The marginal rate of [bands] at a given (already-allowance-adjusted)
  /// [taxable] income. Returns the top band's rate above the last ceiling.
  static double _marginalForTaxable(List<TaxBand> bands, double taxable) {
    if (bands.isEmpty) return 0;
    for (final b in bands) {
      if (taxable <= b.upTo) return b.rate;
    }
    return bands.last.rate;
  }

  static double calcRrspToReachBracket(
      double grossIncome, double targetBracketCeiling, double rrspRoom) {
    final taxableAfterBPA = grossIncome - _bpa;
    if (taxableAfterBPA <= targetBracketCeiling) return 0;
    return min(taxableAfterBPA - targetBracketCeiling, rrspRoom);
  }

  /// Federal marginal rate on (gross − federal BPA), from the registry bands.
  static double _marginalRate(double grossIncome) {
    final set = CalcwiseTax.registry.annual('ca_federal', _kTaxYear);
    if (set == null) return 0;
    final taxable = (grossIncome - (set.basicPersonalAmount ?? 0))
        .clamp(0.0, double.infinity);
    return _marginalForTaxable(set.bands, taxable);
  }

  static _RrspResult calculate({
    required double grossIncome,
    required double rrspRoom,
    required int targetBracketIndex,
    required String province,
  }) {
    final fedSet = CalcwiseTax.registry.annual('ca_federal', _kTaxYear);
    final bpa = fedSet?.basicPersonalAmount ?? 0;
    final bracket = _brackets[targetBracketIndex];
    final contribution =
        calcRrspToReachBracket(grossIncome, bracket.taxableMax, rrspRoom);

    final marginalRate = _marginalRate(grossIncome);
    // Also fold in the provincial marginal rate (registry-derived).
    final provRate = _estimateProvincialMarginalRate(grossIncome, province);
    final effectiveMarginal = marginalRate + provRate;

    final taxSaving = contribution * effectiveMarginal;
    final netCost = contribution - taxSaving;
    final remainingRoom = (rrspRoom - contribution).clamp(0.0, double.infinity);
    final taxableAfterRrsp =
        ((grossIncome - bpa - contribution).clamp(0.0, double.infinity));

    // Determine actual federal bracket after RRSP, from the registry bands.
    final bands = fedSet?.bands ?? const [];
    String finalBracket = _brackets.isNotEmpty ? _brackets.last.label : '';
    for (final b in bands) {
      if (taxableAfterRrsp <= b.upTo) {
        finalBracket = '${_trimPct(b.rate * 100)}%';
        break;
      }
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

  /// Provincial marginal rate, derived from the registry's provincial bands
  /// (2026). The registry bands' `upTo` are expressed in *taxable* income
  /// (after the provincial BPA), so we apply the provincial BPA before the
  /// lookup. Unknown codes fall back to a 10% flat approximation.
  static double _estimateProvincialMarginalRate(
      double grossIncome, String province) {
    final code = _provinceJurisdiction[province];
    final set = code == null
        ? null
        : CalcwiseTax.registry.annual(code, _kTaxYear);
    if (set == null) return 0.10;
    final taxable = (grossIncome - (set.basicPersonalAmount ?? 0))
        .clamp(0.0, double.infinity);
    return _marginalForTaxable(set.bands, taxable);
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
  int _targetBracketIndex = 0; // 15% default — shows non-zero contribution for most salaries

  _RrspResult? _result;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    analyticsService.logScreenView('rrsp_optimizer');
    final salary = salaryNotifier.value;
    _grossCtrl.text = salary > 0 ? salary.toStringAsFixed(0) : '98000';

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _calculate();
    });
    _grossCtrl.addListener(_onInputChanged);
    _rrspRoomCtrl.addListener(_onInputChanged);
    salaryNotifier.addListener(_onMainSalaryChanged);
  }

  void _onInputChanged() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      if (mounted) _calculate();
    });
  }

  void _onMainSalaryChanged() {
    final salary = salaryNotifier.value;
    if (salary > 0 && mounted) {
      _grossCtrl.text = salary.toStringAsFixed(0);
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    salaryNotifier.removeListener(_onMainSalaryChanged);
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

    setState(() => _result = result);
    _scheduleAutoSave();
    analyticsService.logRrspImpactCalculated();
  }

  String _fmt(double v) =>
      NumberFormat.currency(symbol: FlavorConfig.currencySymbol, decimalDigits: 0).format(v);

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
                      // ── Hero result (top) ────────────────────────────────────
                      if (_result != null) ...[
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
                            rawStats: [
                              (label: fr ? 'Remboursement fiscal estimé' : 'Estimated Tax Refund', value: _result!.taxSaving, formatter: (v) => AmountFormatter.ui(v, 'CAD')),
                              (label: fr ? 'Coût net après remboursement' : 'Net Cost After Refund', value: _result!.netCost, formatter: (v) => AmountFormatter.ui(v, 'CAD')),
                            ],
                            gradient: LinearGradient(
                              colors: [AppTheme.primary, AppTheme.primary.withValues(alpha: 0.75)],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                          ),
                        const SizedBox(height: 8),
                        Text(
                          fr
                              ? 'Calculez la cotisation REER idéale pour descendre dans une tranche d\'imposition inférieure.'
                              : 'Find the ideal RRSP contribution to drop into a lower federal tax bracket.',
                          style: TextStyle(
                            fontSize: AppTextSize.sm,
                            color: AppTheme.labelGray,
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],

                      // ── Inputs ──────────────────────────────────────────────
                      Text(
                        fr ? 'Paramètres' : 'Parameters',
                        style: TextStyle(
                          fontSize: AppTextSize.sm,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.labelGray,
                          letterSpacing: 0.6,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.sm),
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
                                  prefixText: '${FlavorConfig.currencySymbol} ',
                                  hintText: '98000',
                                ),
                                style: const TextStyle(
                                    fontSize: AppTextSize.bodyLg,
                                    fontWeight: FontWeight.w600),
                              ),
                              const SizedBox(height: AppSpacing.md),
                              TextFormField(
                                controller: _rrspRoomCtrl,
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                        decimal: true),
                                textInputAction: TextInputAction.next,
                                inputFormatters: [
                                  CurrencyInputFormatter(locale: 'en_CA'),
                                ],
                                decoration: InputDecoration(
                                  labelText: rrspRoomLabel,
                                  prefixText: '${FlavorConfig.currencySymbol} ',
                                  hintText: '32490',
                                  helperText: fr
                                      ? 'Max 2025 : 32 490 \$ (18% du revenu gagné)'
                                      : '2025 max: \$32,490 (18% of prior year earned income)',
                                ),
                                style: const TextStyle(
                                    fontSize: AppTextSize.bodyLg,
                                    fontWeight: FontWeight.w600),
                              ),
                              const SizedBox(height: AppSpacing.md),
                              DropdownButtonFormField<String>(
                                value: _province,
                                decoration: InputDecoration(
                                  labelText: provinceLabel,
                                  isDense: true,
                                  contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 12, vertical: 12),
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
                      const SizedBox(height: AppSpacing.md),

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
                              Wrap(
                                spacing: 8,
                                runSpacing: 6,
                                children: List.generate(
                                  _brackets.length,
                                  (i) {
                                    final isSelected = i == _targetBracketIndex;
                                    return ChoiceChip(
                                      label: Text(_brackets[i].label),
                                      selected: isSelected,
                                      selectedColor: AppTheme.primary,
                                      labelStyle: TextStyle(
                                        color: isSelected
                                            ? Colors.white
                                            : AppTheme.labelGray,
                                        fontWeight: isSelected
                                            ? FontWeight.w600
                                            : FontWeight.normal,
                                        fontSize: AppTextSize.md,
                                      ),
                                      onSelected: (_) {
                                        setState(() => _targetBracketIndex = i);
                                        _calculate();
                                      },
                                    );
                                  },
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),

                      // ── Details (premium gated) ──────────────────────────────
                      if (_result != null) ...[
                        const SizedBox(height: 8),
                        _buildDetails(context, _result!, fr),
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

  Widget _buildDetails(BuildContext context, _RrspResult r, bool fr) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
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
                ? '* Estimations basées sur les taux fédéraux et provinciaux 2026. Consultez un conseiller fiscal pour un avis personnalisé.'
                : '* Estimates based on 2026 federal and provincial rates. Consult a tax advisor for personalized advice.',
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
