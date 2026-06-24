import 'package:flutter/material.dart';
import 'history_screen.dart' show HistoryScreen;
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:calcwise_core/calcwise_core.dart';
import '../main.dart'
    show
        isSpanishNotifier,
        paywallSession,
        salaryNotifier,
        ukStudentLoanNotifier,
        ukScotlandNotifier,
        historyService,
        adService;
import '../core/analytics/analytics_service.dart';
import '../core/salary_engine.dart';
import '../core/data/city_col_data.dart';
import '../core/theme/app_theme.dart';
import '../core/flavor_config.dart';
import '../core/freemium/freemium_service.dart';
import '../core/freemium/iap_service.dart';
import '../widgets/app_bar_actions.dart';
import '../widgets/paywall_hard.dart';
import '../widgets/save_scenario_button.dart';
import '../core/services/pdf_export_service.dart';

// ─── Salary comparison screen ─────────────────────────────────────────────────
// Compares two salary offers side-by-side (US only):
// gross, net annual, net monthly, federal tax, FICA, state tax and difference.

class SalaryComparisonScreen extends StatefulWidget {
  const SalaryComparisonScreen({super.key});

  @override
  State<SalaryComparisonScreen> createState() => _SalaryComparisonScreenState();
}

class _SalaryComparisonScreenState extends State<SalaryComparisonScreen> {
  // ── Controllers ────────────────────────────────────────────────────────────
  final _grossACtrl = TextEditingController(text: '60000');
  final _grossBCtrl = TextEditingController(text: '75000');

  // Region codes are flavor-aware: US states, CA provinces, or '' for UK.
  String _regionA = FlavorConfig.isUS
      ? 'TX'
      : (FlavorConfig.isCA ? 'ON' : '');
  String _regionB = FlavorConfig.isUS
      ? 'CA'
      : (FlavorConfig.isCA ? 'BC' : '');

  SalaryResult? _resultA;
  SalaryResult? _resultB;

  // ── Cost-of-living cities (US flavor only) ───────────────────────────────────
  // COL adjusts each offer's net pay to national-average purchasing power so the
  // two offers can be compared on real spending power, not nominal dollars.
  String _cityA = 'Austin, TX';
  String _cityB = 'San Francisco, CA';

  bool _hasCalculated = false;

  /// Flavor-aware net calculation for one offer.
  SalaryResult _calcOne(double gross, String region) {
    if (FlavorConfig.isUS) return UsSalaryEngine.calculate(gross, region);
    if (FlavorConfig.isCA) return CaSalaryEngine.calculate(gross, region);
    // UK — uses global notifiers for Scotland / student loan.
    return UkSalaryEngine.calculate(
      gross,
      studentLoan: ukStudentLoanNotifier.value,
      scotland: ukScotlandNotifier.value,
    );
  }

  @override
  void initState() {
    super.initState();
    analyticsService.logScreenView('salary_comparison');
    analyticsService.logCalculationCompleted(
        params: {'screen': 'salary_comparison_opened'});
    final salary = salaryNotifier.value;
    if (salary > 0) {
      _grossACtrl.text = salary.toStringAsFixed(0);
    }
    // Calculate with defaults immediately
    WidgetsBinding.instance.addPostFrameCallback((_) => _calculate());
    _grossACtrl.addListener(() { if (mounted) _calculate(); });
    _grossBCtrl.addListener(() { if (mounted) _calculate(); });
  }

  @override
  void dispose() {
    historyService.cancelPendingSave('salaryapp', 'salary_comparison');
    _grossACtrl.dispose();
    _grossBCtrl.dispose();
    super.dispose();
  }

  // ── SmartHistory helpers ──────────────────────────────────────────────────

  double _roundTo(double v, double step) => (v / step).round() * step;

  String _buildHash() {
    final grossA = double.tryParse(
        _grossACtrl.text.replaceAll(RegExp('[,   ]'), '').replaceAll(r'$', '')) ?? 0;
    final grossB = double.tryParse(
        _grossBCtrl.text.replaceAll(RegExp('[,   ]'), '').replaceAll(r'$', '')) ?? 0;
    return ResultHasher.hashMixed({
      'flavor': FlavorConfig.flavor,
      'gross_a': _roundTo(grossA, 1000),
      'gross_b': _roundTo(grossB, 1000),
      'region_a': _regionA,
      'region_b': _regionB,
    });
  }

