import 'dart:math' show min, pow;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../core/flavor_config.dart';
import '../core/salary_engine.dart';
import '../core/theme/app_theme.dart';
import '../core/analytics/analytics_service.dart';
import '../core/freemium/freemium_service.dart';
import '../core/freemium/iap_service.dart';
import '../main.dart' show isSpanishNotifier, salaryNotifier, paywallSession;
import '../widgets/result_card.dart';
import 'package:calcwise_core/calcwise_core.dart'
    show
        CalcwiseAdFooter,
        CalcwiseHeroCard,
        AppDuration,
        AppSpacing,
        AppRadius,
        AppTextSize,
        PaywallSoft,
        PaywallSessionService;

// ─── 401(k) Optimizer (US flavor only) ───────────────────────────────────────
//
// Optimal 401(k) contribution for federal tax minimization.
// IRS 2025 limits: Under-50 → $23,500 | 50+ → $31,000 (catch-up $7,500).

// ─── Filing status ────────────────────────────────────────────────────────────
enum _FilingStatus { single, marriedFilingJointly }

// ─── Engine ───────────────────────────────────────────────────────────────────

class _K401Engine {
  _K401Engine._();

  static const double _limitUnder50 = 23500;
  static const double _limitOver50 = 31000;
  static const double _stdSingle = 15000;
  static const double _stdMfj = 30000;

  static double contributionLimit(bool age50Plus) =>
      age50Plus ? _limitOver50 : _limitUnder50;

  static double _federalTax(double taxableIncome, _FilingStatus status) {
    if (taxableIncome <= 0) return 0;
    if (status == _FilingStatus.marriedFilingJointly) {
      return UsSalaryEngine.federalTax(
        taxableIncome +
            (status == _FilingStatus.marriedFilingJointly
                ? _stdMfj
                : _stdSingle),
        marriedFilingJointly: true,
      );
    }
    return UsSalaryEngine.federalTax(taxableIncome + _stdSingle);
  }

  static _RetirementResult calculate({
    required double grossIncome,
    required double contributionPct,
    required bool age50Plus,
    required _FilingStatus filingStatus,
    required String state,
  }) {
    final limit = contributionLimit(age50Plus);
    final contribution = min(grossIncome * contributionPct / 100, limit);

    final stdDeduction = filingStatus == _FilingStatus.marriedFilingJointly
        ? _stdMfj
        : _stdSingle;

    final taxableWithout =
        (grossIncome - stdDeduction).clamp(0.0, double.infinity);
    final taxableWith =
        (grossIncome - contribution - stdDeduction).clamp(0.0, double.infinity);

    // Federal tax calculation — pass gross so UsSalaryEngine subtracts std deduction
    final isMfj = filingStatus == _FilingStatus.marriedFilingJointly;
    final taxWithout =
        UsSalaryEngine.federalTax(grossIncome, marriedFilingJointly: isMfj);
    final taxWith = UsSalaryEngine.federalTax(grossIncome - contribution,
        marriedFilingJointly: isMfj);

    final taxSaving = taxWithout - taxWith;
    final netCost = contribution - taxSaving;
    final takeHomeChangeMonthly = -(netCost / 12);

    // Projection: compound growth at 7% annual return
    const double annualReturn = 0.07;
    const int years30 = 30;
    final projValue30 =
        contribution * ((pow(1 + annualReturn, years30) - 1) / annualReturn);

    // Verdict
    final utilizationPct = limit > 0 ? (contribution / limit) * 100 : 0;
    final isMaxed = contribution >= limit - 1;

    return _RetirementResult(
      grossIncome: grossIncome,
      contribution: contribution,
      contributionLimit: limit,
      taxSaving: taxSaving,
      netCost: netCost,
      takeHomeChangeMonthly: takeHomeChangeMonthly,
      projectedValue30yr: projValue30,
      utilizationPct: utilizationPct.toDouble(),
      isMaxed: isMaxed,
      age50Plus: age50Plus,
    );
  }
}

