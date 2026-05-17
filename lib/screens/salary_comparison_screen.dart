import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:calcwise_core/calcwise_core.dart';
import '../main.dart' show isSpanishNotifier, paywallSession;
import '../core/analytics/analytics_service.dart';
import '../core/salary_engine.dart';
import '../core/theme/app_theme.dart';
import '../core/flavor_config.dart';
import '../widgets/app_bar_actions.dart';

// ─── Salary comparison screen ─────────────────────────────────────────────────
// Compares two salary offers side-by-side (US only):
// gross, net annual, net monthly, federal tax, FICA, state tax and difference.

class SalaryComparisonScreen extends StatefulWidget {
  const SalaryComparisonScreen({super.key});

  @override
  State<SalaryComparisonScreen> createState() =>
      _SalaryComparisonScreenState();
}

class _SalaryComparisonScreenState extends State<SalaryComparisonScreen> {
  // ── Controllers ────────────────────────────────────────────────────────────
  final _grossACtrl = TextEditingController(text: '60000');
  final _grossBCtrl = TextEditingController(text: '75000');

  String _stateA = 'TX';
  String _stateB = 'CA';

  SalaryResult? _resultA;
  SalaryResult? _resultB;

  bool _hasCalculated = false;

  @override
  void initState() {
    super.initState();
    analyticsService.logCalculationCompleted(
        params: {'screen': 'salary_comparison_opened'});
    // Calculate with defaults immediately
    WidgetsBinding.instance.addPostFrameCallback((_) => _calculate());
  }

  @override
  void dispose() {
    _grossACtrl.dispose();
    _grossBCtrl.dispose();
    super.dispose();
  }

  void _calculate() {
    final grossA = double.tryParse(
        _grossACtrl.text.replaceAll(',', '').replaceAll(r'$', ''));
    final grossB = double.tryParse(
        _grossBCtrl.text.replaceAll(',', '').replaceAll(r'$', ''));

    if (grossA == null || grossA <= 0 || grossB == null || grossB <= 0) {
      return;
    }

    HapticFeedback.mediumImpact();
    setState(() {
      _resultA = UsSalaryEngine.calculate(grossA, _stateA);
      _resultB = UsSalaryEngine.calculate(grossB, _stateB);
      _hasCalculated = true;
    });
    analyticsService.logCalculationCompleted(params: {
      'gross_a': grossA.round(),
      'gross_b': grossB.round(),
      'state_a': _stateA,
      'state_b': _stateB,
    });
  }

