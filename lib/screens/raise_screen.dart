import '../core/ads/ad_footer.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../core/flavor_config.dart';
import '../core/theme/app_theme.dart';
import '../main.dart' show isSpanishNotifier;
import '../widgets/result_card.dart';

// ─── Raise Screen ─────────────────────────────────────────────────────────────

class RaiseScreen extends StatefulWidget {
  /// If launched from CalculatorScreen, pre-fill with the calculated gross.
  final double? initialSalary;

  const RaiseScreen({super.key, this.initialSalary});

  @override
  State<RaiseScreen> createState() => _RaiseScreenState();
}

class _RaiseScreenState extends State<RaiseScreen> {
  final _formKey = GlobalKey<FormState>();
  final _currentCtrl = TextEditingController();
  final _raiseCtrl = TextEditingController();

  /// true = percentage raise, false = dollar/pound raise
  bool _isPercent = true;

  _RaiseResult? _result;

  @override
  void initState() {
    super.initState();
    if (widget.initialSalary != null && widget.initialSalary! > 0) {
      _currentCtrl.text = widget.initialSalary!.toStringAsFixed(0);
    }
  }

  @override
  void dispose() {
    _currentCtrl.dispose();
    _raiseCtrl.dispose();
    super.dispose();
  }

  void _calculate() {
    if (!_formKey.currentState!.validate()) return;
    HapticFeedback.mediumImpact();
    FocusScope.of(context).unfocus();

    final current = _parseAmount(_currentCtrl.text);
    final raiseVal = _parseAmount(_raiseCtrl.text);
    if (current <= 0 || raiseVal <= 0) return;

    final double raisePct =
        _isPercent ? raiseVal : (raiseVal / current * 100);
    final double newAnnual =
        _isPercent ? current * (1 + raisePct / 100) : current + raiseVal;

    const taxEst = 0.25;
    final newMonthlyNet = newAnnual * (1 - taxEst) / 12;
    final oldMonthlyNet = current * (1 - taxEst) / 12;
    final extraMonth = newMonthlyNet - oldMonthlyNet;
    final extraYear = newAnnual - current;

    // Rule of 72
    final yearsToDouble = raisePct > 0 ? 72 / raisePct : double.infinity;

    // 5-year projection (compound raises)
    final in5Years = current * (1 + raisePct / 100) * (1 + raisePct / 100) *
        (1 + raisePct / 100) *
        (1 + raisePct / 100) *
        (1 + raisePct / 100);

    setState(() {
      _result = _RaiseResult(
        currentSalary: current,
        newAnnual: newAnnual,
        raisePct: raisePct,
        newMonthlyNet: newMonthlyNet,
        extraPerMonth: extraMonth,
        extraPerYear: extraYear,
        yearsToDouble: yearsToDouble,
        in5Years: in5Years,
      );
    });
  }

