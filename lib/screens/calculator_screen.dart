import '../core/ads/ad_footer.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:calcwise_core/calcwise_core.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../core/analytics/analytics_service.dart';
import '../core/flavor_config.dart';
import '../core/salary_engine.dart';
import '../core/db/database_service.dart';
import '../core/ads/ad_service.dart';
import '../core/freemium/freemium_service.dart';
import '../main.dart' show paywallSession;
import '../core/theme/app_theme.dart';
import '../widgets/paywall_soft.dart';
import '../widgets/paywall_hard.dart';
import '../l10n/strings_en.dart';
import '../l10n/strings_es.dart';
import '../l10n/strings_fr.dart';
import '../widgets/premium_cta_widget.dart';
import '../widgets/result_card.dart';
import '../widgets/insight_card.dart';
import '../core/insight_engine.dart';
import '../main.dart' show isSpanishNotifier;
import '../core/services/review_service.dart';
import 'raise_screen.dart';
import 'tax_breakdown_screen.dart';
import 'w4_wizard_screen.dart';
import 'bonus_calculator_screen.dart';

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
      case PayFrequency.annual:   return amount;
      case PayFrequency.monthly:  return amount * 12;
      case PayFrequency.biWeekly: return amount * 26;
      case PayFrequency.weekly:   return amount * 52;
      case PayFrequency.hourly:   return amount * 40 * 52;
    }
  }
}

// ─── Screen ───────────────────────────────────────────────────────────────────

class CalculatorScreen extends StatefulWidget {
  const CalculatorScreen({super.key});
  @override
  State<CalculatorScreen> createState() => _CalculatorScreenState();
}

