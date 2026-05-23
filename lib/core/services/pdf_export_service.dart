import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../flavor_config.dart';
import '../freemium/iap_service.dart';
import '../theme/app_theme.dart';
import '../../main.dart';
import 'package:calcwise_core/calcwise_core.dart';

const _navy = PdfColor(0.043, 0.275, 0.490); // SalaryApp deep blue
const _green = PdfColor(0.110, 0.627, 0.384); // accent green
const _light = PdfColor(0.933, 0.976, 0.953);

class PdfExportService {
  static final _cur2 =
      NumberFormat.currency(locale: 'en_US', symbol: '\$', decimalDigits: 2);
  static final _cur0 =
      NumberFormat.currency(locale: 'en_US', symbol: '\$', decimalDigits: 0);
  static final _date = DateFormat('MMMM d, yyyy');

  // ── Public entry point ────────────────────────────────────────────────────

  static Future<void> exportSalary({
    required BuildContext context,
    required double grossAnnual,
    required double federalTax,
    required double stateTax,
    required double socialSecurity,
    required double medicare,
    required double totalDeductions,
    required double netAnnual,
    required double netMonthly,
    required double netBiweekly,
    required double netHourly,
    required String country,
    required String state,
  }) async {
    final pdf = pw.Document();

    pdf.addPage(pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.fromLTRB(36, 36, 36, 28),
      build: (_) => _buildSummaryPage(
        grossAnnual: grossAnnual,
        federalTax: federalTax,
        stateTax: stateTax,
        socialSecurity: socialSecurity,
        medicare: medicare,
        totalDeductions: totalDeductions,
        netAnnual: netAnnual,
        netMonthly: netMonthly,
        netBiweekly: netBiweekly,
        netHourly: netHourly,
        country: country,
        state: state,
      ),
    ));