  double _parseAmount(String text) {
    if (text.isEmpty) return 0;
    final raw = (text.contains('.') && text.contains(','))
        ? text.replaceAll(',', '')
        : text.replaceAll(',', '.');
    return double.tryParse(raw.replaceAll(RegExp(r'[^\d.]'), '')) ?? 0;
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: isSpanishNotifier,
      builder: (context, useAlt, _) {
        final es = FlavorConfig.isUS && useAlt;
        final fr = FlavorConfig.isCA && useAlt;

        final title =
            fr ? 'Calculateur d\'augmentation' : (es ? 'Calculadora de aumento' : 'Raise Calculator');
        final calcLabel =
            fr ? 'Calculer' : (es ? 'Calcular' : 'Calculate');

        return Scaffold(
          appBar: AppBar(title: Text(title)),
          body: Column(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _InputCard(
                          currentCtrl: _currentCtrl,
                          raiseCtrl: _raiseCtrl,
                          isPercent: _isPercent,
                          es: es,
                          fr: fr,
                          onTypeToggle: (v) => setState(() => _isPercent = v),
                        ),
                        SizedBox(height: 24),
                        ElevatedButton(
                          onPressed: _calculate,
                          child: Text(calcLabel,
                              style: TextStyle(
                                  fontSize: 16, fontWeight: FontWeight.w700)),
                        ),
                        if (_result != null) ...[
                          SizedBox(height: 28),
                          _ResultsSection(
                              result: _result!, es: es, fr: fr),
                        ],
                        SizedBox(height: 16),
                      ],
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

// ─── Data model ───────────────────────────────────────────────────────────────

class _RaiseResult {
  final double currentSalary;
  final double newAnnual;
  final double raisePct;
  final double newMonthlyNet;
  final double extraPerMonth;
  final double extraPerYear;
  final double yearsToDouble;
  final double in5Years;

  const _RaiseResult({
    required this.currentSalary,
    required this.newAnnual,
    required this.raisePct,
    required this.newMonthlyNet,
    required this.extraPerMonth,
    required this.extraPerYear,
    required this.yearsToDouble,
    required this.in5Years,
  });
}

// ─── Input card ───────────────────────────────────────────────────────────────

class _InputCard extends StatelessWidget {
  final TextEditingController currentCtrl;
  final TextEditingController raiseCtrl;
  final bool isPercent;
  final bool es, fr;
  final ValueChanged<bool> onTypeToggle;

  const _InputCard({
    required this.currentCtrl,
    required this.raiseCtrl,
    required this.isPercent,
    required this.es,
    required this.fr,
    required this.onTypeToggle,
  });

  @override
  Widget build(BuildContext context) {
    final symbol = FlavorConfig.currencySymbol;
    final currentLabel =
        fr ? 'Salaire actuel (annuel)' : (es ? 'Salario actual (anual)' : 'Current Annual Salary');
    final raiseTypeLabel =
        fr ? 'Type d\'augmentation' : (es ? 'Tipo de aumento' : 'Raise Type');
    final pctLabel = fr ? '% (pourcentage)' : (es ? '% (porcentaje)' : '% (percentage)');
    final amtLabel =
        fr ? '$symbol (montant fixe)' : (es ? '$symbol (monto fijo)' : '$symbol (flat amount)');
    final raiseLabel =
        fr ? 'Valeur de l\'augmentation' : (es ? 'Valor del aumento' : 'Raise Value');

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Current salary
            TextFormField(
              controller: currentCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[\d.,]')),
              ],
              decoration: InputDecoration(
                prefixText: '$symbol ',
                labelText: currentLabel,
                hintText: '60000',
              ),
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              validator: (v) {
                if (v == null || v.trim().isEmpty) {
                  return fr ? 'Requis' : (es ? 'Requerido' : 'Required');
                }
                final val = double.tryParse(
                    v.replaceAll(',', '.').replaceAll(RegExp(r'[^\d.]'), ''));
                if (val == null || val <= 0) {
                  return fr ? 'Montant invalide' : (es ? 'Inválido' : 'Invalid amount');
                }
                return null;
              },
            ),
            SizedBox(height: 20),

            // Raise type toggle
            Text(raiseTypeLabel,
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.labelGray)),
            SizedBox(height: 8),
            Row(children: [
              Expanded(
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
              SizedBox(width: 8),
              Expanded(
                child: ChoiceChip(
                  label: Text(amtLabel),
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
            ]),
            SizedBox(height: 16),

            // Raise value
            TextFormField(
              controller: raiseCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[\d.,]')),
              ],
              decoration: InputDecoration(
                prefixText: isPercent ? '' : '$symbol ',
                suffixText: isPercent ? '%' : '',
                labelText: raiseLabel,
                hintText: isPercent ? '5' : '3000',
              ),
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              validator: (v) {
                if (v == null || v.trim().isEmpty) {
                  return fr ? 'Requis' : (es ? 'Requerido' : 'Required');
                }
                final val = double.tryParse(
                    v.replaceAll(',', '.').replaceAll(RegExp(r'[^\d.]'), ''));
                if (val == null || val <= 0) {
                  return fr ? 'Valeur invalide' : (es ? 'Inválido' : 'Invalid value');
                }
                return null;
              },
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Results section ──────────────────────────────────────────────────────────

class _ResultsSection extends StatelessWidget {
  final _RaiseResult result;
  final bool es, fr;

  const _ResultsSection({
    required this.result,
    required this.es,
    required this.fr,
  });

  String _fmt(double v) => NumberFormat.currency(
        symbol: FlavorConfig.currencySymbol,
        decimalDigits: 0,
      ).format(v);

  String _fmt2(double v) => NumberFormat.currency(
        symbol: FlavorConfig.currencySymbol,
        decimalDigits: 2,
      ).format(v);

  @override
  Widget build(BuildContext context) {
    final newAnnualLabel =
        fr ? 'Nouveau salaire annuel' : (es ? 'Nuevo salario anual' : 'New Annual Salary');
    final newMonthlyLabel = fr
        ? 'Revenu mensuel net estimé'
        : (es ? 'Ingreso mensual neto estimado' : 'Est. Monthly Net Take-Home');
    final extraMonthLabel = fr
        ? 'Gain supplémentaire par mois'
        : (es ? 'Extra por mes' : 'Extra per month');
    final extraYearLabel = fr
        ? 'Gain supplémentaire par an'
        : (es ? 'Extra por año' : 'Extra per year');
    final doubleLabel = fr
        ? 'Années pour doubler le salaire'
        : (es ? 'Años para doblar el salario' : 'Years to double salary');
    final in5Label = fr
        ? 'Projection 5 ans'
        : (es ? 'Proyección a 5 años' : 'Salary in 5 years');
    final taxNote = fr
        ? '* Net estimé après ~25 % d\'impôt'
        : (es ? '* Neto estimado con ~25 % de impuestos' : '* Net estimated after ~25% tax');

    final yearsStr = result.yearsToDouble.isFinite
        ? result.yearsToDouble.toStringAsFixed(1)
        : '∞';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Main results
        ResultCard(
          label: newAnnualLabel,
          value: _fmt(result.newAnnual),
          icon: Icons.trending_up_rounded,
          highlight: true,
        ),
        SizedBox(height: 12),
        Row(children: [
          Expanded(
              child: ResultCard(
                  label: newMonthlyLabel, value: _fmt2(result.newMonthlyNet))),
          SizedBox(width: 10),
          Expanded(
              child: ResultCard(
                  label: extraMonthLabel,
                  value: '+${_fmt2(result.extraPerMonth)}')),
        ]),
        SizedBox(height: 10),
        Row(children: [
          Expanded(
              child: ResultCard(
                  label: extraYearLabel,
                  value: '+${_fmt(result.extraPerYear)}')),
          SizedBox(width: 10),
          Expanded(
              child: ResultCard(label: doubleLabel, value: yearsStr)),
        ]),
        SizedBox(height: 10),
        ResultCard(label: in5Label, value: _fmt(result.in5Years)),
        SizedBox(height: 6),
        Padding(
          padding: const EdgeInsets.only(left: 4),
          child: Text(taxNote,
              style: TextStyle(
                  fontSize: 11, color: AppTheme.labelGray,
                  fontStyle: FontStyle.italic)),
        ),
        SizedBox(height: 20),

        // Scenarios comparison table
        _ScenariosCard(
            currentSalary: result.currentSalary, es: es, fr: fr),
      ],
    );
  }
}

// ─── Scenario comparison ──────────────────────────────────────────────────────

class _ScenariosCard extends StatelessWidget {
  final double currentSalary;
  final bool es, fr;

  const _ScenariosCard({
    required this.currentSalary,
    required this.es,
    required this.fr,
  });

  String _fmt(double v) => NumberFormat.currency(
        symbol: FlavorConfig.currencySymbol,
        decimalDigits: 0,
      ).format(v);

  @override
  Widget build(BuildContext context) {
    final title = fr
        ? 'Comparaison de scénarios'
        : (es ? 'Comparar escenarios' : 'Compare Scenarios');
    final raiseLabel = fr ? 'Augmentation' : (es ? 'Aumento' : 'Raise');
    final newAnnualLabel = fr ? 'Nouv. annuel' : (es ? 'Nuevo anual' : 'New Annual');
    final extraLabel = fr ? 'Extra/an' : (es ? 'Extra/año' : 'Extra/yr');

    const scenarios = [3.0, 5.0, 10.0];

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(Icons.compare_arrows_rounded,
                  size: 18, color: AppTheme.primary),
              SizedBox(width: 8),
              Text(title,
                  style: TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w600)),
            ]),
            SizedBox(height: 14),
            Table(
              columnWidths: const {
                0: FlexColumnWidth(2),
                1: FlexColumnWidth(3),
                2: FlexColumnWidth(3),
              },
              children: [
                TableRow(
                  decoration: BoxDecoration(
                      border: Border(
                          bottom: BorderSide(color: AppTheme.divider))),
                  children: [
                    _headerCell(raiseLabel),
                    _headerCell(newAnnualLabel),
                    _headerCell(extraLabel),
                  ],
                ),
                for (final pct in scenarios)
                  TableRow(children: [
                    _dataCell('${pct.toStringAsFixed(0)}%',
                        color: AppTheme.primary),
                    _dataCell(_fmt(currentSalary * (1 + pct / 100))),
                    _dataCell(
                        '+${_fmt(currentSalary * pct / 100)}',
                        color: AppTheme.success),
                  ]),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _headerCell(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(text,
            style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: AppTheme.labelGray)),
      );

  Widget _dataCell(String text, {Color? color}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Text(text,
            style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: color)),
      );
}