  Map<String, dynamic> _buildL1() {
    final a = _resultA;
    final b = _resultB;
    if (a == null || b == null) return {};
    return {
      'gross_a': a.grossAnnual,
      'gross_b': b.grossAnnual,
      'net_a': a.netAnnual,
      'net_b': b.netAnnual,
      'region_a': _regionA,
      'region_b': _regionB,
    };
  }

  Map<String, dynamic> _buildL2() {
    final a = _resultA;
    final b = _resultB;
    if (a == null || b == null) return {};
    return {
      'inputs': {
        'gross_a': a.grossAnnual,
        'gross_b': b.grossAnnual,
        'region_a': _regionA,
        'region_b': _regionB,
        'flavor': FlavorConfig.flavor,
      },
      'results': {
        'net_a': a.netAnnual,
        'net_b': b.netAnnual,
        'net_monthly_a': a.netMonthly,
        'net_monthly_b': b.netMonthly,
        'effective_rate_a': a.effectiveRate,
        'effective_rate_b': b.effectiveRate,
        'delta_net': b.netAnnual - a.netAnnual,
      },
    };
  }

  void _scheduleAutoSave() {
    if (_resultA == null || _resultB == null) return;
    historyService.scheduleAutoSave(
      appKey: 'salaryapp',
      screenId: 'salary_comparison',
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
    paywallSession.recordAction().ignore();
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
    if (_resultA == null || _resultB == null) return;
    await historyService.saveScenario(
      appKey: 'salaryapp',
      screenId: 'salary_comparison',
      inputHash: _buildHash(),
      l1: _buildL1(),
      l2: _buildL2(),
      label: label,
    );
    HistoryScreen.refreshNotifier.value++;
    adService.onSave();
    paywallSession.recordAction().ignore();
  }

  void _calculate() {
    final grossA = double.tryParse(
        _grossACtrl.text.replaceAll(RegExp('[,   ]'), '').replaceAll(r'$', ''));
    final grossB = double.tryParse(
        _grossBCtrl.text.replaceAll(RegExp('[,   ]'), '').replaceAll(r'$', ''));

    if (grossA == null || grossA <= 0 || grossB == null || grossB <= 0) {
      return;
    }

    AnalyticsService.instance.maybeLogFirstCalculate();

    HapticFeedback.mediumImpact();
    setState(() {
      _resultA = _calcOne(grossA, _regionA);
      _resultB = _calcOne(grossB, _regionB);
      _hasCalculated = true;
    });
    _scheduleAutoSave();
    adService.onAction();
    analyticsService.logCalculationCompleted(params: {
      'gross_a': grossA.round(),
      'gross_b': grossB.round(),
      'region_a': _regionA,
      'region_b': _regionB,
    });
  }

  Future<void> _exportPdf(bool es, bool fr) async {
    final a = _resultA;
    final b = _resultB;
    if (a == null || b == null) return;
    await PdfExportService.exportSalaryComparison(
      context: context,
      grossA: a.grossAnnual,
      grossB: b.grossAnnual,
      netAnnualA: a.netAnnual,
      netAnnualB: b.netAnnual,
      netMonthlyA: a.netMonthly,
      netMonthlyB: b.netMonthly,
      federalTaxA: a.federalTax,
      federalTaxB: b.federalTax,
      ficaTaxA: a.ficaTax,
      ficaTaxB: b.ficaTax,
      stateTaxA: a.stateTax,
      stateTaxB: b.stateTax,
      totalTaxA: a.totalTax,
      totalTaxB: b.totalTax,
      effectiveRateA: a.effectiveRate,
      effectiveRateB: b.effectiveRate,
      regionA: _regionA,
      regionB: _regionB,
      fr: fr,
      es: es,
    );
    analyticsService.logPdfExported();
  }

  /// Hard paywall for the cost-of-living comparison (US value feature).
  Future<void> _showColPaywall(bool es) async {
    await PaywallHard.show(
      context,
      isSpanish: es,
      priceLabel: IAPService.instance.localizedPrice.value,
      onPurchase: IAPService.instance.buy,
    );
  }

  // ── UI ──────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: isSpanishNotifier,
      builder: (context, useAlt, _) {
        final es = FlavorConfig.isUS && useAlt;
        final fr = FlavorConfig.isCA && useAlt;
        return Scaffold(
          appBar: AppBar(
            title: Text(fr
                ? 'Comparaison de salaires'
                : (es ? 'Comparar Salarios' : 'Salary Comparison')),
            leading: const BackButton(),
            actions: const [AppBarActions()],
          ),
          body: CalcwisePageEntrance(
              child: Column(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(AppSpacing.lg,
                      AppSpacing.md, AppSpacing.lg, AppSpacing.xxxl),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // ── Input cards ──────────────────────────────────────
                      IntrinsicHeight(
                        child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(
                            child: _InputCard(
                              label: fr
                                  ? 'Offre A'
                                  : (es ? 'Oferta A' : 'Offer A'),
                              color: AppTheme.primary,
                              grossCtrl: _grossACtrl,
                              selectedState: _regionA,
                              onStateChanged: (v) =>
                                  setState(() => _regionA = v),
                              selectedCity: _cityA,
                              onCityChanged: (v) =>
                                  setState(() => _cityA = v),
                              useAlt: useAlt,
                            ),
                          ),
                          const SizedBox(width: AppSpacing.md),
                          Expanded(
                            child: _InputCard(
                              label: fr
                                  ? 'Offre B'
                                  : (es ? 'Oferta B' : 'Offer B'),
                              color: AppTheme.accent,
                              grossCtrl: _grossBCtrl,
                              selectedState: _regionB,
                              onStateChanged: (v) =>
                                  setState(() => _regionB = v),
                              selectedCity: _cityB,
                              onCityChanged: (v) =>
                                  setState(() => _cityB = v),
                              useAlt: useAlt,
                            ),
                          ),
                        ],
                      ),
                      ),
                      const SizedBox(height: AppSpacing.lg),

                      // ── Compare button ───────────────────────────────────
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: _calculate,
                          icon: const Icon(Icons.compare_arrows_rounded),
                          label: Text(
                            fr ? 'Comparer' : (es ? 'Comparar' : 'Compare'),
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.primary,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(
                                vertical: AppSpacing.mdPlus),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(AppRadius.lg),
                            ),
                          ),
                        ),
                      ),