class _CalculatorScreenState extends State<CalculatorScreen>
    with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _salaryCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();

  PayFrequency _frequency = PayFrequency.annual;
  String _usState = 'CA';
  String _caProvince = 'ON';
  SalaryResult? _result;
  bool _showResults = false;

  late AnimationController _animCtrl;
  late Animation<Offset> _slideAnim;
  late Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 450));
    _slideAnim = Tween<Offset>(
            begin: const Offset(0, 0.12), end: Offset.zero)
        .animate(CurvedAnimation(parent: _animCtrl, curve: Curves.easeOut));
    _fadeAnim = CurvedAnimation(parent: _animCtrl, curve: Curves.easeIn);
  }

  @override
  void dispose() {
    _salaryCtrl.dispose();
    _scrollCtrl.dispose();
    _animCtrl.dispose();
    super.dispose();
  }

  // ── Actions ──────────────────────────────────────────────────────────────

  void _calculate() {
    if (!_formKey.currentState!.validate()) return;
    HapticFeedback.mediumImpact();
    FocusScope.of(context).unfocus();

    final rawText = _salaryCtrl.text;
    final raw = (rawText.contains('.') && rawText.contains(','))
        ? rawText.replaceAll(',', '')
        : rawText.replaceAll(',', '.');
    final input = double.tryParse(raw.replaceAll(RegExp(r'[^\d.]'), '')) ?? 0;
    final grossAnnual = _frequency.toAnnual(input);

    if (grossAnnual <= 0) return;

    SalaryResult res;
    if (FlavorConfig.isUS) {
      res = UsSalaryEngine.calculate(grossAnnual, _usState);
    } else if (FlavorConfig.isUK) {
      res = UkSalaryEngine.calculate(grossAnnual);
    } else {
      res = CaSalaryEngine.calculate(grossAnnual, _caProvince);
    }

    setState(() {
      _result = res;
      _showResults = true;
    });

    _animCtrl
      ..reset()
      ..forward();

    // Persist to history (respects freemium limit)
    _saveToHistory(res);

    // Log analytics calculation event
    analyticsService.logCalculation(
      grossSalary: res.grossAnnual,
      netSalary: res.netAnnual,
      frequency: _frequency.name,
    );

    // Maybe show interstitial
    AdService.instance.onCalculation();

    // Maybe show paywall
    _checkPaywall();

    // Scroll to results after next frame
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 400),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _checkPaywall() async {
    final type = await paywallSession.recordAction();
    if (!mounted) return;
    if (type == PaywallTrigger.hard) {
      await PaywallHard.show(context);
    } else if (type == PaywallTrigger.soft) {
      await PaywallSoft.show(context);
    }
  }

  Future<void> _saveToHistory(SalaryResult res) async {
    final currentCount = await DatabaseService.instance.count();
    if (currentCount >= freemiumService.historyLimit) return;
    final region = FlavorConfig.isUS
        ? _usState
        : (FlavorConfig.isCA ? _caProvince : '');
    await DatabaseService.instance.insert(HistoryEntry(
      flavor: FlavorConfig.flavor,
      region: region,
      timestamp: DateTime.now(),
      result: res,
    ));
    try { analyticsService.logSave(); } catch (_) {}
    await ReviewService.instance.requestAfterSave();
  }

  void _reset() {
    setState(() {
      _salaryCtrl.clear();
      _result = null;
      _showResults = false;
      _frequency = PayFrequency.annual;
    });
    _animCtrl.reset();
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: isSpanishNotifier,
      builder: (context, useAlt, _) {
        final es = FlavorConfig.isUS && useAlt;
        final fr = FlavorConfig.isCA && useAlt;

        String calcLabel, resetLabel, resultsLabel;
        if (fr) {
          calcLabel    = AppStringsFR.calculate;
          resetLabel   = AppStringsFR.reset;
          resultsLabel = AppStringsFR.results;
        } else if (es) {
          calcLabel    = AppStringsES.calculate;
          resetLabel   = AppStringsES.reset;
          resultsLabel = AppStringsES.results;
        } else {
          calcLabel    = AppStringsEN.calculate;
          resetLabel   = AppStringsEN.reset;
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
                icon: Icon(Icons.trending_up_rounded),
                tooltip: es
                    ? 'Calculadora de aumento'
                    : (fr ? 'Augmentation' : 'Raise Calculator'),
                onPressed: () => Navigator.push(
                  context,
                  PageRouteBuilder(
                    pageBuilder: (_, __, ___) => RaiseScreen(
                      initialSalary: _result?.grossAnnual,),
                    transitionsBuilder: (_, anim, __, child) =>
                        FadeTransition(opacity: anim, child: child),
                    transitionDuration: const Duration(milliseconds: 250),
                  ),
                ),
              ),
              IconButton(
                icon: Icon(Icons.pie_chart_outline),
                tooltip: es
                    ? 'Tramos del impuesto'
                    : (fr ? 'Tranches d\'imposition' : 'Tax Bracket Breakdown'),
                onPressed: () => Navigator.push(
                  context,
                  PageRouteBuilder(
                    pageBuilder: (_, __, ___) => TaxBreakdownScreen(
                      initialSalary: _result?.grossAnnual,),
                    transitionsBuilder: (_, anim, __, child) =>
                        FadeTransition(opacity: anim, child: child),
                    transitionDuration: const Duration(milliseconds: 250),
                  ),
                ),
              ),
              // Bonus Calculator — all flavors
              IconButton(
                icon: const Icon(Icons.card_giftcard_outlined),
                tooltip: es
                    ? 'Calculadora de bonificación'
                    : (fr ? 'Calculateur de prime' : 'Bonus Calculator'),
                onPressed: () => Navigator.push(
                  context,
                  PageRouteBuilder(
                    pageBuilder: (_, __, ___) =>
                        const BonusCalculatorScreen(),
                    transitionsBuilder: (_, anim, __, child) =>
                        FadeTransition(opacity: anim, child: child),
                    transitionDuration: const Duration(milliseconds: 250),
                  ),
                ),
              ),
              // W-4 Wizard — US flavor only
              if (FlavorConfig.isUS)
                IconButton(
                  icon: const Icon(Icons.assignment_outlined),
                  tooltip: es ? 'Asistente W-4' : 'W-4 Withholding Wizard',
                  onPressed: () => Navigator.push(
                    context,
                    PageRouteBuilder(
                      pageBuilder: (_, __, ___) => const W4WizardScreen(),
                      transitionsBuilder: (_, anim, __, child) =>
                          FadeTransition(opacity: anim, child: child),
                      transitionDuration: const Duration(milliseconds: 250),
                    ),
                  ),
                ),
              if (_showResults)
                IconButton(
                  icon: Icon(Icons.refresh),
                  tooltip: resetLabel,
                  onPressed: _reset,
                ),
            ],
          ),
          body: Column(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  controller: _scrollCtrl,
                  padding: const EdgeInsets.all(16),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 600),
                      child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        CalcwiseStaggerItem(
                          index: 0,
                          child: _SalaryInputCard(
                          controller: _salaryCtrl,
                          frequency: _frequency,
                          useAlt: useAlt,
                          es: es,
                          fr: fr,
                        )),
                        SizedBox(height: 16),
                        CalcwiseStaggerItem(
                          index: 1,
                          child: Column(children: [
                        _FrequencyChips(
                          selected: _frequency,
                          useAlt: useAlt,
                          onChanged: (f) => setState(() => _frequency = f),
                        ),
                        if (FlavorConfig.isUS) ...[
                          SizedBox(height: 16),
                          _StateDropdown(
                            value: _usState,
                            useAlt: useAlt,
                            onChanged: (v) => setState(() => _usState = v!),
                          ),
                        ],
                        if (FlavorConfig.isCA) ...[
                          SizedBox(height: 16),
                          _ProvinceDropdown(
                            value: _caProvince,
                            useAlt: useAlt,
                            onChanged: (v) =>
                                setState(() => _caProvince = v!),
                          ),
                        ],
                          ])),
                        SizedBox(height: 24),
                        CalcwiseStaggerItem(
                          index: 2,
                          child: ElevatedButton(
                          onPressed: _calculate,
                          child: Text(calcLabel,
                              style: TextStyle(
                                  fontSize: 16, fontWeight: FontWeight.w700)),
                        )),
                        if (_showResults && _result != null) ...[
                          SizedBox(height: 28),
                          SlideTransition(
                            position: _slideAnim,
                            child: FadeTransition(
                              opacity: _fadeAnim,
                              child: _ResultsSection(
                                result: _result!,
                                label: resultsLabel,
                                useAlt: useAlt,
                                es: es,
                                fr: fr,
                              ),
                            ),
                          ),
                        ],
                        SizedBox(height: 16),
                      ],
                    ),
                  ),
                    ),
                  ),
                ),
              ),
              const AdFooter(),
            ],
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
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(
            _hintLabel,
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(color: AppTheme.primary),
          ),
          SizedBox(height: 12),
          TextFormField(
            controller: controller,
            keyboardType:
                const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[\d.,]')),
            ],
            decoration: InputDecoration(
              prefixText: '${FlavorConfig.currencySymbol} ',
              prefixStyle: TextStyle(
                  fontSize: 18, fontWeight: FontWeight.w600),
              labelText: _fieldLabel,
              hintText: '0.00',
            ),
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            validator: (v) {
              if (v == null || v.trim().isEmpty) {
                return fr
                    ? 'Veuillez entrer un montant'
                    : (es ? 'Ingrese un monto' : 'Please enter an amount');
              }
              final normalized = (v.contains('.') && v.contains(','))
                  ? v.replaceAll(',', '')
                  : v.replaceAll(',', '.');
              final val = double.tryParse(normalized);
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
    return Wrap(
      spacing: 8,
      runSpacing: 6,
      children: PayFrequency.values.map((f) {
        final isSelected = f == selected;
        return ChoiceChip(
          label: Text(f.label(useAlt)),
          selected: isSelected,
          selectedColor: AppTheme.primary,
          labelStyle: TextStyle(
            color: isSelected ? Colors.white : AppTheme.labelGray,
            fontWeight:
                isSelected ? FontWeight.w600 : FontWeight.normal,
          ),
          onSelected: (_) => onChanged(f),
        );
      }).toList(),
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
        prefixIcon: Icon(Icons.location_on_outlined),
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
        prefixIcon: Icon(Icons.location_on_outlined),
      ),
      items: CaSalaryEngine.provinces
          .map((p) => DropdownMenuItem(value: p, child: Text(p)))
          .toList(),
      onChanged: onChanged,
    );
  }
}

