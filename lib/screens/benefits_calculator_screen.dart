import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../core/flavor_config.dart';
import '../core/freemium/freemium_service.dart';
import '../core/freemium/iap_service.dart';
import '../core/theme/app_theme.dart';
import '../main.dart' show isSpanishNotifier, salaryNotifier;
import '../widgets/paywall_hard.dart';
import '../widgets/result_card.dart';
import 'package:calcwise_core/calcwise_core.dart'
    show
        CalcwiseAdFooter,
        CalcwiseHeroCard,
        AppDuration,
        AppSpacing,
        AppRadius,
        AppTextSize;

// ─── Benefits Value Calculator ────────────────────────────────────────────────
//
// Calculates the total monetary value of employer benefits and adds it to the
// base salary to produce a Total Compensation figure.
//
// Flavor-specific labels:
//   US  → 401(k) Match  | USD
//   CA  → RRSP Match    | CAD
//   UK  → Pension Contribution | GBP

class BenefitsCalculatorScreen extends StatefulWidget {
  const BenefitsCalculatorScreen({super.key});

  @override
  State<BenefitsCalculatorScreen> createState() =>
      _BenefitsCalculatorScreenState();
}

class _BenefitsCalculatorScreenState extends State<BenefitsCalculatorScreen> {
  // ── Controllers ────────────────────────────────────────────────────────────
  late final TextEditingController _salaryCtrl;
  final _healthCtrl = TextEditingController(text: '500');
  final _retirementPctCtrl = TextEditingController(text: '4');
  final _ptoDaysCtrl = TextEditingController(text: '15');
  final _remoteCtrl = TextEditingController(text: '0');
  final _otherCtrl = TextEditingController(text: '0');

  // ── Results ────────────────────────────────────────────────────────────────
  _BenefitsResult? _result;
  bool _hasCalculated = false;