    await Printing.sharePdf(
      bytes: await pdf.save(),
      filename:
          'SalaryCalc_${grossAnnual.round()}_${DateTime.now().millisecondsSinceEpoch}.pdf',
    );
  }

  static pw.Widget _buildSummaryPage({
    required double grossAnnual,
    required double federalTax,
    required double stateTax,
    required double socialSecurity,
    required double medicare,
    required double totalDeductions,
    required double netAnnual,
    required double netMonthly,
    required double netBiweekly,
    required double netHourly,
    required String country,
    required String state,
  }) {
    final now = DateTime.now();
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          crossAxisAlignment: pw.CrossAxisAlignment.end,
          children: [
            pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text('Salary Calculator',
                      style: pw.TextStyle(
                          fontSize: AppTextSize.title,
                          fontWeight: pw.FontWeight.bold,
                          color: _navy)),
                  pw.Text(
                      'Take-Home Pay Report · ${state.toUpperCase()}, ${country.toUpperCase()}',
                      style: const pw.TextStyle(
                          fontSize: AppTextSize.xs, color: PdfColors.grey700)),
                ]),
            pw.Text(_date.format(now),
                style:
                    const pw.TextStyle(fontSize: 9, color: PdfColors.grey600)),
          ],
        ),
        pw.Container(
            height: 2,
            color: _navy,
            margin: const pw.EdgeInsets.only(top: 6, bottom: 14)),
        pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          pw.Expanded(
              child: pw.Column(children: [
            _sectionBox('GROSS INCOME', [
              _row2('Annual Gross', _cur0.format(grossAnnual),
                  bold: true, color: _navy),
              _row2('Monthly Gross', _cur0.format(grossAnnual / 12)),
              _row2('Bi-Weekly Gross', _cur0.format(grossAnnual / 26)),
              _row2('Hourly (40hr/wk)', _cur2.format(grossAnnual / 2080)),
            ]),
            pw.SizedBox(height: 10),
            _sectionBox('DEDUCTIONS', [
              _row2('Federal Income Tax', _cur0.format(federalTax)),
              _row2('State Income Tax', _cur0.format(stateTax)),
              _row2('Social Security', _cur0.format(socialSecurity)),
              _row2('Medicare', _cur0.format(medicare)),
              pw.Divider(color: PdfColors.grey300, height: 6),
              _row2('Total Deductions', _cur0.format(totalDeductions),
                  bold: true),
            ]),
          ])),
          pw.SizedBox(width: 14),
          pw.Expanded(
              child: pw.Column(children: [
            _sectionBox('TAKE-HOME PAY', [
              _row2('Annual Net', _cur0.format(netAnnual),
                  bold: true, color: _green),
              _row2('Monthly Net', _cur0.format(netMonthly),
                  bold: true, color: _navy),
              _row2('Bi-Weekly Net', _cur0.format(netBiweekly)),
              _row2('Hourly Net', _cur2.format(netHourly)),
            ]),
            pw.SizedBox(height: 10),
            _effectiveRateBar(grossAnnual, totalDeductions),
          ])),
        ]),
        pw.Spacer(),
        _footerNote(),
      ],
    );
  }

  static pw.Widget _effectiveRateBar(double gross, double deductions) {
    final effectiveRate = gross > 0 ? deductions / gross : 0.0;
    final takeHome = 1.0 - effectiveRate;
    return _sectionBox('EFFECTIVE TAX RATE', [
      pw.SizedBox(height: 6),
      pw.Row(children: [
        pw.Expanded(
          flex: (takeHome * 100).round().clamp(1, 99),
          child: pw.Container(
              height: 14,
              color: _green,
              child: pw.Center(
                  child: pw.Text(
                '${(takeHome * 100).toStringAsFixed(0)}% keep',
                style: pw.TextStyle(
                    fontSize: 7,
                    color: PdfColors.white,
                    fontWeight: pw.FontWeight.bold),
              ))),
        ),
        pw.Expanded(
          flex: (effectiveRate * 100).round().clamp(1, 99),
          child: pw.Container(
              height: 14,
              color: _navy,
              child: pw.Center(
                  child: pw.Text(
                '${(effectiveRate * 100).toStringAsFixed(1)}% tax',
                style: pw.TextStyle(
                    fontSize: 7,
                    color: PdfColors.white,
                    fontWeight: pw.FontWeight.bold),
              ))),
        ),
      ]),
    ]);
  }

  static pw.Widget _footerNote() => pw.Column(children: [
        pw.Divider(color: PdfColors.grey300, height: 12),
        pw.Text(
            'Generated by Salary Calculator · For illustration purposes only. Not financial advice.',
            style: const pw.TextStyle(fontSize: 7, color: PdfColors.grey500)),
      ]);

  static pw.Widget _sectionBox(String title, List<pw.Widget> rows) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Container(
            width: double.infinity,
            padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            color: _navy,
            child: pw.Text(title,
                style: pw.TextStyle(
                    fontSize: 8,
                    fontWeight: pw.FontWeight.bold,
                    color: PdfColors.white)),
          ),
          pw.Container(
            padding: const pw.EdgeInsets.all(AppSpacing.sm),
            decoration: pw.BoxDecoration(
                border: pw.Border.all(color: PdfColors.grey300, width: 0.5)),
            child: pw.Column(children: rows),
          ),
        ],
      );

  static pw.Widget _row2(String label, String value,
          {bool bold = false, PdfColor? color}) =>
      pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 2.5),
        child: pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(label,
                  style: const pw.TextStyle(
                      fontSize: 9, color: PdfColors.grey800)),
              pw.Text(value,
                  style: pw.TextStyle(
                      fontSize: 9,
                      fontWeight:
                          bold ? pw.FontWeight.bold : pw.FontWeight.normal,
                      color: color ?? PdfColors.black)),
            ]),
      );

  // ── Unlock sheet ──────────────────────────────────────────────────────────

  static Future<void> showUnlockOrPay(
    BuildContext context,
    Future<void> Function() onExport,
  ) async {
    await showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => _PdfUnlockSheet(onExport: onExport),
    );
  }
}

class _PdfUnlockSheet extends StatefulWidget {
  final Future<void> Function() onExport;
  const _PdfUnlockSheet({required this.onExport});
  @override
  State<_PdfUnlockSheet> createState() => _PdfUnlockSheetState();
}