// ─── Results section ──────────────────────────────────────────────────────────

class _ResultsSection extends StatelessWidget {
  final SalaryResult result;
  final String label;
  final bool useAlt, es, fr;

  const _ResultsSection({
    required this.result,
    required this.label,
    required this.useAlt,
    required this.es,
    required this.fr,
  });

  String _fmt(double v) {
    final symbol = FlavorConfig.currencySymbol;
    final f = NumberFormat.currency(
      symbol: symbol,
      decimalDigits: 2,
    );
    return f.format(v);
  }

  String _pct(double v) => '${v.toStringAsFixed(1)}%';

  @override
  Widget build(BuildContext context) {
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
    final effectiveLabel = fr
        ? 'Taux effectif'
        : (es ? 'Tasa efectiva' : 'Effective Tax Rate');

    final federalLabel = FlavorConfig.isUK
        ? (fr ? 'Impôt sur le revenu' : 'Income Tax')
        : (fr ? 'Impôt fédéral' : (es ? 'Impuesto federal' : 'Federal Tax'));

    final ficaLabel = FlavorConfig.isUS
        ? 'FICA (SS + Medicare)'
        : (FlavorConfig.isUK
            ? 'National Insurance'
            : (fr ? 'RPC + AE' : 'CPP + EI'));

    final stateLabel = FlavorConfig.isUS
        ? (es ? 'Impuesto estatal' : 'State Tax')
        : (fr ? 'Impôt provincial' : 'Provincial Tax');

    final grossLabel =
        fr ? 'Salaire brut' : (es ? 'Salario bruto' : 'Gross Salary');
    final totalTaxLabel =
        fr ? 'Total impôts' : (es ? 'Total impuestos' : 'Total Tax');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(color: AppTheme.primary)),
        SizedBox(height: 12),