                      // ── Results ──────────────────────────────────────────
                      if (_hasCalculated &&
                          _resultA != null &&
                          _resultB != null) ...[
                        const SizedBox(height: AppSpacing.xl),
                        CalcwiseStaggerItem(
                          index: 0,
                          child: _ResultsTable(
                            resultA: _resultA!,
                            resultB: _resultB!,
                            labelA: fr ? 'Offre A' : (es ? 'Oferta A' : 'Offer A'),
                            labelB: fr ? 'Offre B' : (es ? 'Oferta B' : 'Offer B'),
                            useAlt: useAlt,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.lg),
                        CalcwiseStaggerItem(
                          index: 1,
                          child: _WinnerCard(
                            resultA: _resultA!,
                            resultB: _resultB!,
                            useAlt: useAlt,
                          ),
                        ),

                        // ── Save Scenario button ─────────────────────────────
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
                            onPressed: () async {
                              HapticFeedback.mediumImpact();
                              if (!isPremium) {
                                await PdfExportService.showUnlockOrPay(
                                    context, () => _exportPdf(es, fr));
                              } else {
                                await _exportPdf(es, fr);
                              }
                            },
                            icon: Icon(isPremium
                                ? Icons.picture_as_pdf_rounded
                                : Icons.lock_outline_rounded,
                                size: 18),
                            label: Text(pdfLabel),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: AppTheme.primary,
                              minimumSize: const Size(double.infinity, 48),
                              side: BorderSide(
                                  color: AppTheme.primary
                                      .withValues(alpha: 0.4)),
                              shape: RoundedRectangleBorder(
                                  borderRadius:
                                      BorderRadius.circular(AppRadius.lg)),
                              padding: const EdgeInsets.symmetric(
                                  vertical: AppSpacing.md),
                            ),
                          ),
                            );
                          },
                        ),

                        // ── Cost-of-living adjustment (US flavor only) ───────
                        if (FlavorConfig.isUS) ...[
                          const SizedBox(height: AppSpacing.lg),
                          ValueListenableBuilder<bool>(
                            valueListenable:
                                freemiumService.hasFullAccessNotifier,
                            builder: (context, isPremium, _) {
                              if (!isPremium) {
                                return PaywallSoft(
                                  featureTitle: es
                                      ? 'Poder adquisitivo real por ciudad'
                                      : 'Real purchasing power by city',
                                  featureSubtitle: es
                                      ? '\$80k en Austin ≠ \$80k en San Francisco'
                                      : '\$80k in Austin ≠ \$80k in San Francisco',
                                  isSpanish: es,
                                  onUnlock: () => _showColPaywall(es),
                                );
                              }
                              return _ColCard(
                                resultA: _resultA!,
                                resultB: _resultB!,
                                cityA: _cityA,
                                cityB: _cityB,
                                useAlt: useAlt,
                              );
                            },
                          ),
                        ],
                      ],
                    ],
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