class _RetirementResult {
  final double grossIncome;
  final double contribution;
  final double contributionLimit;
  final double taxSaving;
  final double netCost;
  final double takeHomeChangeMonthly;
  final double projectedValue30yr;
  final double utilizationPct;
  final bool isMaxed;
  final bool age50Plus;

  const _RetirementResult({
    required this.grossIncome,
    required this.contribution,
    required this.contributionLimit,
    required this.taxSaving,
    required this.netCost,
    required this.takeHomeChangeMonthly,
    required this.projectedValue30yr,
    required this.utilizationPct,
    required this.isMaxed,
    required this.age50Plus,
  });
}

// ─── Screen ───────────────────────────────────────────────────────────────────

class RetirementOptimizerScreen extends StatefulWidget {
  const RetirementOptimizerScreen({super.key});

  @override
  State<RetirementOptimizerScreen> createState() =>
      _RetirementOptimizerScreenState();
}

class _RetirementOptimizerScreenState extends State<RetirementOptimizerScreen> {
  final _grossCtrl = TextEditingController();

  double _contributionPct = 10.0; // 10% default
  bool _age50Plus = false;
  _FilingStatus _filingStatus = _FilingStatus.single;
  String _state = 'TX';

  _RetirementResult? _result;
  bool _hasCalculated = false;

