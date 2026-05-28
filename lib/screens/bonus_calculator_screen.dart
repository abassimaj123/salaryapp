import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/flavor_config.dart';
import '../core/salary_engine.dart';
import '../core/theme/app_theme.dart';
import '../main.dart' show isSpanishNotifier, salaryNotifier;
import '../widgets/result_card.dart';
import 'package:calcwise_core/calcwise_core.dart';

// ─── Bonus / Supplemental Pay Calculator (all flavors) ───────────────────────
//
// US:  Flat 22% supplemental federal rate (37% if bonus > $1M) + state rate
//      Aggregate method: tax on (regular paycheck + bonus) minus regular tax
// CA:  Federal + provincial marginal rates applied to bonus amount
// UK:  Bonus added to annual income → recalculate as regular income

// ─── Engine ───────────────────────────────────────────────────────────────────

class BonusResult {
  // Common
  final double bonusAmount;
  final double grossAnnual;

  // US flat-rate method
  final double? usFlatFederalTax;
  final double? usFlatStateTax;
  final double? usFlatTotalTax;
  final double? usFlatNetBonus;

  // US aggregate method
  final double? usAggregateTotalTax;
  final double? usAggregateNetBonus;
  final String? betterMethod; // 'flat' or 'aggregate'

  // CA
  final double? caFederalTax;
  final double? caProvincialTax;
  final double? caTotalTax;
  final double? caNetBonus;

  // UK
  final double? ukExtraTax;
  final double? ukNetBonus;

  const BonusResult({
    required this.bonusAmount,
    required this.grossAnnual,
    this.usFlatFederalTax,
    this.usFlatStateTax,
    this.usFlatTotalTax,
    this.usFlatNetBonus,
    this.usAggregateTotalTax,
    this.usAggregateNetBonus,
    this.betterMethod,
    this.caFederalTax,
    this.caProvincialTax,
    this.caTotalTax,
    this.caNetBonus,
    this.ukExtraTax,
    this.ukNetBonus,
  });
}

class BonusEngine {
  BonusEngine._();

  // ── US ──────────────────────────────────────────────────────────────────────

  /// Supplemental federal rate: 22% up to $1M, 37% above.
  static double usSupplementalFederalRate(double bonus) =>
      bonus > 1000000 ? 0.37 : 0.22;

  /// Flat-rate method: apply supplemental rate directly to bonus.
  static _UsFlatResult usFlatRate(
      double bonus, double annualSalary, String state) {
    final federalRate = usSupplementalFederalRate(bonus);
    final federalTax = bonus * federalRate;
    final stateRate = UsSalaryEngine.stateTax(1.0, state); // rate per $1
    final stateTax = bonus * stateRate;
    final total = federalTax + stateTax;
    return _UsFlatResult(
        federalTax: federalTax, stateTax: stateTax, total: total);
  }

  /// Aggregate method:
  /// Tax on (1 regular paycheck + bonus) minus tax on 1 regular paycheck.
  static _UsAggregateResult usAggregate(
      double bonus, double annualSalary, String state, int payPeriods) {
    final regularPaycheck = annualSalary / payPeriods;
    final annualized = regularPaycheck * payPeriods;
    final annualizedWithBonus = (regularPaycheck + bonus) * payPeriods;

    final taxOnRegular = UsSalaryEngine.federalTax(annualized) +
        UsSalaryEngine.stateTax(annualized, state);
    final taxOnWithBonus = UsSalaryEngine.federalTax(annualizedWithBonus) +
        UsSalaryEngine.stateTax(annualizedWithBonus, state);

    final bonusTax =
        ((taxOnWithBonus - taxOnRegular)).clamp(0.0, double.infinity);
    return _UsAggregateResult(bonusTax: bonusTax);
  }