// ── Input card ────────────────────────────────────────────────────────────────

class _InputCard extends StatelessWidget {
  final String label;
  final Color color;
  final TextEditingController grossCtrl;
  final String selectedState;
  final ValueChanged<String> onStateChanged;
  final String selectedCity;
  final ValueChanged<String> onCityChanged;
  final bool useAlt;

  const _InputCard({
    required this.label,
    required this.color,
    required this.grossCtrl,
    required this.selectedState,
    required this.onStateChanged,
    required this.selectedCity,
    required this.onCityChanged,
    required this.useAlt,
  });

  @override
  Widget build(BuildContext context) {
    final ct = CalcwiseTheme.of(context);
    final es = FlavorConfig.isUS && useAlt;
    final fr = FlavorConfig.isCA && useAlt;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(AppRadius.xl),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Label chip
          Container(
            padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.smPlus, vertical: AppSpacing.xs),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: AppTextSize.xs,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.md),

          // Gross salary field
          TextField(
            controller: grossCtrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              CurrencyInputFormatter(
                  locale: FlavorConfig.isCA
                      ? 'en_CA'
                      : (FlavorConfig.isUK ? 'en_GB' : 'en_US')),
            ],
            style: const TextStyle(fontSize: AppTextSize.md),
            decoration: InputDecoration(
              labelText: fr
                  ? 'Salaire brut'
                  : (es ? 'Salario bruto' : 'Gross salary'),
              prefixText: '${FlavorConfig.currencySymbol} ',
              isDense: true,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppRadius.md),
                borderSide: BorderSide(color: ct.cardBorder),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppRadius.md),
                borderSide: BorderSide(color: ct.cardBorder),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.smPlus),

          // Region dropdown — US states / CA provinces. UK has no sub-region.
          if (FlavorConfig.isUS || FlavorConfig.isCA)
            DropdownButtonFormField<String>(
              value: selectedState,
              isExpanded: true,
              isDense: true,
              decoration: InputDecoration(
                labelText: FlavorConfig.isCA
                    ? 'Province'
                    : (es ? 'Estado' : 'State'),
                isDense: true,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  borderSide: BorderSide(color: ct.cardBorder),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  borderSide: BorderSide(color: ct.cardBorder),
                ),
              ),
              items: (FlavorConfig.isCA
                      ? CaSalaryEngine.provinces
                      : UsSalaryEngine.states)
                  .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                  .toList(),
              onChanged: (v) {
                if (v != null) onStateChanged(v);
              },
            ),

          // City dropdown — US only. Drives cost-of-living adjustment.
          if (FlavorConfig.isUS) ...[
            const SizedBox(height: AppSpacing.smPlus),
            DropdownButtonFormField<String>(
              value: selectedCity,
              isExpanded: true,
              isDense: true,
              decoration: InputDecoration(
                labelText: es ? 'Ciudad' : 'City',
                isDense: true,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  borderSide: BorderSide(color: ct.cardBorder),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  borderSide: BorderSide(color: ct.cardBorder),
                ),
              ),
              items: CityColData.allCities
                  .map((c) => DropdownMenuItem(
                        value: c,
                        child: Text(c,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: AppTextSize.sm)),
                      ))
                  .toList(),
              onChanged: (v) {
                if (v != null) onCityChanged(v);
              },
            ),
          ],
        ],
      ),
    );
  }
}

// ── Results table ─────────────────────────────────────────────────────────────