        // Net take-home highlight card
        ResultCard(
          label: netLabel,
          value: _fmt(result.netAnnual),
          icon: Icons.account_balance_wallet_outlined,
          highlight: true,
        ),
        SizedBox(height: 12),

        // Monthly / Bi-weekly / Weekly row
        Row(children: [
          Expanded(
              child: ResultCard(
                  label: monthlyLabel, value: _fmt(result.netMonthly))),
          SizedBox(width: 10),
          Expanded(
              child: ResultCard(
                  label: biWeeklyLabel, value: _fmt(result.netBiWeekly))),
        ]),
        SizedBox(height: 10),
        ResultCard(label: weeklyLabel, value: _fmt(result.netWeekly)),
        SizedBox(height: 20),

        // Pie chart
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(breakdownLabel,
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontSize: 15)),
                SizedBox(height: 16),
                SizedBox(
                  height: 200,
                  child: _TaxPieChart(
                    result: result,
                    federalLabel: federalLabel,
                    ficaLabel: ficaLabel,
                    stateLabel: stateLabel,
                  ),
                ),
                SizedBox(height: 16),
                Divider(color: AppTheme.divider),
                SizedBox(height: 8),
                MetricRow(
                    label: grossLabel, value: _fmt(result.grossAnnual)),
                MetricRow(
                    label: federalLabel,
                    value: _fmt(result.federalTax),
                    valueColor: Colors.redAccent),
                if (result.ficaTax > 0)
                  MetricRow(
                      label: ficaLabel,
                      value: _fmt(result.ficaTax),
                      valueColor: Colors.orange),
                if (!FlavorConfig.isUK && result.stateTax > 0)
                  MetricRow(
                      label: stateLabel,
                      value: _fmt(result.stateTax),
                      valueColor: Colors.deepOrange),
                MetricRow(
                    label: totalTaxLabel,
                    value: _fmt(result.totalTax),
                    valueColor: Colors.red),
                MetricRow(
                    label: effectiveLabel, value: _pct(result.effectiveRate)),
                MetricRow(
                    label: netLabel,
                    value: _fmt(result.netAnnual),
                    valueColor: AppTheme.success),
              ],
            ),
          ),
        ),

        SizedBox(height: 16),

        // Smart Insights
        if (FlavorConfig.isUS)
          InsightCard(
            insights: InsightEngine.generate(
              grossAnnual:       result.grossAnnual,
              netAnnual:         result.netAnnual,
              federalTax:        result.federalTax,
              stateTax:          result.stateTax,
              ficaTax:           result.ficaTax,
              federalBracketPct: InsightEngine.usFederalBracketPct(result.grossAnnual),
              isEs: es,
              isFr: fr,
            ),
            isSpanish: es,
          ),

        SizedBox(height: 16),

        // Benefits & deductions estimator
        _BenefitsCard(result: result, fr: fr, es: es),

        SizedBox(height: 16),

        // Pay Rate Converter
        _PayRateConverter(result: result, fr: fr, es: es),

        SizedBox(height: 16),

        // Premium CTA if user is free
        ValueListenableBuilder<bool>(
          valueListenable: freemiumService.isPremiumNotifier,
          builder: (_, isPremium, __) => isPremium
              ? const SizedBox.shrink()
              : PremiumCtaWidget(
                  feature: fr
                      ? 'Historique illimité & PDF'
                      : (es
                          ? 'Historial ilimitado y PDF'
                          : 'Unlimited History & PDF'),
                ),
        ),

        SizedBox(height: 12),

        // PDF export button
        _PdfExportButton(result: result, fr: fr, es: es),
      ],
    );
  }
}