  // ── UI ──────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: isSpanishNotifier,
      builder: (context, useAlt, _) {
        return Scaffold(
          appBar: AppBar(
            title: Text(useAlt ? 'Comparar Salarios' : 'Salary Comparison'),
            leading: const BackButton(),
            actions: const [AppBarActions()],
          ),
          body: Column(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // ── Input cards ──────────────────────────────────────
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: _InputCard(
                              label: useAlt ? 'Oferta A' : 'Offer A',
                              color: AppTheme.primary,
                              grossCtrl: _grossACtrl,
                              selectedState: _stateA,
                              onStateChanged: (v) =>
                                  setState(() => _stateA = v),
                              useAlt: useAlt,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _InputCard(
                              label: useAlt ? 'Oferta B' : 'Offer B',
                              color: AppTheme.accent,
                              grossCtrl: _grossBCtrl,
                              selectedState: _stateB,
                              onStateChanged: (v) =>
                                  setState(() => _stateB = v),
                              useAlt: useAlt,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),

                      // ── Compare button ───────────────────────────────────
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: _calculate,
                          icon: const Icon(Icons.compare_arrows_rounded),
                          label: Text(
                            useAlt ? 'Comparar' : 'Compare',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.primary,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 14),
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
                        const SizedBox(height: 20),
                        _ResultsTable(
                          resultA: _resultA!,
                          resultB: _resultB!,
                          labelA: useAlt ? 'Oferta A' : 'Offer A',
                          labelB: useAlt ? 'Oferta B' : 'Offer B',
                          useAlt: useAlt,
                        ),
                        const SizedBox(height: 16),
                        _WinnerCard(
                          resultA: _resultA!,
                          resultB: _resultB!,
                          useAlt: useAlt,
                        ),
                      ],
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
}

// ── Input card ────────────────────────────────────────────────────────────────

class _InputCard extends StatelessWidget {
  final String label;
  final Color color;
  final TextEditingController grossCtrl;
  final String selectedState;
  final ValueChanged<String> onStateChanged;
  final bool useAlt;

  const _InputCard({
    required this.label,
    required this.color,
    required this.grossCtrl,
    required this.selectedState,
    required this.onStateChanged,
    required this.useAlt,
  });

  @override
  Widget build(BuildContext context) {
    final ct = CalcwiseTheme.of(context);
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
            padding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
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
          const SizedBox(height: 12),

          // Gross salary field
          TextField(
            controller: grossCtrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: false),
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            style: const TextStyle(fontSize: AppTextSize.md),
            decoration: InputDecoration(
              labelText: useAlt ? 'Salario bruto' : 'Gross salary',
              prefixText: r'$',
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
          const SizedBox(height: 10),

          // State dropdown (US only)
          if (FlavorConfig.isUS)
            DropdownButtonFormField<String>(
              value: selectedState,
              isExpanded: true,
              isDense: true,
              decoration: InputDecoration(
                labelText: useAlt ? 'Estado' : 'State',
                isDense: true,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  borderSide: BorderSide(color: ct.cardBorder),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  borderSide: BorderSide(color: ct.cardBorder),
                ),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
              ),
              items: UsSalaryEngine.states
                  .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                  .toList(),
              onChanged: (v) {
                if (v != null) onStateChanged(v);
              },
            ),
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
    final fmt = NumberFormat.currency(
        locale: 'en_US', symbol: r'$', decimalDigits: 0);
    final pctFmt = NumberFormat('0.0#', 'en_US');
    final ct = CalcwiseTheme.of(context);

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
            padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(
              children: [
                Expanded(
                  flex: 3,
                  child: Text(
                    useAlt ? 'Métrica' : 'Metric',
                    style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: AppTextSize.sm),
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
                    useAlt ? 'Delta' : 'Diff',
                    textAlign: TextAlign.right,
                    style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: AppTextSize.sm),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: Column(
              children: [
                _Row(
                  label: useAlt ? 'Salario bruto' : 'Gross salary',
                  valA: fmt.format(resultA.grossAnnual),
                  valB: fmt.format(resultB.grossAnnual),
                  delta: resultB.grossAnnual - resultA.grossAnnual,
                  fmt: fmt,
                  bold: true,
                ),
                const Divider(height: 16),
                _Row(
                  label: useAlt ? 'Impuesto federal' : 'Federal tax',
                  valA: fmt.format(resultA.federalTax),
                  valB: fmt.format(resultB.federalTax),
                  delta: resultB.federalTax - resultA.federalTax,
                  fmt: fmt,
                  invertColors: true,
                ),
                _Row(
                  label: 'FICA (SS + Medicare)',
                  valA: fmt.format(resultA.ficaTax),
                  valB: fmt.format(resultB.ficaTax),
                  delta: resultB.ficaTax - resultA.ficaTax,
                  fmt: fmt,
                  invertColors: true,
                ),
                _Row(
                  label: useAlt ? 'Impuesto estatal' : 'State tax',
                  valA: fmt.format(resultA.stateTax),
                  valB: fmt.format(resultB.stateTax),
                  delta: resultB.stateTax - resultA.stateTax,
                  fmt: fmt,
                  invertColors: true,
                ),
                _Row(
                  label: useAlt ? 'Impuesto total' : 'Total tax',
                  valA: fmt.format(resultA.totalTax),
                  valB: fmt.format(resultB.totalTax),
                  delta: resultB.totalTax - resultA.totalTax,
                  fmt: fmt,
                  invertColors: true,
                ),
                const Divider(height: 16),
                _Row(
                  label: useAlt ? 'Neto anual' : 'Net annual',
                  valA: fmt.format(resultA.netAnnual),
                  valB: fmt.format(resultB.netAnnual),
                  delta: resultB.netAnnual - resultA.netAnnual,
                  fmt: fmt,
                  bold: true,
                ),
                _Row(
                  label: useAlt ? 'Neto mensual' : 'Net monthly',
                  valA: fmt.format(resultA.netMonthly),
                  valB: fmt.format(resultB.netMonthly),
                  delta: resultB.netMonthly - resultA.netMonthly,
                  fmt: fmt,
                  bold: true,
                ),
                const Divider(height: 16),
                _RowPct(
                  label: useAlt ? 'Tasa efectiva' : 'Effective rate',
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
            child: Text(label,
                style: const TextStyle(fontSize: AppTextSize.sm)),
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
    final delta = resultB.netAnnual - resultA.netAnnual;
    final fmt =
        NumberFormat.currency(locale: 'en_US', symbol: r'$', decimalDigits: 0);
    final isTie = delta.abs() < 1;
    final aWins = delta < 0;

    String title;
    Color borderColor;
    if (isTie) {
      title = useAlt ? 'Empate' : 'It\'s a tie!';
      borderColor = AppTheme.warning;
    } else if (aWins) {
      title = useAlt
          ? 'Oferta A — +${fmt.format(delta.abs())} neto/año'
          : 'Offer A — +${fmt.format(delta.abs())} net/year';
      borderColor = AppTheme.primary;
    } else {
      title = useAlt
          ? 'Oferta B — +${fmt.format(delta.abs())} neto/año'
          : 'Offer B — +${fmt.format(delta.abs())} net/year';
      borderColor = AppTheme.accent;
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
            isTie
                ? Icons.balance_rounded
                : Icons.emoji_events_rounded,
            color: borderColor,
            size: 30,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isTie
                      ? (useAlt ? 'Resultado' : 'Result')
                      : (useAlt ? 'Mejor oferta' : 'Best offer'),
                  style: TextStyle(
                    fontSize: AppTextSize.xs,
                    color: AppTheme.labelGray,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  title,
                  style: TextStyle(
                    fontSize: AppTextSize.bodyLg,
                    fontWeight: FontWeight.bold,
                    color: borderColor,
                  ),
                ),
                if (!isTie) ...[
                  const SizedBox(height: 2),
                  Text(
                    useAlt
                        ? '+${fmt.format(delta.abs() / 12)} por mes'
                        : '+${fmt.format(delta.abs() / 12)} per month',
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