class _ResultsTable extends StatelessWidget {
  final SalaryResult resultA;
  final SalaryResult resultB;
  final String labelA;
  final String labelB;
  final bool useAlt;

  const _ResultsTable({
    required this.resultA,
    required this.resultB,
    required this.labelA,
    required this.labelB,
    required this.useAlt,
  });

  @override
  Widget build(BuildContext context) {
    final es = FlavorConfig.isUS && useAlt;
    final fr = FlavorConfig.isCA && useAlt;
    final fmt = NumberFormat.currency(
        locale: FlavorConfig.locale,
        symbol: FlavorConfig.currencySymbol,
        decimalDigits: 0);
    final pctFmt = NumberFormat('0.0#', FlavorConfig.locale);
    final ct = CalcwiseTheme.of(context);

    // Flavor-aware deduction labels.
    final federalLabel = FlavorConfig.isUK
        ? 'Income tax'
        : (fr ? 'Impôt fédéral' : (es ? 'Impuesto federal' : 'Federal tax'));
    final ficaLabel = FlavorConfig.isUS
        ? 'FICA (SS + Medicare)'
        : (FlavorConfig.isUK
            ? 'National Insurance'
            : (fr ? 'RPC + AE' : 'CPP + EI'));
    final stateLabel = FlavorConfig.isUS
        ? (es ? 'Impuesto estatal' : 'State tax')
        : (fr ? 'Impôt provincial' : 'Provincial tax');

    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(AppRadius.xl),
        border: Border.all(color: ct.cardBorder),
      ),
      child: Column(
        children: [
          // ── Table header ─────────────────────────────────────────────
          Container(
            decoration: BoxDecoration(
              color: AppTheme.primary.withValues(alpha: 0.1),
              borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(AppRadius.xl)),
            ),
            padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.lg, vertical: AppSpacing.smPlus),
            child: Row(
              children: [
                Expanded(
                  flex: 3,
                  child: Text(
                    fr ? 'Métrique' : (es ? 'Métrica' : 'Metric'),
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: AppTextSize.sm),
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: Text(
                    labelA,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        color: AppTheme.primary,
                        fontWeight: FontWeight.bold,
                        fontSize: AppTextSize.sm),
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: Text(
                    labelB,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        color: AppTheme.accent,
                        fontWeight: FontWeight.bold,
                        fontSize: AppTextSize.sm),
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: Text(
                    fr ? 'Écart' : (es ? 'Delta' : 'Diff'),
                    textAlign: TextAlign.right,
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: AppTextSize.sm),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg, AppSpacing.sm, AppSpacing.lg, AppSpacing.md),
            child: Column(
              children: [
                _Row(
                  label: fr
                      ? 'Salaire brut'
                      : (es ? 'Salario bruto' : 'Gross salary'),
                  valA: fmt.format(resultA.grossAnnual),
                  valB: fmt.format(resultB.grossAnnual),
                  delta: resultB.grossAnnual - resultA.grossAnnual,
                  fmt: fmt,
                  bold: true,
                ),
                const Divider(height: 16),
                _Row(
                  label: federalLabel,
                  valA: fmt.format(resultA.federalTax),
                  valB: fmt.format(resultB.federalTax),
                  delta: resultB.federalTax - resultA.federalTax,
                  fmt: fmt,
                  invertColors: true,
                ),
                _Row(
                  label: ficaLabel,
                  valA: fmt.format(resultA.ficaTax),
                  valB: fmt.format(resultB.ficaTax),
                  delta: resultB.ficaTax - resultA.ficaTax,
                  fmt: fmt,
                  invertColors: true,
                ),
                if (!FlavorConfig.isUK)
                  _Row(
                    label: stateLabel,
                    valA: fmt.format(resultA.stateTax),
                    valB: fmt.format(resultB.stateTax),
                    delta: resultB.stateTax - resultA.stateTax,
                    fmt: fmt,
                    invertColors: true,
                  ),
                _Row(
                  label: fr
                      ? 'Total impôts'
                      : (es ? 'Impuesto total' : 'Total tax'),
                  valA: fmt.format(resultA.totalTax),
                  valB: fmt.format(resultB.totalTax),
                  delta: resultB.totalTax - resultA.totalTax,
                  fmt: fmt,
                  invertColors: true,
                ),
                const Divider(height: 16),
                _Row(
                  label: fr
                      ? 'Net annuel'
                      : (es ? 'Neto anual' : 'Net annual'),
                  valA: fmt.format(resultA.netAnnual),
                  valB: fmt.format(resultB.netAnnual),
                  delta: resultB.netAnnual - resultA.netAnnual,
                  fmt: fmt,
                  bold: true,
                ),
                _Row(
                  label: fr
                      ? 'Net mensuel'
                      : (es ? 'Neto mensual' : 'Net monthly'),
                  valA: fmt.format(resultA.netMonthly),
                  valB: fmt.format(resultB.netMonthly),
                  delta: resultB.netMonthly - resultA.netMonthly,
                  fmt: fmt,
                  bold: true,
                ),
                const Divider(height: 16),
                _RowPct(
                  label: fr
                      ? 'Taux effectif'
                      : (es ? 'Tasa efectiva' : 'Effective rate'),
                  valA: '${pctFmt.format(resultA.effectiveRate)}%',
                  valB: '${pctFmt.format(resultB.effectiveRate)}%',
                  delta: resultB.effectiveRate - resultA.effectiveRate,
                  pctFmt: pctFmt,
                  invertColors: true,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Table row — monetary ──────────────────────────────────────────────────────

class _Row extends StatelessWidget {
  final String label;
  final String valA;
  final String valB;
  final double delta;
  final NumberFormat fmt;
  final bool bold;
  final bool invertColors;

  const _Row({
    required this.label,
    required this.valA,
    required this.valB,
    required this.delta,
    required this.fmt,
    this.bold = false,
    this.invertColors = false,
  });

  @override
  Widget build(BuildContext context) {
    final positive = invertColors ? delta <= 0 : delta >= 0;
    final deltaColor = delta == 0
        ? null
        : positive
            ? AppTheme.success
            : AppTheme.error;
    final sign = delta >= 0 ? '+' : '−';
    final deltaStr = '$sign${fmt.format(delta.abs())}';

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: Text(
              label,
              style: TextStyle(
                fontSize: AppTextSize.sm,
                fontWeight: bold ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              valA,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: AppTextSize.sm,
                fontWeight: bold ? FontWeight.bold : FontWeight.w500,
                color: AppTheme.primary,
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              valB,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: AppTextSize.sm,
                fontWeight: bold ? FontWeight.bold : FontWeight.w500,
                color: AppTheme.accent,
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              deltaStr,
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: AppTextSize.sm,
                fontWeight: bold ? FontWeight.bold : FontWeight.w500,
                color: deltaColor,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Table row — percentage ────────────────────────────────────────────────────

class _RowPct extends StatelessWidget {
  final String label;
  final String valA;
  final String valB;
  final double delta;
  final NumberFormat pctFmt;
  final bool invertColors;

  const _RowPct({
    required this.label,
    required this.valA,
    required this.valB,
    required this.delta,
    required this.pctFmt,
    this.invertColors = false,
  });

  @override
  Widget build(BuildContext context) {
    final positive = invertColors ? delta <= 0 : delta >= 0;
    final deltaColor = delta == 0
        ? null
        : positive
            ? AppTheme.success
            : AppTheme.error;
    final sign = delta >= 0 ? '+' : '−';
    final deltaStr = '$sign${pctFmt.format(delta.abs())}pp';

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child:
                Text(label, style: const TextStyle(fontSize: AppTextSize.sm)),
          ),
          Expanded(
            flex: 2,
            child: Text(
              valA,
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: AppTextSize.sm,
                  fontWeight: FontWeight.w500,
                  color: AppTheme.primary),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              valB,
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: AppTextSize.sm,
                  fontWeight: FontWeight.w500,
                  color: AppTheme.accent),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              deltaStr,
              textAlign: TextAlign.right,
              style: TextStyle(
                  fontSize: AppTextSize.sm,
                  fontWeight: FontWeight.w500,
                  color: deltaColor),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Winner card ───────────────────────────────────────────────────────────────

class _WinnerCard extends StatelessWidget {
  final SalaryResult resultA;
  final SalaryResult resultB;
  final bool useAlt;

  const _WinnerCard({
    required this.resultA,
    required this.resultB,
    required this.useAlt,
  });

  @override
  Widget build(BuildContext context) {
    final es = FlavorConfig.isUS && useAlt;
    final fr = FlavorConfig.isCA && useAlt;
    final delta = resultB.netAnnual - resultA.netAnnual;
    final fmt = NumberFormat.currency(
        locale: FlavorConfig.locale,
        symbol: FlavorConfig.currencySymbol,
        decimalDigits: 0);
    final isTie = delta.abs() < 1;
    final aWins = delta < 0;
    final amt = fmt.format(delta.abs());

    String title;
    Color borderColor;
    if (isTie) {
      title = fr ? 'Égalité !' : (es ? 'Empate' : 'It\'s a tie!');
      borderColor = AppTheme.warning;
    } else {
      final offer = aWins ? 'A' : 'B';
      final offerLabel = fr ? 'Offre' : (es ? 'Oferta' : 'Offer');
      title = fr
          ? '$offerLabel $offer — +$amt net/an'
          : (es
              ? '$offerLabel $offer — +$amt neto/año'
              : '$offerLabel $offer — +$amt net/year');
      borderColor = AppTheme.success;
    }

    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: borderColor.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppRadius.xl),
        border: Border.all(color: borderColor.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          Icon(
            isTie ? Icons.balance_rounded : Icons.emoji_events_rounded,
            color: borderColor,
            size: 30,
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isTie
                      ? (fr
                          ? 'Résultat'
                          : (es ? 'Resultado' : 'Result'))
                      : (fr
                          ? 'Meilleure offre'
                          : (es ? 'Mejor oferta' : 'Best offer')),
                  style: TextStyle(
                    fontSize: AppTextSize.xs,
                    color: AppTheme.labelGray,
                  ),
                ),
                const SizedBox(height: AppSpacing.xxs),
                Text(
                  title,
                  style: TextStyle(
                    fontSize: AppTextSize.bodyLg,
                    fontWeight: FontWeight.bold,
                    color: borderColor,
                  ),
                ),
                if (!isTie) ...[
                  const SizedBox(height: AppSpacing.xxs),
                  Text(
                    fr
                        ? '+${fmt.format(delta.abs() / 12)} par mois'
                        : (es
                            ? '+${fmt.format(delta.abs() / 12)} por mes'
                            : '+${fmt.format(delta.abs() / 12)} per month'),
                    style: TextStyle(
                      fontSize: AppTextSize.sm,
                      color: AppTheme.labelGray,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Cost-of-living card (US only, premium) ────────────────────────────────────
//
// COL adjustment normalizes each offer's net pay to national-average purchasing
// power (index 100):
//     colAdjustedNet = netAnnual / (cityIndex / 100)
// A high-cost city (index > 100) shrinks real value; a low-cost city (< 100)
// boosts it. The two adjusted figures are directly comparable on real spending
// power regardless of where each offer is located.

class _ColCard extends StatelessWidget {
  final SalaryResult resultA;
  final SalaryResult resultB;
  final String cityA;
  final String cityB;
  final bool useAlt;

  const _ColCard({
    required this.resultA,
    required this.resultB,
    required this.cityA,
    required this.cityB,
    required this.useAlt,
  });

  @override
  Widget build(BuildContext context) {
    final es = FlavorConfig.isUS && useAlt;
    final fmt = NumberFormat.currency(
        locale: FlavorConfig.locale,
        symbol: FlavorConfig.currencySymbol,
        decimalDigits: 0);
    final ct = CalcwiseTheme.of(context);

    final idxA = CityColData.indexFor(cityA);
    final idxB = CityColData.indexFor(cityB);

    // Adjust each net to national-average (index 100) purchasing power.
    final adjA = resultA.netAnnual / (idxA / 100);
    final adjB = resultB.netAnnual / (idxB / 100);

    final realDelta = adjB - adjA;
    final realTie = realDelta.abs() < 1;
    final realAWins = realDelta < 0;

    // Nominal winner (for the "flips" insight line).
    final nomDelta = resultB.netAnnual - resultA.netAnnual;
    final nomAWins = nomDelta < 0;
    final flips = !realTie && (realAWins != nomAWins);

    String winnerLabel;
    if (realTie) {
      winnerLabel = es ? 'Empate en poder adquisitivo' : 'Equal purchasing power';
    } else {
      final offer = realAWins ? 'A' : 'B';
      final amt = fmt.format(realDelta.abs());
      winnerLabel = es
          ? 'Oferta $offer gana en poder real (+$amt)'
          : 'Offer $offer wins on real value (+$amt)';
    }

    // Explanatory line: what offer A's net is worth in offer B's city.
    // e.g. "$80k in Austin ≈ $X in San Francisco in purchasing power".
    final equivInB = resultA.netAnnual * (idxB / idxA);

    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(AppRadius.xl),
        border: Border.all(color: AppTheme.accent.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg, AppSpacing.mdPlus, AppSpacing.lg, AppSpacing.sm),
            child: Row(
              children: [
                Icon(Icons.public_rounded,
                    color: AppTheme.accent, size: 18),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    es
                        ? 'Poder adquisitivo real (costo de vida)'
                        : 'Real Purchasing Power (cost of living)',
                    style: const TextStyle(
                        fontSize: AppTextSize.md, fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg, AppSpacing.sm, AppSpacing.lg, AppSpacing.md),
            child: Column(
              children: [
                // Nominal net row (already shown above, repeated for contrast).
                _ColRow(
                  label: es ? 'Neto nominal' : 'Nominal net',
                  cityA: cityA,
                  cityB: cityB,
                  valA: fmt.format(resultA.netAnnual),
                  valB: fmt.format(resultB.netAnnual),
                ),
                const SizedBox(height: AppSpacing.xs),
                // COL-adjusted row.
                _ColRow(
                  label: es ? 'Neto ajustado por COL' : 'COL-adjusted net',
                  cityA: '${es ? "índice" : "index"} ${idxA.toStringAsFixed(0)}',
                  cityB: '${es ? "índice" : "index"} ${idxB.toStringAsFixed(0)}',
                  valA: fmt.format(adjA),
                  valB: fmt.format(adjB),
                  bold: true,
                ),
                const SizedBox(height: AppSpacing.md),
                // Winner banner
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(AppSpacing.md),
                  decoration: BoxDecoration(
                    color: AppTheme.accent.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(AppRadius.lg),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        winnerLabel,
                        style: TextStyle(
                          fontSize: AppTextSize.sm,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.accent,
                        ),
                      ),
                      if (flips) ...[
                        const SizedBox(height: AppSpacing.xxs),
                        Text(
                          es
                              ? 'El ganador cambia tras ajustar por costo de vida.'
                              : 'The winner flips once cost of living is applied.',
                          style: TextStyle(
                            fontSize: AppTextSize.xs,
                            color: AppTheme.labelGray,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                // Explanatory equivalence line.
                Text(
                  es
                      ? '${fmt.format(resultA.netAnnual)} en $cityA ≈ ${fmt.format(equivInB)} en $cityB en poder adquisitivo.'
                      : '${fmt.format(resultA.netAnnual)} in $cityA ≈ ${fmt.format(equivInB)} in $cityB in purchasing power.',
                  style: TextStyle(
                    fontSize: AppTextSize.xs,
                    color: AppTheme.labelGray,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── COL comparison row ────────────────────────────────────────────────────────

class _ColRow extends StatelessWidget {
  final String label;
  final String cityA;
  final String cityB;
  final String valA;
  final String valB;
  final bool bold;

  const _ColRow({
    required this.label,
    required this.cityA,
    required this.cityB,
    required this.valA,
    required this.valB,
    this.bold = false,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          flex: 3,
          child: Text(
            label,
            style: TextStyle(
              fontSize: AppTextSize.sm,
              fontWeight: bold ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        ),
        Expanded(
          flex: 3,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Text(
                valA,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: AppTextSize.sm,
                  fontWeight: bold ? FontWeight.bold : FontWeight.w500,
                  color: AppTheme.primary,
                ),
              ),
              Text(
                cityA,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: AppTextSize.xs, color: AppTheme.labelGray),
              ),
            ],
          ),
        ),
        Expanded(
          flex: 3,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Text(
                valB,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: AppTextSize.sm,
                  fontWeight: bold ? FontWeight.bold : FontWeight.w500,
                  color: AppTheme.accent,
                ),
              ),
              Text(
                cityB,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: AppTextSize.xs, color: AppTheme.labelGray),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
