import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';

import '../core/analytics/analytics_service.dart';
import '../core/db/database_service.dart';
import '../core/flavor_config.dart';
import '../core/freemium/freemium_service.dart';
import '../core/freemium/iap_service.dart';
import '../core/salary_engine.dart';
import '../core/services/pdf_export_service.dart' show PdfExportService;
import '../core/theme/app_theme.dart';
import '../main.dart' show isSpanishNotifier;
import 'package:calcwise_core/calcwise_core.dart' show CalcwiseAdFooter;
import 'package:calcwise_core/calcwise_core.dart' hide HistoryEntry;

class HistoryDetailScreen extends StatelessWidget {
  final HistoryEntry entry;

  const HistoryDetailScreen({super.key, required this.entry});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: isSpanishNotifier,
      builder: (context, useAlt, _) {
        final es = FlavorConfig.isUS && useAlt;
        final fr = FlavorConfig.isCA && useAlt;

        final currencySymbol =
            entry.flavor == 'uk' ? '£' : (entry.flavor == 'ca' ? 'CA\$' : '\$');
        final fmtMoney =
            NumberFormat.currency(symbol: currencySymbol, decimalDigits: 2);
        final fmtDate = DateFormat('MMMM d, yyyy  HH:mm');

        final l = _Labels(fr: fr, es: es);
        final r = entry.result;

        final federalLabel = entry.flavor == 'uk'
            ? (fr ? 'Impôt sur le revenu' : 'Income Tax')
            : (fr
                ? 'Impôt fédéral'
                : (es ? 'Impuesto federal' : 'Federal Tax'));
        final ficaLabel = entry.flavor == 'us'
            ? 'FICA (SS + Medicare)'
            : (entry.flavor == 'uk'
                ? 'National Insurance'
                : (fr ? 'RPC + AE' : 'CPP + EI'));
        final stateLabel = entry.flavor == 'us'
            ? (es ? 'Impuesto estatal' : 'State Tax')
            : (fr ? 'Impôt provincial' : 'Provincial Tax');

        return Scaffold(
          appBar: AppBar(
            title: Text(l.title),
            actions: [
              ValueListenableBuilder<bool>(
                valueListenable: freemiumService.hasFullAccessNotifier,
                builder: (context, isPremium, _) => IconButton(
                  icon: Icon(isPremium
                      ? Icons.picture_as_pdf_rounded
                      : Icons.lock_outline_rounded),
                  tooltip: l.exportPdf,
                  onPressed: () => _exportPdf(context, r, fr, es),
                ),
              ),
              IconButton(
                icon: Icon(Icons.share_rounded),
                tooltip: l.share,
                onPressed: () {
                  analyticsService.logShareResult();
                  _shareText(context, r, fmtMoney, fmtDate, l, fr, es);
                },
              ),
            ],
          ),
          body: Column(
            children: [
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  children: [
                    // Date & region
                    _DetailCard(
                        icon: Icons.schedule,
                        label: l.date,
                        value: fmtDate.format(entry.timestamp)),
                    if (entry.region.isNotEmpty) ...[
                      SizedBox(height: AppSpacing.sm),
                      _DetailCard(
                          icon: Icons.location_on_rounded,
                          label: l.region,
                          value: entry.region),
                    ],
                    SizedBox(height: AppSpacing.lg),

                    // Salary breakdown
                    _SectionHeader(l.breakdown),
                    SizedBox(height: AppSpacing.sm),
                    _DetailCard(
                        icon: Icons.account_balance_wallet_rounded,
                        label: l.grossAnnual,
                        value: fmtMoney.format(r.grossAnnual),
                        valueColor: AppTheme.primary),
                    SizedBox(height: AppSpacing.sm),
                    _DetailCard(
                        icon: Icons.trending_down,
                        label: federalLabel,
                        value: fmtMoney.format(r.federalTax),
                        valueColor: CalcwiseSemanticColors.error(
                            Theme.of(context).brightness)),
                    if (r.ficaTax > 0) ...[
                      SizedBox(height: AppSpacing.sm),
                      _DetailCard(
                          icon: Icons.trending_down,
                          label: ficaLabel,
                          value: fmtMoney.format(r.ficaTax),
                          valueColor: CalcwiseSemanticColors.warnIcon),
                    ],
                    if (entry.flavor != 'uk' && r.stateTax > 0) ...[
                      SizedBox(height: AppSpacing.sm),
                      _DetailCard(
                          icon: Icons.trending_down,
                          label: stateLabel,
                          value: fmtMoney.format(r.stateTax),
                          valueColor: CalcwiseSemanticColors.alert(
                              Theme.of(context).brightness)),
                    ],
                    SizedBox(height: AppSpacing.sm),
                    _DetailCard(
                        icon: Icons.receipt_long_rounded,
                        label: l.totalTax,
                        value: fmtMoney.format(r.totalTax),
                        valueColor: CalcwiseSemanticColors.error(
                            Theme.of(context).brightness)),
                    SizedBox(height: AppSpacing.sm),
                    _DetailCard(
                        icon: Icons.percent,
                        label: l.effectiveRate,
                        value: '${r.effectiveRate.toStringAsFixed(1)}%',
                        valueColor: CalcwiseSemanticColors.error(
                            Theme.of(context).brightness)),
                    SizedBox(height: AppSpacing.lg),

                    // Net pay breakdown
                    _SectionHeader(l.netPay),
                    SizedBox(height: AppSpacing.sm),
                    _DetailCard(
                        icon: Icons.star_rounded,
                        label: l.netAnnual,
                        value: fmtMoney.format(r.netAnnual),
                        valueColor: AppTheme.success),
                    SizedBox(height: AppSpacing.sm),
                    _DetailCard(
                        icon: Icons.calendar_month_rounded,
                        label: l.netMonthly,
                        value: fmtMoney.format(r.netMonthly),
                        valueColor: AppTheme.success),
                    SizedBox(height: AppSpacing.sm),
                    _DetailCard(
                        icon: Icons.date_range_rounded,
                        label: l.netBiWeekly,
                        value: fmtMoney.format(r.netBiWeekly)),
                    SizedBox(height: AppSpacing.sm),
                    _DetailCard(
                        icon: Icons.view_week_rounded,
                        label: l.netWeekly,
                        value: fmtMoney.format(r.netWeekly)),
                    SizedBox(height: AppSpacing.lg),

                    // PDF export button — always visible, PaywallHard-gated
                    ValueListenableBuilder<bool>(
                      valueListenable: freemiumService.hasFullAccessNotifier,
                      builder: (context, isPremium, _) => SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          icon: Icon(isPremium
                              ? Icons.picture_as_pdf_rounded
                              : Icons.lock_outline_rounded),
                          label: Text(l.exportPdf),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppTheme.primary,
                            side: BorderSide(color: AppTheme.primary),
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                                borderRadius:
                                    BorderRadius.circular(AppRadius.xl)),
                          ),
                          onPressed: () => _exportPdf(context, r, fr, es),
                        ),
                      ),
                    ),
                    SizedBox(height: AppSpacing.lg),
                  ],
                ),
              ),
              ValueListenableBuilder<bool>(
                valueListenable: freemiumService.hasFullAccessNotifier,
                builder: (_, isPremium, __) => isPremium
                    ? const SizedBox.shrink()
                    : const CalcwiseAdFooter(),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _exportPdf(
      BuildContext context, SalaryResult r, bool fr, bool es) async {
    if (!freemiumService.hasFullAccess) {
      await PdfExportService.showUnlockOrPay(
        context,
        () => PdfExportService.exportSalary(
          context: context,
          grossAnnual: r.grossAnnual,
          federalTax: r.federalTax,
          stateTax: r.stateTax,
          socialSecurity: entry.flavor == 'us' ? r.ficaTax * 0.635 : 0,
          medicare: entry.flavor == 'us' ? r.ficaTax * 0.365 : 0,
          totalDeductions: r.totalTax,
          netAnnual: r.netAnnual,
          netMonthly: r.netMonthly,
          netBiweekly: r.netBiWeekly,
          netHourly: r.netAnnual / 2080,
          country: entry.flavor.toUpperCase(),
          state: entry.region,
          fr: fr,
          es: es,
        ),
      );
      return;
    }
    await PdfExportService.exportSalary(
      context: context,
      grossAnnual: r.grossAnnual,
      federalTax: r.federalTax,
      stateTax: r.stateTax,
      socialSecurity: entry.flavor == 'us' ? r.ficaTax * 0.635 : 0,
      medicare: entry.flavor == 'us' ? r.ficaTax * 0.365 : 0,
      totalDeductions: r.totalTax,
      netAnnual: r.netAnnual,
      netMonthly: r.netMonthly,
      netBiweekly: r.netBiWeekly,
      netHourly: r.netAnnual / 2080,
      country: entry.flavor.toUpperCase(),
      state: entry.region,
      fr: fr,
      es: es,
    );
    analyticsService.logPdfExported();
  }

  void _shareText(
    BuildContext context,
    SalaryResult r,
    NumberFormat fmtMoney,
    DateFormat fmtDate,
    _Labels l,
    bool fr,
    bool es,
  ) {
    final buf = StringBuffer();
    buf.writeln('${l.title} — ${fmtDate.format(entry.timestamp)}');
    if (entry.region.isNotEmpty) buf.writeln('${l.region}: ${entry.region}');
    buf.writeln('${l.grossAnnual}: ${fmtMoney.format(r.grossAnnual)}');
    buf.writeln('${l.totalTax}: ${fmtMoney.format(r.totalTax)}');
    buf.writeln('${l.effectiveRate}: ${r.effectiveRate.toStringAsFixed(1)}%');
    buf.writeln('${l.netAnnual}: ${fmtMoney.format(r.netAnnual)}');
    buf.writeln('${l.netMonthly}: ${fmtMoney.format(r.netMonthly)}');

    final subject = fr
        ? 'Résumé de salaire'
        : (es ? 'Resumen de salario' : 'Salary Summary');
    Share.share(buf.toString(), subject: subject);
  }
}