// ─── Benefits & deductions estimator ─────────────────────────────────────────

class _BenefitsCard extends StatefulWidget {
  final SalaryResult result;
  final bool fr, es;
  const _BenefitsCard({required this.result, required this.fr, required this.es});
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
      _insurancePct = 3.0; _retirementPct = 5.0; _unionPct = 1.0;
    } else if (FlavorConfig.isUK) {
      _insurancePct = 2.0; _retirementPct = 5.0; _unionPct = 0.5;
    } else {
      _insurancePct = 5.0; _retirementPct = 6.0; _unionPct = 1.0;
    }
    _insCtrl = TextEditingController(text: _insurancePct.toStringAsFixed(1));
    _retCtrl = TextEditingController(text: _retirementPct.toStringAsFixed(1));
    _uniCtrl = TextEditingController(text: _unionPct.toStringAsFixed(1));
  }

  @override
  void dispose() {
    _insCtrl.dispose(); _retCtrl.dispose(); _uniCtrl.dispose();
    super.dispose();
  }

  double get _gross => widget.result.grossAnnual;
  double get _insAmt  => _gross * _insurancePct  / 100;
  double get _retAmt  => _gross * _retirementPct / 100;
  double get _uniAmt  => _gross * _unionPct      / 100;
  double get _netAfter => widget.result.netAnnual - _insAmt - _retAmt - _uniAmt;

  String _fmt(double v) {
    return NumberFormat.currency(symbol: FlavorConfig.currencySymbol, decimalDigits: 0).format(v);
  }

  void _update(TextEditingController ctrl, void Function(double) setter) {
    final v = double.tryParse(ctrl.text);
    if (v != null && v >= 0 && v <= 50) setState(() => setter(v));
  }

  @override
  Widget build(BuildContext context) {
    final fr = widget.fr; final es = widget.es;
    final title      = fr ? 'Avantages sociaux (estimatif)'  : (es ? 'Beneficios sociales (estimativo)' : 'Benefits & Deductions (estimate)');
    final insLabel   = FlavorConfig.isCA ? (fr ? 'Assurance collective' : 'Group Insurance')
                     : FlavorConfig.isUK ? 'Private Health / Dental' : 'Health Insurance';
    final retLabel   = FlavorConfig.isCA ? (fr ? 'REER' : 'RRSP') : FlavorConfig.isUK ? 'Pension (employee)' : '401(k)';
    final uniLabel   = fr ? 'Cotisation syndicale' : (es ? 'Cuota sindical' : 'Union Dues');
    final netLabel   = fr ? 'Net estimé après déductions' : (es ? 'Neto estimado tras deducciones' : 'Est. Net After Benefits');
    final pctHint    = fr ? '% du brut' : (es ? '% del bruto' : '% of gross');

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(Icons.health_and_safety_outlined, size: 18, color: AppTheme.primary),
              SizedBox(width: 8),
              Expanded(child: Text(title, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600))),
            ]),
            SizedBox(height: 4),
            Text(pctHint, style: TextStyle(fontSize: 11, color: AppTheme.labelGray)),
            SizedBox(height: 12),
            _BenefitRow(label: insLabel, controller: _insCtrl,
              amount: _insAmt, onChanged: () => _update(_insCtrl, (v) => _insurancePct = v)),
            SizedBox(height: 8),
            _BenefitRow(label: retLabel, controller: _retCtrl,
              amount: _retAmt, onChanged: () => _update(_retCtrl, (v) => _retirementPct = v)),
            SizedBox(height: 8),
            _BenefitRow(label: uniLabel, controller: _uniCtrl,
              amount: _uniAmt, onChanged: () => _update(_uniCtrl, (v) => _unionPct = v)),
            Divider(height: 20),
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Text(netLabel, style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
              Text(_fmt(_netAfter),
                style: TextStyle(
                  fontWeight: FontWeight.bold, fontSize: 15,
                  color: _netAfter > 0 ? AppTheme.success : Colors.red),
              ),
            ]),
            SizedBox(height: 4),
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Text(fr ? 'Mensuel' : (es ? 'Mensual' : 'Monthly'),
                style: TextStyle(fontSize: 12, color: AppTheme.labelGray)),
              Text(_fmt(_netAfter / 12),
                style: TextStyle(fontSize: 12, color: AppTheme.labelGray, fontWeight: FontWeight.w500)),
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
  const _BenefitRow({required this.label, required this.controller, required this.amount, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      Expanded(flex: 4, child: Text(label, style: TextStyle(fontSize: 12))),
      SizedBox(
        width: 60,
        child: TextFormField(
          controller: controller,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 13),
          decoration: const InputDecoration(
            suffixText: '%', contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            isDense: true,
          ),
          onChanged: (_) => onChanged(),
        ),
      ),
      SizedBox(width: 8),
      SizedBox(
        width: 80,
        child: Text(
          NumberFormat.currency(symbol: FlavorConfig.currencySymbol, decimalDigits: 0).format(amount),
          textAlign: TextAlign.right,
          style: TextStyle(fontSize: 12, color: AppTheme.labelGray),
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

    final sections = <_Slice>[
      _Slice(
          label: widget.federalLabel,
          value: r.federalTax,
          color: Colors.redAccent),
      if (r.ficaTax > 0)
        _Slice(
            label: widget.ficaLabel,
            value: r.ficaTax,
            color: Colors.orangeAccent),
      if (!FlavorConfig.isUK && r.stateTax > 0)
        _Slice(
            label: widget.stateLabel,
            value: r.stateTax,
            color: Colors.deepOrangeAccent),
      _Slice(
          label: 'Net pay', value: r.netAnnual, color: AppTheme.success),
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
              centerSpaceRadius: 36,
              sections: sections.asMap().entries.map((e) {
                final idx = e.key;
                final s = e.value;
                final pct = s.value / gross * 100;
                final isTouched = idx == _touched;
                return PieChartSectionData(
                  color: s.color,
                  value: s.value,
                  title: '${pct.toStringAsFixed(1)}%',
                  radius: isTouched ? 68 : 58,
                  titleStyle: TextStyle(
                    fontSize: isTouched ? 13 : 11,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                );
              }).toList(),
            ),
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
                    decoration: BoxDecoration(
                        color: s.color, shape: BoxShape.circle),
                  ),
                  SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      s.label,
                      style: TextStyle(
                          fontSize: 11, color: AppTheme.labelGray),
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
  const _Slice({required this.label, required this.value, required this.color});
}

// ─── PDF Export Button ────────────────────────────────────────────────────────

class _PdfExportButton extends StatelessWidget {
  final SalaryResult result;
  final bool fr, es;

  const _PdfExportButton({
    required this.result,
    required this.fr,
    required this.es,
  });

  String get _label => fr ? 'Exporter PDF' : (es ? 'Exportar PDF' : 'Export PDF');

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: freemiumService.isPremiumNotifier,
      builder: (context, isPremium, _) {
        return SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            icon: Icon(Icons.picture_as_pdf_outlined),
            label: Text(_label),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppTheme.primary,
              side: BorderSide(color: AppTheme.primary),
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
            ),
            onPressed: () async {
              if (!isPremium) {
                await PaywallHard.show(context);
                return;
              }
              await _exportPdf(context);
            },
          ),
        );
      },
    );
  }

  Future<void> _exportPdf(BuildContext context) async {
    final symbol = FlavorConfig.currencySymbol;
    final fmtCurrency = NumberFormat.currency(symbol: symbol, decimalDigits: 2);
    final fmtPct      = (double v) => '${v.toStringAsFixed(1)}%';

    final federalLabel = FlavorConfig.isUK
        ? 'Income Tax'
        : (fr ? 'Impôt fédéral' : (es ? 'Impuesto federal' : 'Federal Tax'));
    final ficaLabel = FlavorConfig.isUS
        ? 'FICA (SS + Medicare)'
        : (FlavorConfig.isUK
            ? 'National Insurance'
            : (fr ? 'RPC + AE' : 'CPP + EI'));
    final stateLabel = FlavorConfig.isUS
        ? (es ? 'Impuesto estatal' : 'State Tax')
        : (fr ? 'Impôt provincial' : 'Provincial Tax');
    final grossLabel  = fr ? 'Salaire brut'   : (es ? 'Salario bruto'   : 'Gross Salary');
    final netLabel    = fr ? 'Salaire net'     : (es ? 'Salario neto'    : 'Net Salary (Annual)');
    final totalLabel  = fr ? 'Total impôts'    : (es ? 'Total impuestos' : 'Total Tax');
    final rateLabel   = fr ? 'Taux effectif'   : (es ? 'Tasa efectiva'   : 'Effective Tax Rate');
    final monthLabel  = fr ? 'Mensuel'         : (es ? 'Mensual'         : 'Monthly');
    final titleText   = fr ? 'Analyse salariale' : (es ? 'Análisis salarial' : 'Salary Analysis');

    final doc = pw.Document();
    doc.addPage(pw.Page(
      build: (ctx) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(titleText,
              style: pw.TextStyle(
                  fontSize: 22, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 4),
          pw.Text(DateFormat('MMMM d, yyyy').format(DateTime.now()),
              style: const pw.TextStyle(fontSize: 11)),
          pw.Divider(height: 20),
          _pdfRow(grossLabel, fmtCurrency.format(result.grossAnnual)),
          _pdfRow(federalLabel, fmtCurrency.format(result.federalTax)),
          if (result.ficaTax > 0)
            _pdfRow(ficaLabel, fmtCurrency.format(result.ficaTax)),
          if (!FlavorConfig.isUK && result.stateTax > 0)
            _pdfRow(stateLabel, fmtCurrency.format(result.stateTax)),
          _pdfRow(totalLabel, fmtCurrency.format(result.totalTax)),
          _pdfRow(rateLabel, fmtPct(result.effectiveRate)),
          pw.Divider(height: 20),
          _pdfRow(netLabel, fmtCurrency.format(result.netAnnual)),
          _pdfRow(monthLabel, fmtCurrency.format(result.netMonthly)),
        ],
      ),
    ));

    await Printing.sharePdf(
        bytes: await doc.save(),
        filename: 'salary_summary_${DateTime.now().millisecondsSinceEpoch}.pdf');

    analyticsService.logPdfExported();
  }

  pw.Widget _pdfRow(String label, String value) => pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 4),
        child: pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(label, style: const pw.TextStyle(fontSize: 12)),
            pw.Text(value,
                style: pw.TextStyle(
                    fontSize: 12, fontWeight: pw.FontWeight.bold)),
          ],
        ),
      );
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

  String _fmt(double v) => NumberFormat.currency(
        symbol: FlavorConfig.currencySymbol,
        decimalDigits: 2,
      ).format(v);

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
        period: fr ? 'Journalier (÷260)' : (es ? 'Diario (÷260)' : 'Daily (÷260)'),
        gross: gross / _workingDays,
        net: gross * (1 - effRate) / _workingDays,
      ),
      _RateRow(
        period: fr ? 'Horaire (÷2080)' : (es ? 'Por hora (÷2080)' : 'Hourly (÷2080)'),
        gross: gross / _workingHours,
        net: gross * (1 - effRate) / _workingHours,
      ),
    ];

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(Icons.swap_horiz_rounded,
                  size: 18, color: AppTheme.primary),
              SizedBox(width: 8),
              Text(title,
                  style: TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w600)),
            ]),
            SizedBox(height: 14),
            Table(
              columnWidths: const {
                0: FlexColumnWidth(3),
                1: FlexColumnWidth(3),
                2: FlexColumnWidth(3),
              },
              children: [
                TableRow(
                  decoration: BoxDecoration(
                      border: Border(
                          bottom: BorderSide(color: AppTheme.divider))),
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
            SizedBox(height: 8),
            Text(taxNote,
                style: TextStyle(
                    fontSize: 11,
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
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: AppTheme.labelGray)),
      );

  Widget _td(String text, {Color? color}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 7),
        child: Text(text,
            style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: color)),
      );
}

class _RateRow {
  final String period;
  final double gross, net;
  const _RateRow({required this.period, required this.gross, required this.net});
}