  static BonusResult calculateUS(
      double bonus, double annualSalary, String state, int payPeriods) {
    final flat = usFlatRate(bonus, annualSalary, state);
    final aggregate = usAggregate(bonus, annualSalary, state, payPeriods);

    // "Better" = lower withholding = more take-home
    final better = flat.total <= aggregate.bonusTax ? 'flat' : 'aggregate';

    return BonusResult(
      bonusAmount: bonus,
      grossAnnual: annualSalary,
      usFlatFederalTax: flat.federalTax,
      usFlatStateTax: flat.stateTax,
      usFlatTotalTax: flat.total,
      usFlatNetBonus: bonus - flat.total,
      usAggregateTotalTax: aggregate.bonusTax,
      usAggregateNetBonus: bonus - aggregate.bonusTax,
      betterMethod: better,
    );
  }

  // ── CA ──────────────────────────────────────────────────────────────────────

  /// CA bonus tax = marginal federal + marginal provincial applied to bonus.
  static BonusResult calculateCA(
      double bonus, double annualSalary, String province) {
    final taxWithout = CaSalaryEngine.federalTax(annualSalary) +
        CaSalaryEngine.provincialTax(annualSalary, province);
    final taxWith = CaSalaryEngine.federalTax(annualSalary + bonus) +
        CaSalaryEngine.provincialTax(annualSalary + bonus, province);

    final totalTax = (taxWith - taxWithout).clamp(0.0, double.infinity);
    // Approximate split
    final fedWithout = CaSalaryEngine.federalTax(annualSalary);
    final fedWith = CaSalaryEngine.federalTax(annualSalary + bonus);
    final fedTax = (fedWith - fedWithout).clamp(0.0, double.infinity);
    final provTax = (totalTax - fedTax).clamp(0.0, double.infinity);

    return BonusResult(
      bonusAmount: bonus,
      grossAnnual: annualSalary,
      caFederalTax: fedTax,
      caProvincialTax: provTax,
      caTotalTax: totalTax,
      caNetBonus: bonus - totalTax,
    );
  }

  // ── UK ──────────────────────────────────────────────────────────────────────

  /// UK: bonus added to annual income; extra tax = marginal.
  static BonusResult calculateUK(double bonus, double annualSalary) {
    final taxWithout = UkSalaryEngine.incomeTax(annualSalary) +
        UkSalaryEngine.nationalInsurance(annualSalary);
    final taxWith = UkSalaryEngine.incomeTax(annualSalary + bonus) +
        UkSalaryEngine.nationalInsurance(annualSalary + bonus);
    final extraTax = (taxWith - taxWithout).clamp(0.0, double.infinity);
    return BonusResult(
      bonusAmount: bonus,
      grossAnnual: annualSalary,
      ukExtraTax: extraTax,
      ukNetBonus: bonus - extraTax,
    );
  }
}

class _UsFlatResult {
  final double federalTax, stateTax, total;
  const _UsFlatResult(
      {required this.federalTax, required this.stateTax, required this.total});
}

class _UsAggregateResult {
  final double bonusTax;
  const _UsAggregateResult({required this.bonusTax});
}

// ─── Screen ───────────────────────────────────────────────────────────────────

class BonusCalculatorScreen extends StatefulWidget {
  const BonusCalculatorScreen({super.key});

  @override
  State<BonusCalculatorScreen> createState() => _BonusCalculatorScreenState();
}

class _BonusCalculatorScreenState extends State<BonusCalculatorScreen> {
  final _formKey = GlobalKey<FormState>();
  final _salaryCtrl = TextEditingController();
  final _bonusCtrl = TextEditingController(text: '5,000');
  final _scrollCtrl = ScrollController();

  String _usState = 'CA';
  String _caProvince = 'ON';
  int _payPeriods = 26; // biweekly default

  BonusResult? _result;