  @override
  void initState() {
    super.initState();
    final salary = salaryNotifier.value;
    _grossCtrl.text = salary > 0 ? salary.toStringAsFixed(0) : '75000';
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _calculate();
    });
  }

  @override
  void dispose() {
    _grossCtrl.dispose();
    super.dispose();
  }

  double _parseGross() {
    final raw =
        _grossCtrl.text.replaceAll(',', '').replaceAll(RegExp(r'[^\d.]'), '');
    return double.tryParse(raw) ?? 0;
  }

  void _calculate() {
    final gross = _parseGross();
    if (gross <= 0) return;

    HapticFeedback.mediumImpact();
    FocusScope.of(context).unfocus();

    final result = _K401Engine.calculate(
      grossIncome: gross,
      contributionPct: _contributionPct,
      age50Plus: _age50Plus,
      filingStatus: _filingStatus,
      state: _state,
    );

    setState(() {
      _result = result;
      _hasCalculated = true;
    });

    analyticsService.logCalculationCompleted(
        params: {'screen': '401k_optimizer', 'pct': _contributionPct.round()});
  }

  Future<void> _showPaywall(bool es) async {
    await PaywallSoft.show(
      context,
      isSpanish: es,
      featureTitle: es ? 'Optimizador 401(k)' : '401(k) Optimizer',
      featureSubtitle: es
          ? 'Desbloquea proyecciones y análisis completo'
          : 'Unlock projections and full tax analysis',
      priceLabel: IAPService.instance.localizedPrice.value,
      onUnlock: () => IAPService.instance.buy(),
    );
    if (mounted) setState(() {});
  }

  String _fmt(double v) =>
      NumberFormat.currency(symbol: '\$', decimalDigits: 0).format(v);

  String _fmtLarge(double v) {
    if (v >= 1000000) {
      return '\$${(v / 1000000).toStringAsFixed(2)}M';
    }
    if (v >= 1000) {
      return '\$${(v / 1000).toStringAsFixed(0)}K';
    }
    return _fmt(v);
  }

  @override
  Widget build(BuildContext context) {
    if (!FlavorConfig.isUS) {
      return const Scaffold(body: Center(child: Text('US flavor only')));
    }

    return ValueListenableBuilder<bool>(
      valueListenable: isSpanishNotifier,
      builder: (context, useAlt, _) {
        final es = FlavorConfig.isUS && useAlt;

        final titleStr = es ? 'Optimizador 401(k)' : '401(k) Optimizer';
        final grossLabel = es ? 'Salario bruto anual' : 'Gross Annual Salary';
        final contribLabel = es ? 'Aportación %' : 'Contribution %';
        final ageLabel = es ? 'Edad' : 'Age';
        final filingLabel = es ? 'Estado civil' : 'Filing Status';
        final stateLabel = es ? 'Estado' : 'State';
        final calcLabel = es ? 'Calcular' : 'Calculate';

        // Soft gate: session >= 4 and not premium
        final shouldGate =
            !freemiumService.hasFullAccess && paywallSession.sessionCount >= 4;

        return Scaffold(
          appBar: AppBar(
            title: Text(titleStr),
          ),
          body: Column(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        es
                            ? 'Optimiza tus aportes al 401(k) para minimizar impuestos federales'
                            : 'Optimize your 401(k) contributions to minimize federal taxes',
                        style: TextStyle(
                          fontSize: AppTextSize.md,
                          color: AppTheme.labelGray,
                        ),
                      ),
                      const SizedBox(height: 20),

                      // ── Gross income ─────────────────────────────────────────
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(AppSpacing.lg),
                          child: TextFormField(
                            controller: _grossCtrl,
                            keyboardType: const TextInputType.numberWithOptions(
                                decimal: true),
                            inputFormatters: [
                              FilteringTextInputFormatter.allow(
                                  RegExp(r'[\d.,]')),
                            ],
                            decoration: InputDecoration(
                              labelText: grossLabel,
                              prefixText: '\$ ',
                              hintText: '75000',
                            ),
                            style: const TextStyle(
                                fontSize: AppTextSize.bodyLg,
                                fontWeight: FontWeight.w600),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),

                      // ── Contribution slider ──────────────────────────────────
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(AppSpacing.lg),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    contribLabel,
                                    style: TextStyle(
                                        fontSize: AppTextSize.md,
                                        fontWeight: FontWeight.w600,
                                        color: AppTheme.labelGray),
                                  ),
                                  Text(
                                    '${_contributionPct.toStringAsFixed(0)}%',
                                    style: TextStyle(
                                        fontSize: AppTextSize.bodyLg,
                                        fontWeight: FontWeight.bold,
                                        color: AppTheme.primary),
                                  ),
                                ],
                              ),
                              Slider(
                                value: _contributionPct,
                                min: 0,
                                max: 100,
                                divisions: 100,
                                activeColor: AppTheme.primary,
                                onChanged: (v) =>
                                    setState(() => _contributionPct = v),
                              ),
                              if (_parseGross() > 0) ...[
                                Text(
                                  () {
                                    final limit = _K401Engine.contributionLimit(
                                        _age50Plus);
                                    final raw =
                                        _parseGross() * _contributionPct / 100;
                                    final capped = min(raw, limit);
                                    final capped0 = NumberFormat.currency(
                                            symbol: '\$', decimalDigits: 0)
                                        .format(capped);
                                    final limited = raw > limit;
                                    if (es) {
                                      return limited
                                          ? 'Aportación: $capped0 (limitada al máximo IRS)'
                                          : 'Contribution: $capped0/yr';
                                    }
                                    return limited
                                        ? 'Contribution: $capped0 (IRS limit applies)'
                                        : 'Contribution: $capped0/yr';
                                  }(),
                                  style: TextStyle(
                                    fontSize: AppTextSize.sm,
                                    color: AppTheme.labelGray,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),

                      // ── Age toggle + filing status ───────────────────────────
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(AppSpacing.lg),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                ageLabel,
                                style: TextStyle(
                                    fontSize: AppTextSize.md,
                                    fontWeight: FontWeight.w600,
                                    color: AppTheme.labelGray),
                              ),
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  Expanded(
                                    child: _ToggleChip(
                                      label: es ? 'Menor de 50' : 'Under 50',
                                      selected: !_age50Plus,
                                      onTap: () =>
                                          setState(() => _age50Plus = false),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: _ToggleChip(
                                      label: '50+',
                                      selected: _age50Plus,
                                      onTap: () =>
                                          setState(() => _age50Plus = true),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Text(
                                _age50Plus
                                    ? (es
                                        ? 'Límite IRS 2025: \$31,000 (incluye catch-up de \$7,500)'
                                        : 'IRS 2025 limit: \$31,000 (includes \$7,500 catch-up)')
                                    : (es
                                        ? 'Límite IRS 2025: \$23,500'
                                        : 'IRS 2025 limit: \$23,500'),
                                style: TextStyle(
                                  fontSize: AppTextSize.sm,
                                  color: AppTheme.labelGray,
                                ),
                              ),
                              const SizedBox(height: 16),
                              Text(
                                filingLabel,
                                style: TextStyle(
                                    fontSize: AppTextSize.md,
                                    fontWeight: FontWeight.w600,
                                    color: AppTheme.labelGray),
                              ),
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  Expanded(
                                    child: _ToggleChip(
                                      label: es ? 'Soltero' : 'Single',
                                      selected:
                                          _filingStatus == _FilingStatus.single,
                                      onTap: () => setState(() =>
                                          _filingStatus = _FilingStatus.single),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: _ToggleChip(
                                      label: es
                                          ? 'Casado conjunto'
                                          : 'Married (MFJ)',
                                      selected: _filingStatus ==
                                          _FilingStatus.marriedFilingJointly,
                                      onTap: () => setState(() =>
                                          _filingStatus = _FilingStatus
                                              .marriedFilingJointly),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),

                      // ── State selector ───────────────────────────────────────
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(AppSpacing.lg),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                stateLabel,
                                style: TextStyle(
                                    fontSize: AppTextSize.md,
                                    fontWeight: FontWeight.w600,
                                    color: AppTheme.labelGray),
                              ),
                              const SizedBox(height: 8),
                              DropdownButtonFormField<String>(
                                value: _state,
                                decoration: const InputDecoration(
                                  isDense: true,
                                  contentPadding: EdgeInsets.symmetric(
                                      horizontal: 12, vertical: 8),
                                ),
                                items: UsSalaryEngine.states
                                    .map((s) => DropdownMenuItem(
                                          value: s,
                                          child: Text(s,
                                              style: const TextStyle(
                                                  fontSize: AppTextSize.body)),
                                        ))
                                    .toList(),
                                onChanged: (v) {
                                  if (v != null) setState(() => _state = v);
                                },
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),

                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: _calculate,
                          child: Text(
                            calcLabel,
                            style: const TextStyle(
                                fontSize: AppTextSize.bodyLg,
                                fontWeight: FontWeight.w700),
                          ),
                        ),
                      ),

                      // ── Results ──────────────────────────────────────────────
                      if (_hasCalculated && _result != null) ...[
                        const SizedBox(height: 24),
                        if (shouldGate)
                          _GateCard(
                            es: es,
                            onUnlock: () => _showPaywall(es),
                          )
                        else
                          _buildResults(context, _result!, es),
                      ],

                      const SizedBox(height: 16),
                    ],
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

  Widget _buildResults(BuildContext context, _RetirementResult r, bool es) {
    final heroLabel =
        es ? 'Aportación 401(k) anual' : '401(k) Annual Contribution';
    final heroValue = _fmt(r.contribution);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CalcwiseHeroCard(
          label: heroLabel,
          value: heroValue,
          secondary: r.isMaxed
              ? (es ? 'Máximo IRS alcanzado' : 'IRS max reached')
              : null,
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

        // Core metrics
        Card(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              children: [
                MetricRow(
                  label: es
                      ? 'Ahorro en impuestos federales'
                      : 'Federal Tax Savings',
                  value: _fmt(r.taxSaving),
                  valueColor: AppTheme.success,
                ),
                MetricRow(
                  label: es
                      ? 'Costo neto después de ahorros'
                      : 'Net Cost After Tax Savings',
                  value: _fmt(r.netCost),
                  valueColor: AppTheme.primary,
                ),
                MetricRow(
                  label: es
                      ? 'Cambio mensual en salario neto'
                      : 'Take-Home Change / Month',
                  value:
                      '${r.takeHomeChangeMonthly >= 0 ? '+' : ''}\$${(-r.netCost / 12).abs().toStringAsFixed(0)}',
                  valueColor: r.takeHomeChangeMonthly >= 0
                      ? AppTheme.success
                      : AppTheme.error,
                ),
                MetricRow(
                  label: es ? 'Utilización del límite IRS' : 'IRS Limit Usage',
                  value: '${r.utilizationPct.toStringAsFixed(0)}%',
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),

        // Verdict card
        Container(
          padding: const EdgeInsets.all(AppSpacing.lg),
          decoration: BoxDecoration(
            color: AppTheme.success.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(AppRadius.lg),
            border: Border.all(color: AppTheme.success.withValues(alpha: 0.25)),
          ),
          child: Row(
            children: [
              Icon(Icons.lightbulb_rounded, color: AppTheme.success, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  es
                      ? 'Maximiza si puedes — el match del empleador es dinero gratis'
                      : 'Max out if you can — employer match is free money',
                  style: TextStyle(
                    fontSize: AppTextSize.sm,
                    color: AppTheme.success,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),

        // 30-year projection card
        Container(
          padding: const EdgeInsets.all(AppSpacing.lg),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                AppTheme.primary.withValues(alpha: 0.10),
                AppTheme.primary.withValues(alpha: 0.04),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(AppRadius.lg),
            border: Border.all(color: AppTheme.primary.withValues(alpha: 0.15)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.trending_up_rounded,
                      color: AppTheme.primary, size: 18),
                  const SizedBox(width: 8),
                  Text(
                    es
                        ? 'Proyección a 30 años (7% anual)'
                        : '30-Year Projection at 7% Return',
                    style: TextStyle(
                        fontSize: AppTextSize.md,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.primary),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                _fmtLarge(r.projectedValue30yr),
                style: TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.primary,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                es
                    ? 'Si contribuyes \$${_fmt(r.contribution)}/año durante 30 años al 7%.'
                    : 'If you contribute ${_fmt(r.contribution)}/yr for 30 years at 7%.',
                style: TextStyle(
                  fontSize: AppTextSize.sm,
                  color: AppTheme.labelGray,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Text(
            es
                ? '* Basado en tasas federales IRS 2025. Las proyecciones asumen tasa de retorno constante. No es asesoramiento financiero.'
                : '* Based on IRS 2025 federal rates. Projections assume constant return rate. Not financial advice.',
            style: TextStyle(
              fontSize: AppTextSize.xs,
              color: AppTheme.labelGray,
              fontStyle: FontStyle.italic,
            ),
          ),
        ),
      ],
    );
  }
}

// ─── Small helpers ────────────────────────────────────────────────────────────

class _ToggleChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _ToggleChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: AppDuration.fast,
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: selected
              ? AppTheme.primary
              : AppTheme.primary.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(
            color: selected
                ? AppTheme.primary
                : AppTheme.primary.withValues(alpha: 0.2),
          ),
        ),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              color: selected ? Colors.white : AppTheme.primary,
              fontWeight: FontWeight.w600,
              fontSize: AppTextSize.sm,
            ),
          ),
        ),
      ),
    );
  }
}

class _GateCard extends StatelessWidget {
  final bool es;
  final VoidCallback onUnlock;

  const _GateCard({required this.es, required this.onUnlock});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.xl),
      decoration: BoxDecoration(
        color: AppTheme.primary.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(AppRadius.xl),
        border: Border.all(color: AppTheme.primary.withValues(alpha: 0.2)),
      ),
      child: Column(
        children: [
          Icon(Icons.lock_rounded, color: AppTheme.primary, size: 32),
          const SizedBox(height: 12),
          Text(
            es ? 'Resultados completos' : 'Full 401(k) Analysis',
            style: TextStyle(
                fontSize: AppTextSize.bodyLg,
                fontWeight: FontWeight.w700,
                color: AppTheme.primary),
          ),
          const SizedBox(height: 6),
          Text(
            es
                ? 'Desbloquea proyecciones, ahorro fiscal y análisis detallado.'
                : 'Unlock projections, tax savings, and detailed analysis.',
            textAlign: TextAlign.center,
            style:
                TextStyle(fontSize: AppTextSize.sm, color: AppTheme.labelGray),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: onUnlock,
              child: Text(
                es ? 'Pasar a Premium' : 'Go Premium',
                style: const TextStyle(
                    fontSize: AppTextSize.body, fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