// ─── Section header ───────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final String text;
  const _SectionHeader(this.text);

  @override
  Widget build(BuildContext context) => Text(
        text,
        style: TextStyle(
            fontSize: AppTextSize.body,
            fontWeight: FontWeight.w600,
            color: AppTheme.labelGray),
      );
}

// ─── Detail card widget ───────────────────────────────────────────────────────

class _DetailCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color? valueColor;

  const _DetailCard({
    required this.icon,
    required this.label,
    required this.value,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg, vertical: AppSpacing.mdPlus),
        child: Row(children: [
          Icon(icon, size: 20, color: AppTheme.primary),
          SizedBox(width: AppSpacing.md),
          Expanded(
            child: Text(label,
                style: TextStyle(
                    fontSize: AppTextSize.md, color: AppTheme.labelGray)),
          ),
          Text(value,
              style: TextStyle(
                  fontSize: AppTextSize.body,
                  fontWeight: FontWeight.w600,
                  color: valueColor)),
        ]),
      ),
    );
  }
}

// ─── Labels ───────────────────────────────────────────────────────────────────

class _Labels {
  final bool fr, es;
  _Labels({required this.fr, required this.es});

  String get title => fr
      ? 'Détail du calcul'
      : (es ? 'Detalle del cálculo' : 'Calculation Detail');
  String get share => fr ? 'Partager' : (es ? 'Compartir' : 'Share');
  String get exportPdf =>
      fr ? 'Exporter PDF' : (es ? 'Exportar PDF' : 'Export PDF');
  String get date => fr ? 'Date' : (es ? 'Fecha' : 'Date');
  String get region => fr ? 'Province' : (es ? 'Estado' : 'Region');
  String get breakdown =>
      fr ? 'Répartition fiscale' : (es ? 'Desglose fiscal' : 'Tax Breakdown');
  String get netPay => fr ? 'Salaire net' : (es ? 'Salario neto' : 'Net Pay');
  String get grossAnnual => fr
      ? 'Salaire brut annuel'
      : (es ? 'Salario bruto anual' : 'Gross Annual Salary');
  String get totalTax =>
      fr ? 'Total impôts' : (es ? 'Total impuestos' : 'Total Tax');
  String get effectiveRate =>
      fr ? 'Taux effectif' : (es ? 'Tasa efectiva' : 'Effective Tax Rate');
  String get netAnnual =>
      fr ? 'Net annuel' : (es ? 'Neto anual' : 'Annual Net');
  String get netMonthly => fr ? 'Mensuel' : (es ? 'Mensual' : 'Monthly Net');
  String get netBiWeekly =>
      fr ? 'Bimensuel' : (es ? 'Quincenal' : 'Bi-Weekly Net');
  String get netWeekly => fr ? 'Hebdomadaire' : (es ? 'Semanal' : 'Weekly Net');
}