  @override
  void initState() {
    super.initState();
    final salary = salaryNotifier.value;
    _salaryCtrl.text = salary > 0
        ? NumberFormat('#,###').format(salary.round())
        : '75,000';
    // Load saved province for CA flavor
    if (FlavorConfig.isCA) {
      SharedPreferences.getInstance().then((prefs) {
        final saved = prefs.getString('salary_ca_province');
        if (saved != null && mounted) setState(() => _caProvince = saved);
      });
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _calculate();
    });
  }

  @override
  void dispose() {
    _salaryCtrl.dispose();
    _bonusCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  double _parse(TextEditingController c) {
    // Strip all thousand-separator variants (comma, non-breaking space, etc.)
    final raw = c.text.replaceAll(RegExp('[,   ]'), '').replaceAll(RegExp(r'[^\d.]'), '');
    return double.tryParse(raw) ?? 0;
  }

  void _calculate() {
    if (!_formKey.currentState!.validate()) return;
    HapticFeedback.mediumImpact();
    FocusScope.of(context).unfocus();

    final salary = _parse(_salaryCtrl);
    final bonus = _parse(_bonusCtrl);
    if (salary <= 0 || bonus <= 0) return;

    BonusResult res;
    if (FlavorConfig.isUS) {
      res = BonusEngine.calculateUS(bonus, salary, _usState, _payPeriods);
    } else if (FlavorConfig.isCA) {
      res = BonusEngine.calculateCA(bonus, salary, _caProvince);
    } else {
      res = BonusEngine.calculateUK(bonus, salary);
    }

    setState(() => _result = res);
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: isSpanishNotifier,
      builder: (context, useAlt, _) {
        final es = FlavorConfig.isUS && useAlt;
        final fr = FlavorConfig.isCA && useAlt;

        final title = fr
            ? 'Calculateur de prime'
            : (es ? 'Calculadora de bonificación' : 'Bonus Calculator');
        final calcLabel = fr ? 'Calculer' : (es ? 'Calcular' : 'Calculate');

        return Scaffold(
          appBar: AppBar(title: Text(title)),
          body: Column(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  controller: _scrollCtrl,
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _InputCard(
                          salaryCtrl: _salaryCtrl,
                          bonusCtrl: _bonusCtrl,
                          usState: _usState,
                          caProvince: _caProvince,
                          payPeriods: _payPeriods,
                          es: es,
                          fr: fr,
                          onStateChanged: (v) => setState(() => _usState = v!),
                          onProvinceChanged: (v) =>
                              setState(() => _caProvince = v!),
                          onPayPeriodsChanged: (v) =>
                              setState(() => _payPeriods = v),
                        ),
                        const SizedBox(height: AppSpacing.xxl),
                        ElevatedButton(
                          onPressed: _calculate,
                          child: Text(calcLabel,
                              style: const TextStyle(
                                  fontSize: AppTextSize.bodyLg,
                                  fontWeight: FontWeight.w700)),
                        ),
                        if (_result != null) ...[
                          const SizedBox(height: AppSpacing.xxlPlus),
                          _ResultsSection(result: _result!, es: es, fr: fr),
                        ],
                        const SizedBox(height: AppSpacing.lg),
                      ],
                    ),
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

// ─── Input card ───────────────────────────────────────────────────────────────

class _InputCard extends StatelessWidget {
  final TextEditingController salaryCtrl;
  final TextEditingController bonusCtrl;
  final String usState;
  final String caProvince;
  final int payPeriods;
  final bool es, fr;
  final ValueChanged<String?> onStateChanged;
  final ValueChanged<String?> onProvinceChanged;
  final ValueChanged<int> onPayPeriodsChanged;

  const _InputCard({
    required this.salaryCtrl,
    required this.bonusCtrl,
    required this.usState,
    required this.caProvince,
    required this.payPeriods,
    required this.es,
    required this.fr,
    required this.onStateChanged,
    required this.onProvinceChanged,
    required this.onPayPeriodsChanged,
  });

  static const _periodOptions = [52, 26, 24, 12];

  List<String> _periodLabels(bool es, bool fr) => [
        fr ? 'Hebdo (52)' : (es ? 'Semanal (52)' : 'Weekly (52)'),
        fr ? 'Bimensuel (26)' : (es ? 'Quincenal (26)' : 'Bi-weekly (26)'),
        fr ? 'Semi-mens. (24)' : (es ? 'Semi-mens. (24)' : 'Semi-mo. (24)'),
        fr ? 'Mensuel (12)' : (es ? 'Mensual (12)' : 'Monthly (12)'),
      ];

  @override
  Widget build(BuildContext context) {
    final symbol = FlavorConfig.currencySymbol;
    final salaryLabel = fr
        ? 'Salaire annuel brut'
        : (es ? 'Salario anual bruto' : 'Gross Annual Salary');
    final bonusLabel = fr
        ? 'Montant de la prime'
        : (es ? 'Monto de la bonificación' : 'Bonus Amount');
    final reqMsg = fr ? 'Requis' : (es ? 'Requerido' : 'Required');
    final invalidMsg =
        fr ? 'Montant invalide' : (es ? 'Inválido' : 'Invalid amount');

    final periodLabels = _periodLabels(es, fr);

    return Card(
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
                CurrencyInputFormatter(
                    locale: FlavorConfig.isCA
                        ? 'en_CA'
                        : (FlavorConfig.isUK ? 'en_GB' : 'en_US')),
              ],
              decoration: InputDecoration(
                labelText: salaryLabel,
                prefixText: '$symbol ',
                hintText: '75,000',
              ),
              style: const TextStyle(
                  fontSize: AppTextSize.bodyLg, fontWeight: FontWeight.w600),
              validator: (v) {
                if (v == null || v.trim().isEmpty) return reqMsg;
                final val = double.tryParse(
                    v.replaceAll(',', '').replaceAll(RegExp(r'[^\d.]'), ''));
                if (val == null || val <= 0) return invalidMsg;
                return null;
              },
            ),
            const SizedBox(height: AppSpacing.lg),
            TextFormField(
              controller: bonusCtrl,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                CurrencyInputFormatter(
                    locale: FlavorConfig.isCA
                        ? 'en_CA'
                        : (FlavorConfig.isUK ? 'en_GB' : 'en_US')),
              ],
              decoration: InputDecoration(
                labelText: bonusLabel,
                prefixText: '$symbol ',
                hintText: '5,000',
                helperText: FlavorConfig.isUS
                    ? (es
                        ? '22% tasa suplementaria federal (37% si > \$1M)'
                        : '22% federal supplemental rate (37% if > \$1M)')
                    : null,
              ),
              style: const TextStyle(
                  fontSize: AppTextSize.bodyLg, fontWeight: FontWeight.w600),
              validator: (v) {
                if (v == null || v.trim().isEmpty) return reqMsg;
                final val = double.tryParse(
                    v.replaceAll(',', '').replaceAll(RegExp(r'[^\d.]'), ''));
                if (val == null || val <= 0) return invalidMsg;
                return null;
              },
            ),
            if (FlavorConfig.isUS) ...[
              const SizedBox(height: AppSpacing.lg),
              DropdownButtonFormField<String>(
                value: usState,
                decoration: InputDecoration(
                  labelText: es ? 'Estado' : 'State',
                  prefixIcon: const Icon(Icons.location_on_rounded),
                ),
                items: UsSalaryEngine.states
                    .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                    .toList(),
                onChanged: onStateChanged,
              ),
              const SizedBox(height: AppSpacing.lg),
              Text(
                es ? 'Frecuencia de pago' : 'Pay Frequency',
                style: TextStyle(
                    fontSize: AppTextSize.md,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.labelGray),
              ),
              const SizedBox(height: AppSpacing.sm),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: List.generate(_periodOptions.length, (i) {
                  final isSelected = payPeriods == _periodOptions[i];
                  return ChoiceChip(
                    label: Text(periodLabels[i]),
                    selected: isSelected,
                    selectedColor: AppTheme.primary,
                    labelStyle: TextStyle(
                      color: isSelected ? Colors.white : AppTheme.labelGray,
                      fontWeight:
                          isSelected ? FontWeight.w600 : FontWeight.normal,
                      fontSize: AppTextSize.sm,
                    ),
                    onSelected: (_) => onPayPeriodsChanged(_periodOptions[i]),
                  );
                }),
              ),
            ],
            if (FlavorConfig.isCA) ...[
              const SizedBox(height: AppSpacing.lg),
              DropdownButtonFormField<String>(
                value: caProvince,
                decoration: InputDecoration(
                  labelText: fr ? 'Province' : 'Province',
                  prefixIcon: const Icon(Icons.location_on_rounded),
                ),
                items: CaSalaryEngine.provinces
                    .map((p) => DropdownMenuItem(value: p, child: Text(p)))
                    .toList(),
                onChanged: onProvinceChanged,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ─── Results section ──────────────────────────────────────────────────────────

class _ResultsSection extends StatelessWidget {
  final BonusResult result;
  final bool es, fr;

  const _ResultsSection(
      {required this.result, required this.es, required this.fr});

  String _fmt(double v) =>
      AmountFormatter.ui(v, FlavorConfig.currencyCode);

  String _pct(double v) => '${(v * 100).toStringAsFixed(1)}%';

  @override
  Widget build(BuildContext context) {
    if (FlavorConfig.isUS) return _buildUS(context);
    if (FlavorConfig.isCA) return _buildCA(context);
    return _buildUK(context);
  }

  Widget _buildUS(BuildContext context) {
    final r = result;
    final flatBetter = r.betterMethod == 'flat';

    final flatTitle = es ? 'Método tasa fija' : 'Flat Rate Method';
    final aggTitle = es ? 'Método agregado' : 'Aggregate Method';
    final federalLabel =
        es ? 'Impuesto federal suplementario' : 'Supplemental Federal Tax';
    final stateLabel = es ? 'Impuesto estatal' : 'State Tax';
    final totalTaxLabel = es ? 'Total impuesto retenido' : 'Total Tax Withheld';
    final netLabel = es ? 'Pago neto de bonificación' : 'Net Bonus Pay';
    final verdictLabel = es ? '¿Cuál es mejor?' : 'Which is better for you?';
    final flatRate = r.bonusAmount > 1000000 ? '37%' : '22%';
    final flatDesc = es
        ? 'Tasa federal suplementaria: $flatRate + tasa estatal'
        : 'Supplemental federal rate: $flatRate + state rate';
    final aggDesc = es
        ? 'Nómina regular + bono → calcular impuesto diferencial'
        : 'Add bonus to one regular paycheck → marginal tax on combined';

    final verdictMethod = flatBetter
        ? (es ? 'Tasa fija' : 'Flat Rate')
        : (es ? 'Método agregado' : 'Aggregate Method');
    final verdictSavings = (r.usAggregateNetBonus! - r.usFlatNetBonus!).abs();
    final verdictText = flatBetter
        ? (es
            ? 'La tasa fija retiene ${_fmt(verdictSavings)} menos. Usted recibe más ahora.'
            : 'Flat rate withholds ${_fmt(verdictSavings)} less. You take home more now.')
        : (es
            ? 'El método agregado retiene ${_fmt(verdictSavings)} menos. Usted recibe más ahora.'
            : 'Aggregate method withholds ${_fmt(verdictSavings)} less. You take home more now.');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Highlight: net bonus for better method
        ResultCard(
          label: flatBetter
              ? (es
                  ? 'Mejor bono neto (tasa fija)'
                  : 'Best Net Bonus (Flat Rate)')
              : (es
                  ? 'Mejor bono neto (método agregado)'
                  : 'Best Net Bonus (Aggregate)'),
          value: _fmt(flatBetter ? r.usFlatNetBonus! : r.usAggregateNetBonus!),
          icon: Icons.monetization_on_rounded,
          highlight: true,
        ),
        const SizedBox(height: AppSpacing.xl),

        // Side-by-side methods
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _MethodCard(
                title: flatTitle,
                subtitle: flatDesc,
                isBetter: flatBetter,
                rows: [
                  _MRow(federalLabel, _fmt(r.usFlatFederalTax!),
                      CalcwiseSemanticColors.errorDark),
                  _MRow(stateLabel, _fmt(r.usFlatStateTax!),
                      Colors.deepOrangeAccent),
                  _MRow(totalTaxLabel, _fmt(r.usFlatTotalTax!),
                      CalcwiseSemanticColors.errorDark),
                  _MRow(netLabel, _fmt(r.usFlatNetBonus!), AppTheme.success),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.smPlus),
            Expanded(
              child: _MethodCard(
                title: aggTitle,
                subtitle: aggDesc,
                isBetter: !flatBetter,
                rows: [
                  _MRow(totalTaxLabel, _fmt(r.usAggregateTotalTax!),
                      CalcwiseSemanticColors.errorDark),
                  _MRow(
                      netLabel, _fmt(r.usAggregateNetBonus!), AppTheme.success),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.lg),

        // Verdict card
        Container(
          padding: const EdgeInsets.all(AppSpacing.lg),
          decoration: BoxDecoration(
            color: AppTheme.success.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(AppRadius.lg),
            border: Border.all(color: AppTheme.success.withValues(alpha: 0.4)),
          ),
          child: Row(
            children: [
              Icon(Icons.lightbulb_outline, color: AppTheme.success, size: 22),
              const SizedBox(width: AppSpacing.smPlus),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      verdictLabel,
                      style: TextStyle(
                          fontSize: AppTextSize.sm,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.success),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      '${es ? "Recomendado" : "Recommended"}: $verdictMethod',
                      style: TextStyle(
                          fontSize: AppTextSize.body,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.success),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(verdictText,
                        style: TextStyle(
                            fontSize: AppTextSize.sm,
                            color: AppTheme.success.withValues(alpha: 0.85))),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
          child: Text(
            es
                ? '* El método preferido depende de sus preferencias de flujo de caja. Ambos importes anuales son iguales si su tasa marginal real coincide con la tasa suplementaria.'
                : '* The preferred method depends on cash-flow preference. Both yield equal annual tax if your marginal rate equals the supplemental rate.',
            style: TextStyle(
                fontSize: AppTextSize.xs,
                color: AppTheme.labelGray,
                fontStyle: FontStyle.italic),
          ),
        ),
      ],
    );
  }

  Widget _buildCA(BuildContext context) {
    final r = result;
    final federalLabel =
        fr ? 'Impôt fédéral sur la prime' : 'Federal Tax on Bonus';
    final provLabel =
        fr ? 'Impôt provincial sur la prime' : 'Provincial Tax on Bonus';
    final totalLabel = fr ? 'Total retenu sur la prime' : 'Total Tax Withheld';
    final netLabel = fr ? 'Prime nette' : 'Net Bonus Pay';
    final effLabel = fr ? 'Taux effectif' : 'Effective Rate on Bonus';
    final effRate = r.caTotalTax! / r.bonusAmount;
    final caNote = fr
        ? '* Méthode marginale : l\'impôt est calculé sur la prime au taux marginal actuel.'
        : '* Marginal method: bonus is taxed at your current marginal federal + provincial rates.';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ResultCard(
          label: netLabel,
          value: _fmt(r.caNetBonus!),
          icon: Icons.monetization_on_rounded,
          highlight: true,
        ),
        const SizedBox(height: AppSpacing.lg),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              children: [
                MetricRow(
                    label: fr ? 'Prime brute' : 'Gross Bonus',
                    value: _fmt(r.bonusAmount)),
                MetricRow(
                    label: federalLabel,
                    value: _fmt(r.caFederalTax!),
                    valueColor: CalcwiseSemanticColors.errorDark),
                MetricRow(
                    label: provLabel,
                    value: _fmt(r.caProvincialTax!),
                    valueColor: Colors.deepOrangeAccent),
                MetricRow(
                    label: totalLabel,
                    value: _fmt(r.caTotalTax!),
                    valueColor: CalcwiseSemanticColors.errorDark),
                MetricRow(label: effLabel, value: _pct(effRate)),
                MetricRow(
                    label: netLabel,
                    value: _fmt(r.caNetBonus!),
                    valueColor: AppTheme.success),
              ],
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
          child: Text(
            caNote,
            style: TextStyle(
                fontSize: AppTextSize.xs,
                color: AppTheme.labelGray,
                fontStyle: FontStyle.italic),
          ),
        ),
      ],
    );
  }

  Widget _buildUK(BuildContext context) {
    final r = result;
    final taxLabel = 'Tax & NI on Bonus';
    final netLabel = 'Net Bonus Pay';
    final effLabel = 'Effective Rate on Bonus';
    final effRate = r.ukExtraTax! / r.bonusAmount;
    final ukNote =
        '* UK: bonus is treated as regular income — added to annual salary and taxed at your marginal Income Tax + NI rate.';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ResultCard(
          label: netLabel,
          value: _fmt(r.ukNetBonus!),
          icon: Icons.monetization_on_rounded,
          highlight: true,
        ),
        const SizedBox(height: AppSpacing.lg),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              children: [
                MetricRow(label: 'Gross Bonus', value: _fmt(r.bonusAmount)),
                MetricRow(
                    label: taxLabel,
                    value: _fmt(r.ukExtraTax!),
                    valueColor: CalcwiseSemanticColors.errorDark),
                MetricRow(label: effLabel, value: _pct(effRate)),
                MetricRow(
                    label: netLabel,
                    value: _fmt(r.ukNetBonus!),
                    valueColor: AppTheme.success),
              ],
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
          child: Text(
            ukNote,
            style: TextStyle(
                fontSize: AppTextSize.xs,
                color: AppTheme.labelGray,
                fontStyle: FontStyle.italic),
          ),
        ),
      ],
    );
  }
}

// ─── Method comparison card (US) ─────────────────────────────────────────────

class _MRow {
  final String label;
  final String value;
  final Color? color;
  const _MRow(this.label, this.value, [this.color]);
}

class _MethodCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final bool isBetter;
  final List<_MRow> rows;

  const _MethodCard({
    required this.title,
    required this.subtitle,
    required this.isBetter,
    required this.rows,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(
          color: isBetter ? AppTheme.success : AppTheme.divider,
          width: isBetter ? 2 : 1,
        ),
      ),
      child: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md, vertical: AppSpacing.smPlus),
            decoration: BoxDecoration(
              color: isBetter
                  ? AppTheme.success.withValues(alpha: 0.12)
                  : Colors.transparent,
              borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(AppRadius.lg)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (isBetter)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.xs, vertical: AppSpacing.xxs),
                    decoration: BoxDecoration(
                      color: AppTheme.success,
                      borderRadius: BorderRadius.circular(AppRadius.xs),
                    ),
                    child: const Text('BEST',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: AppTextSize.xxs,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.5)),
                  ),
                const SizedBox(height: AppSpacing.xs),
                Text(title,
                    style: const TextStyle(
                        fontSize: AppTextSize.md, fontWeight: FontWeight.w700)),
                const SizedBox(height: AppSpacing.xxs),
                Text(subtitle,
                    style: TextStyle(fontSize: AppTextSize.xs, color: AppTheme.labelGray)),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Column(
              children: rows.map((row) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
                  child: Row(
                    children: [
                      Expanded(
                          child: Text(row.label,
                              style:
                                  const TextStyle(fontSize: AppTextSize.xs))),
                      Text(row.value,
                          style: TextStyle(
                              fontSize: AppTextSize.sm,
                              fontWeight: FontWeight.w600,
                              color: row.color)),
                    ],
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }
}