  @override
  void initState() {
    super.initState();
    final salary = salaryNotifier.value;
    _salaryCtrl =
        TextEditingController(text: salary > 0 ? salary.toStringAsFixed(0) : (FlavorConfig.isUK ? '55000' : '75000'));

    // Gate check: show hard paywall immediately if not premium
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (!freemiumService.hasFullAccess) {
        final es = FlavorConfig.isUS && isSpanishNotifier.value;
        final fr = FlavorConfig.isCA && isSpanishNotifier.value;
        PaywallHard.show(
          context,
          isSpanish: es,
          isFrench: fr,
          priceLabel: IAPService.instance.localizedPrice.value,
          onPurchase: IAPService.instance.buy,
        );
      } else {
        _calculate();
      }
    });
  }

  @override
  void dispose() {
    _salaryCtrl.dispose();
    _healthCtrl.dispose();
    _retirementPctCtrl.dispose();
    _ptoDaysCtrl.dispose();
    _remoteCtrl.dispose();
    _otherCtrl.dispose();
    super.dispose();
  }

  double _parse(TextEditingController c) {
    final raw = c.text.replaceAll(',', '').replaceAll(RegExp(r'[^\d.]'), '');
    return double.tryParse(raw) ?? 0;
  }

  void _calculate() {
    HapticFeedback.mediumImpact();
    FocusScope.of(context).unfocus();

    final salary = _parse(_salaryCtrl);
    final healthMonthly = _parse(_healthCtrl);
    final retirementPct = _parse(_retirementPctCtrl);
    final ptoDays = _parse(_ptoDaysCtrl);
    final remoteMonthly = _parse(_remoteCtrl);
    final otherAnnual = _parse(_otherCtrl);

    if (salary <= 0) return;

    final healthAnnual = healthMonthly * 12;
    final retirementAnnual = salary * retirementPct / 100;
    // PTO value = salary / 260 * number of PTO days
    final ptoAnnual = salary / 260.0 * ptoDays;
    final remoteAnnual = remoteMonthly * 12;

    final totalBenefits =
        healthAnnual + retirementAnnual + ptoAnnual + remoteAnnual + otherAnnual;
    final totalCompensation = salary + totalBenefits;

    setState(() {
      _result = _BenefitsResult(
        baseSalary: salary,
        healthAnnual: healthAnnual,
        retirementAnnual: retirementAnnual,
        ptoAnnual: ptoAnnual,
        remoteAnnual: remoteAnnual,
        otherAnnual: otherAnnual,
        totalBenefits: totalBenefits,
        totalCompensation: totalCompensation,
      );
      _hasCalculated = true;
    });
  }

  Future<void> _sharePdf(BuildContext context, _BenefitsResult r, bool fr,
      bool es) async {
    final symbol = FlavorConfig.currencySymbol;
    final fmtCur =
        NumberFormat.currency(symbol: symbol, decimalDigits: 0);
    final retLabel = _retirementLabel(fr, es);
    final doc = pw.Document();
    doc.addPage(pw.Page(
      build: (ctx) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            fr
                ? 'Rapport de rémunération globale'
                : es
                    ? 'Informe de compensación total'
                    : 'Total Compensation Report',
            style: pw.TextStyle(
                fontSize: AppTextSize.title, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 4),
          pw.Text(DateFormat('MMMM d, yyyy').format(DateTime.now()),
              style: const pw.TextStyle(fontSize: AppTextSize.xs)),
          pw.Divider(height: 24),
          _pdfRow(
              fr
                  ? 'Salaire de base'
                  : es
                      ? 'Salario base'
                      : 'Base Salary',
              fmtCur.format(r.baseSalary)),
          pw.Divider(height: 16),
          pw.Text(
              fr
                  ? 'Valeur des avantages sociaux'
                  : es
                      ? 'Valor de beneficios laborales'
                      : 'Benefits Value',
              style: pw.TextStyle(
                  fontSize: AppTextSize.sm, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 6),
          _pdfRow(
              fr
                  ? 'Assurance santé (annuelle)'
                  : es
                      ? 'Seguro de salud (anual)'
                      : (FlavorConfig.isUK ? 'Private Health Insurance (annual)' : 'Health Insurance (annual)'),
              fmtCur.format(r.healthAnnual)),
          _pdfRow(retLabel, fmtCur.format(r.retirementAnnual)),
          _pdfRow(
              fr
                  ? 'Valeur des congés payés'
                  : es
                      ? 'Valor de vacaciones pagadas'
                      : (FlavorConfig.isUK ? 'Annual Leave Value' : 'PTO Value'),
              fmtCur.format(r.ptoAnnual)),
          if (r.remoteAnnual > 0)
            _pdfRow(
                fr
                    ? 'Économies télétravail (annuelles)'
                    : es
                        ? 'Ahorro trabajo remoto (anual)'
                        : 'Remote Work Savings (annual)',
                fmtCur.format(r.remoteAnnual)),
          if (r.otherAnnual > 0)
            _pdfRow(
                fr
                    ? 'Autres avantages'
                    : es
                        ? 'Otros beneficios'
                        : 'Other Perks',
                fmtCur.format(r.otherAnnual)),
          pw.Divider(height: 16),
          _pdfRow(
              fr
                  ? 'Total des avantages sociaux'
                  : es
                      ? 'Total beneficios'
                      : 'Total Benefits Value',
              fmtCur.format(r.totalBenefits),
              bold: true),
          pw.SizedBox(height: 8),
          _pdfRow(
              fr
                  ? 'Rémunération globale'
                  : es
                      ? 'Compensación total'
                      : 'Total Compensation',
              fmtCur.format(r.totalCompensation),
              bold: true),
          pw.SizedBox(height: 20),
          pw.Text(
            fr
                ? '* Estimations à titre informatif uniquement. Ceci n\'est pas un conseil financier.'
                : es
                    ? '* Estimaciones con fines informativos únicamente. No es asesoramiento financiero.'
                    : '* Estimates for informational purposes only. Not financial advice.',
            style: const pw.TextStyle(fontSize: 8),
          ),
        ],
      ),
    ));
    await Printing.sharePdf(
        bytes: await doc.save(),
        filename:
            'total_compensation_${DateTime.now().millisecondsSinceEpoch}.pdf');
  }

  pw.Widget _pdfRow(String label, String value, {bool bold = false}) =>
      pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 3),
        child: pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(label,
                style: const pw.TextStyle(fontSize: AppTextSize.sm)),
            pw.Text(value,
                style: pw.TextStyle(
                    fontSize: AppTextSize.sm,
                    fontWeight:
                        bold ? pw.FontWeight.bold : pw.FontWeight.normal)),
          ],
        ),
      );

  String _retirementLabel(bool fr, bool es) {
    if (FlavorConfig.isCA) return fr ? 'Cotisation REER employeur' : 'RRSP Match';
    if (FlavorConfig.isUK) return 'Pension Contribution';
    return es ? 'Aportación 401(k) empleador' : '401(k) Match';
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: isSpanishNotifier,
      builder: (context, useAlt, _) {
        final es = FlavorConfig.isUS && useAlt;
        final fr = FlavorConfig.isCA && useAlt;

        String t(String en, String esStr, String frStr) =>
            fr ? frStr : (es ? esStr : en);

        final symbol = FlavorConfig.currencySymbol;
        final retLabel = _retirementLabel(fr, es);

        return Scaffold(
          appBar: AppBar(
            title: Text(t(
              'Benefits Value Calculator',
              'Calculadora de beneficios',
              'Calculateur d\'avantages',
            )),
          ),
          body: Column(
            children: [
              Expanded(
                child: ValueListenableBuilder<bool>(
                  valueListenable: freemiumService.hasFullAccessNotifier,
                  builder: (context, isPremium, _) {
                    if (!isPremium) {
                      return _LockedView(fr: fr, es: es);
                    }
                    return SingleChildScrollView(
                      padding: EdgeInsets.fromLTRB(
                        AppSpacing.lg,
                        AppSpacing.lg,
                        AppSpacing.lg,
                        AppSpacing.lg +
                            MediaQuery.of(context).padding.bottom +
                            AppSpacing.xl,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            t(
                              'Enter your employer\'s benefit contributions to calculate your true total compensation.',
                              'Ingresa las contribuciones de beneficios de tu empleador para calcular tu compensación total real.',
                              'Entrez les contributions d\'avantages sociaux de votre employeur pour calculer votre rémunération globale réelle.',
                            ),
                            style: TextStyle(
                              fontSize: AppTextSize.md,
                              color: AppTheme.labelGray,
                            ),
                          ),
                          const SizedBox(height: AppSpacing.md),

                          // ── Input card ─────────────────────────────────────
                          Card(
                            child: Padding(
                              padding: const EdgeInsets.all(AppSpacing.lg),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    t('Your Salary', 'Tu salario',
                                        'Votre salaire'),
                                    style: TextStyle(
                                      fontSize: AppTextSize.md,
                                      fontWeight: FontWeight.w600,
                                      color: AppTheme.labelGray,
                                    ),
                                  ),
                                  const SizedBox(height: AppSpacing.sm),
                                  TextFormField(
                                    controller: _salaryCtrl,
                                    keyboardType:
                                        const TextInputType.numberWithOptions(
                                            decimal: true),
                                    textInputAction: TextInputAction.next,
                                    inputFormatters: [
                                      FilteringTextInputFormatter.allow(
                                          RegExp(r'[\d.,]')),
                                    ],
                                    decoration: InputDecoration(
                                      labelText: t('Base Annual Salary',
                                          'Salario anual base',
                                          'Salaire annuel de base'),
                                      prefixText: '$symbol ',
                                      hintText: '75000',
                                    ),
                                    style: const TextStyle(
                                        fontSize: AppTextSize.bodyLg,
                                        fontWeight: FontWeight.w600),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: AppSpacing.sm),

                          // ── Benefits inputs ────────────────────────────────
                          Card(
                            child: Padding(
                              padding: const EdgeInsets.all(AppSpacing.lg),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    t('Employer Benefits',
                                        'Beneficios del empleador',
                                        'Avantages employeur'),
                                    style: TextStyle(
                                      fontSize: AppTextSize.md,
                                      fontWeight: FontWeight.w600,
                                      color: AppTheme.labelGray,
                                    ),
                                  ),
                                  const SizedBox(height: AppSpacing.sm),

                                  // Health Insurance
                                  TextFormField(
                                    controller: _healthCtrl,
                                    keyboardType:
                                        const TextInputType.numberWithOptions(
                                            decimal: true),
                                    textInputAction: TextInputAction.next,
                                    inputFormatters: [
                                      FilteringTextInputFormatter.allow(
                                          RegExp(r'[\d.,]')),
                                    ],
                                    decoration: InputDecoration(
                                      labelText: FlavorConfig.isUK
                                          ? 'Private Health Insurance (employer contribution)'
                                          : t(
                                              'Health Insurance (employer contribution)',
                                              'Seguro de salud (contribución empleador)',
                                              'Assurance santé (contribution employeur)',
                                            ),
                                      prefixText: '$symbol ',
                                      hintText: '400',
                                      helperText:
                                          t('/month', '/mes', '/mois'),
                                    ),
                                  ),
                                  const SizedBox(height: AppSpacing.sm),

                                  // Retirement match %
                                  TextFormField(
                                    controller: _retirementPctCtrl,
                                    keyboardType:
                                        const TextInputType.numberWithOptions(
                                            decimal: true),
                                    textInputAction: TextInputAction.next,
                                    inputFormatters: [
                                      FilteringTextInputFormatter.allow(
                                          RegExp(r'[\d.,]')),
                                    ],
                                    decoration: InputDecoration(
                                      labelText: retLabel,
                                      suffixText: '%',
                                      hintText: '4',
                                      helperText: t(
                                          '% of base salary',
                                          '% del salario base',
                                          '% du salaire de base'),
                                    ),
                                  ),
                                  const SizedBox(height: AppSpacing.sm),

                                  // PTO days
                                  TextFormField(
                                    controller: _ptoDaysCtrl,
                                    keyboardType:
                                        const TextInputType.numberWithOptions(
                                            decimal: true),
                                    textInputAction: TextInputAction.next,
                                    inputFormatters: [
                                      FilteringTextInputFormatter.allow(
                                          RegExp(r'[\d.,]')),
                                    ],
                                    decoration: InputDecoration(
                                      labelText: FlavorConfig.isUK
                                          ? 'Annual Leave Days'
                                          : t('PTO Days', 'Días de vacaciones',
                                              'Jours de congé payé'),
                                      hintText: '15',
                                      helperText: t(
                                          'Value = salary ÷ 260 × days',
                                          'Valor = salario ÷ 260 × días',
                                          'Valeur = salaire ÷ 260 × jours'),
                                    ),
                                  ),
                                  const SizedBox(height: AppSpacing.sm),

                                  // Remote savings
                                  TextFormField(
                                    controller: _remoteCtrl,
                                    keyboardType:
                                        const TextInputType.numberWithOptions(
                                            decimal: true),
                                    textInputAction: TextInputAction.next,
                                    inputFormatters: [
                                      FilteringTextInputFormatter.allow(
                                          RegExp(r'[\d.,]')),
                                    ],
                                    decoration: InputDecoration(
                                      labelText: t(
                                        'Remote Work Savings (optional)',
                                        'Ahorro trabajo remoto (opcional)',
                                        'Économies télétravail (facultatif)',
                                      ),
                                      prefixText: '$symbol ',
                                      hintText: '0',
                                      helperText:
                                          t('/month', '/mes', '/mois'),
                                    ),
                                  ),
                                  const SizedBox(height: AppSpacing.sm),

                                  // Other perks
                                  TextFormField(
                                    controller: _otherCtrl,
                                    keyboardType:
                                        const TextInputType.numberWithOptions(
                                            decimal: true),
                                    textInputAction: TextInputAction.done,
                                    inputFormatters: [
                                      FilteringTextInputFormatter.allow(
                                          RegExp(r'[\d.,]')),
                                    ],
                                    decoration: InputDecoration(
                                      labelText: t(
                                        'Other Perks (optional)',
                                        'Otros beneficios (opcional)',
                                        'Autres avantages (facultatif)',
                                      ),
                                      prefixText: '$symbol ',
                                      hintText: '0',
                                      helperText:
                                          t('/year', '/año', '/an'),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: AppSpacing.lg),

                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton(
                              onPressed: _calculate,
                              child: Text(
                                t('Calculate', 'Calcular', 'Calculer'),
                                style: const TextStyle(
                                    fontSize: AppTextSize.bodyLg,
                                    fontWeight: FontWeight.w700),
                              ),
                            ),
                          ),

                          // ── Results ────────────────────────────────────────
                          if (_hasCalculated && _result != null) ...[
                            const SizedBox(height: AppSpacing.xl),
                            _buildResults(context, _result!, fr, es, symbol,
                                retLabel, t),
                          ],

                          const SizedBox(height: AppSpacing.lg),
                        ],
                      ),
                    );
                  },
                ),
              ),
              const CalcwiseAdFooter(),
            ],
          ),
        );
      },
    );
  }

  Widget _buildResults(
    BuildContext context,
    _BenefitsResult r,
    bool fr,
    bool es,
    String symbol,
    String retLabel,
    String Function(String, String, String) t,
  ) {
    final fmtCur =
        NumberFormat.currency(symbol: symbol, decimalDigits: 0);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Hero: Total Compensation
        CalcwiseHeroCard(
          label: t(
            'Total Compensation',
            'Compensación total',
            'Rémunération globale',
          ),
          value: fmtCur.format(r.totalCompensation),
          secondary: t(
            'Salary + Benefits / year',
            'Salario + Beneficios / año',
            'Salaire + Avantages / an',
          ),
          gradient: LinearGradient(
            colors: [
              AppTheme.primary,
              AppTheme.primary.withValues(alpha: 0.75),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),

        // Benefits breakdown card
        Card(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              children: [
                MetricRow(
                  label: t('Base Salary', 'Salario base', 'Salaire de base'),
                  value: fmtCur.format(r.baseSalary),
                  valueColor: AppTheme.primary,
                ),
                const Divider(height: 20),
                Text(
                  t('Benefits Breakdown', 'Desglose de beneficios',
                      'Détail des avantages'),
                  style: TextStyle(
                    fontSize: AppTextSize.md,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.labelGray,
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                if (r.healthAnnual > 0)
                  MetricRow(
                    label: FlavorConfig.isUK
                        ? 'Private Health Insurance (annual)'
                        : t('Health Insurance (annual)',
                            'Seguro de salud (anual)',
                            'Assurance santé (annuelle)'),
                    value: fmtCur.format(r.healthAnnual),
                    valueColor: AppTheme.success,
                  ),
                MetricRow(
                  label: retLabel,
                  value: fmtCur.format(r.retirementAnnual),
                  valueColor: AppTheme.success,
                ),
                MetricRow(
                  label: FlavorConfig.isUK
                      ? 'Annual Leave Value'
                      : t('PTO Value', 'Valor vacaciones', 'Valeur congés'),
                  value: fmtCur.format(r.ptoAnnual),
                  valueColor: AppTheme.success,
                ),
                if (r.remoteAnnual > 0)
                  MetricRow(
                    label: t('Remote Savings (annual)',
                        'Ahorro remoto (anual)',
                        'Économies télétravail (annuel)'),
                    value: fmtCur.format(r.remoteAnnual),
                    valueColor: AppTheme.success,
                  ),
                if (r.otherAnnual > 0)
                  MetricRow(
                    label: t('Other Perks', 'Otros beneficios',
                        'Autres avantages'),
                    value: fmtCur.format(r.otherAnnual),
                    valueColor: AppTheme.success,
                  ),
                const Divider(height: 20),
                MetricRow(
                  label: t('Total Benefits Value', 'Valor total de beneficios',
                      'Valeur totale des avantages sociaux'),
                  value: fmtCur.format(r.totalBenefits),
                  valueColor: AppTheme.success,
                ),
                MetricRow(
                  label: t('Total Compensation', 'Compensación total',
                      'Rémunération globale'),
                  value: fmtCur.format(r.totalCompensation),
                  valueColor: AppTheme.primary,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),

        // Benefits as % of salary
        _BenefitsPercentCard(result: r, fr: fr, es: es, symbol: symbol),

        const SizedBox(height: AppSpacing.md),

        // PDF export button
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            icon: const Icon(Icons.picture_as_pdf_rounded),
            label: Text(t(
                'Export PDF Report', 'Exportar informe PDF',
                'Exporter rapport PDF')),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppTheme.primary,
              side: BorderSide(color: AppTheme.primary),
              padding:
                  const EdgeInsets.symmetric(vertical: AppSpacing.smPlus),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppRadius.xl)),
            ),
            onPressed: () => _sharePdf(context, r, fr, es),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Text(
            t(
              '* Estimates only. Consult HR or a financial advisor for exact benefit values.',
              '* Solo estimaciones. Consulta a RR.HH. o a un asesor financiero para valores exactos.',
              '* Estimations uniquement. Consultez les RH ou un conseiller financier pour des valeurs exactes.',
            ),
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

// ─── Benefits % of salary card ────────────────────────────────────────────────

class _BenefitsPercentCard extends StatelessWidget {
  final _BenefitsResult result;
  final bool fr, es;
  final String symbol;

  const _BenefitsPercentCard({
    required this.result,
    required this.fr,
    required this.es,
    required this.symbol,
  });

  @override
  Widget build(BuildContext context) {
    final pct = result.baseSalary > 0
        ? (result.totalBenefits / result.baseSalary * 100)
        : 0.0;
    final title = fr
        ? 'Avantages en % du salaire'
        : (es ? 'Beneficios como % del salario' : 'Benefits as % of Salary');
    final pctLabel = fr
        ? 'Vos avantages représentent ${pct.toStringAsFixed(1)} % de votre salaire'
        : (es
            ? 'Tus beneficios representan el ${pct.toStringAsFixed(1)} % de tu salario'
            : 'Your benefits represent ${pct.toStringAsFixed(1)}% of your base salary');

    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppTheme.primary.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(AppRadius.xl),
        border: Border.all(color: AppTheme.primary.withValues(alpha: 0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.pie_chart_rounded, color: AppTheme.primary, size: 18),
              const SizedBox(width: 8),
              Text(title,
                  style: TextStyle(
                      fontSize: AppTextSize.bodyMd,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.primary)),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            pctLabel,
            style: TextStyle(
                fontSize: AppTextSize.md, color: AppTheme.labelGray),
          ),
          const SizedBox(height: AppSpacing.sm),
          ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.full),
            child: LinearProgressIndicator(
              value: (pct / 100).clamp(0.0, 1.0),
              minHeight: 8,
              backgroundColor: AppTheme.divider,
              valueColor: AlwaysStoppedAnimation<Color>(AppTheme.primary),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Locked view (shown before paywall resolves) ──────────────────────────────

class _LockedView extends StatelessWidget {
  final bool fr, es;

  const _LockedView({required this.fr, required this.es});

  @override
  Widget build(BuildContext context) {
    final title = fr
        ? 'Calculateur d\'avantages'
        : (es ? 'Calculadora de beneficios' : 'Benefits Value Calculator');
    final subtitle = fr
        ? 'Calculez la valeur réelle de vos avantages sociaux.'
        : (es
            ? 'Calcula el valor real de tus beneficios.'
            : 'Calculate the real value of your employer benefits.');

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.card_giftcard_rounded,
                size: 56, color: AppTheme.primary),
            const SizedBox(height: AppSpacing.lg),
            Text(title,
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: AppTextSize.bodyXl,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.primary)),
            const SizedBox(height: AppSpacing.sm),
            Text(subtitle,
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: AppTextSize.body, color: AppTheme.labelGray)),
            const SizedBox(height: AppSpacing.xl),
            Icon(Icons.lock_rounded, size: 32, color: AppTheme.labelGray),
          ],
        ),
      ),
    );
  }
}

// ─── Result model ─────────────────────────────────────────────────────────────

class _BenefitsResult {
  final double baseSalary;
  final double healthAnnual;
  final double retirementAnnual;
  final double ptoAnnual;
  final double remoteAnnual;
  final double otherAnnual;
  final double totalBenefits;
  final double totalCompensation;

  const _BenefitsResult({
    required this.baseSalary,
    required this.healthAnnual,
    required this.retirementAnnual,
    required this.ptoAnnual,
    required this.remoteAnnual,
    required this.otherAnnual,
    required this.totalBenefits,
    required this.totalCompensation,
  });
}