class _PdfUnlockSheetState extends State<_PdfUnlockSheet> {
  bool _loading = false;
  Future<void> _watchAd() async {
    setState(() => _loading = true);
    final earned = await adService.showRewarded();
    if (!mounted) return;
    setState(() => _loading = false);
    if (earned) {
      Navigator.pop(context);
      await widget.onExport();
    } else {
      final msg = !isSpanishNotifier.value
          ? 'Ad not available. Try again later.'
          : FlavorConfig.isCA
              ? 'Pub non disponible. Réessaie plus tard.'
              : 'Anuncio no disponible. Inténtalo más tarde.';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final adReady = adService.isRewardedReady;
    final isAlt =
        isSpanishNotifier.value; // true = FR (CA flavor) or ES (US flavor)
    final isFr = FlavorConfig.isCA;
    final exportLabel =
        isAlt ? (isFr ? 'Exporter PDF' : 'Exportar PDF') : 'Export PDF';
    final subtitleLabel = isAlt
        ? (isFr
            ? 'Choisissez comment débloquer l\'export'
            : 'Elige cómo desbloquear la exportación')
        : 'Choose how to unlock PDF export';
    final watchLabel = isAlt
        ? (isFr ? 'Regarder une courte vidéo' : 'Ver un video corto')
        : 'Watch a short video';
    final freeLabel = isAlt
        ? (isFr ? 'Exporter une fois — gratuit' : 'Exportar una vez — gratis')
        : 'Export once — free';
    final premiumLabel = isAlt
        ? (isFr
            ? 'Premium — \$3.99 (illimité)'
            : 'Premium — \$3.99 (ilimitado)')
        : 'Premium — \$3.99 (unlimited)';
    final notNowLabel = isAlt ? (isFr ? 'Plus tard' : 'Ahora no') : 'Not now';
    return Padding(
      padding: EdgeInsets.only(
          left: 24,
          right: 24,
          top: 12,
          bottom: MediaQuery.of(context).viewInsets.bottom + 28),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Center(
            child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                    color: CalcwiseTheme.of(context).cardBorder,
                    borderRadius: BorderRadius.circular(2)))),
        const SizedBox(height: 20),
        Icon(Icons.picture_as_pdf_rounded, size: 36, color: AppTheme.primary),
        const SizedBox(height: 12),
        Text(exportLabel,
            style: const TextStyle(
                fontSize: AppTextSize.subtitle, fontWeight: FontWeight.bold)),
        const SizedBox(height: 6),
        Text(subtitleLabel,
            style: TextStyle(
                fontSize: AppTextSize.md, color: CalcwiseTheme.of(context).textSecondary)),
        const SizedBox(height: 24),
        Opacity(
          opacity: adReady ? 1.0 : 0.45,
          child: InkWell(
            onTap: (adReady && !_loading) ? _watchAd : null,
            borderRadius: BorderRadius.circular(AppRadius.xl),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                  border: Border.all(
                      color: AppTheme.primary.withValues(alpha: 0.3)),
                  borderRadius: BorderRadius.circular(AppRadius.xl)),
              child: Row(children: [
                Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                        color: AppTheme.primary.withValues(alpha: 0.1),
                        shape: BoxShape.circle),
                    child: Icon(Icons.play_circle_outline,
                        color: AppTheme.primary, size: 24)),
                const SizedBox(width: 14),
                Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      Text(watchLabel,
                          style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: AppTextSize.bodyMd)),
                      const SizedBox(height: 2),
                      Text(freeLabel,
                          style: TextStyle(
                              color: CalcwiseTheme.of(context).textSecondary,
                              fontSize: AppTextSize.md)),
                    ])),
                if (_loading)
                  const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2))
                else
                  Icon(Icons.chevron_right_rounded,
                      color: CalcwiseTheme.of(context).textSecondary),
              ]),
            ),
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () {
                Navigator.pop(context);
                IAPService.instance.buy();
              },
              icon: const Icon(Icons.workspace_premium, size: 18),
              label: Text(premiumLabel,
                  style: const TextStyle(fontWeight: FontWeight.bold)),
              style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppRadius.xl))),
            )),
        const SizedBox(height: 10),
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(notNowLabel,
                style: TextStyle(color: CalcwiseTheme.of(context).textSecondary))),
      ]),
    );
  }
}
