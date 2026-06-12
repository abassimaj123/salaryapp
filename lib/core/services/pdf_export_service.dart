import 'dart:isolate';
import 'dart:math' show pow;
import 'dart:typed_data';

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

// ── Isolate param classes ─────────────────────────────────────────────────────
// Only sendable types: String, int, double, bool, List, Map, Uint8List

class _SalaryPdfParams {
  final double grossAnnual, federalTax, stateTax, socialSecurity, medicare,
      totalDeductions, netAnnual, netMonthly, netBiweekly, netHourly;
  final String country, state;
  final bool fr, es;
  const _SalaryPdfParams({
    required this.grossAnnual,
    required this.federalTax,
    required this.stateTax,
    required this.socialSecurity,
    required this.medicare,
    required this.totalDeductions,
    required this.netAnnual,
    required this.netMonthly,
    required this.netBiweekly,
    required this.netHourly,
    required this.country,
    required this.state,
    required this.fr,
    required this.es,
  });
}

class _BonusPdfParams {
  final double grossAnnual, bonusAmount;
  final double usFlatFederalTax, usFlatStateTax, usFlatTotalTax, usFlatNetBonus;
  final double usAggregateTotalTax, usAggregateNetBonus;
  final String betterMethod, usState;
  final double caFederalTax, caProvincialTax, caTotalTax, caNetBonus;
  final String caProvince;
  final double ukExtraTax, ukNetBonus;
  final bool fr, es;
  const _BonusPdfParams({
    required this.grossAnnual,
    required this.bonusAmount,
    required this.usFlatFederalTax,
    required this.usFlatStateTax,
    required this.usFlatTotalTax,
    required this.usFlatNetBonus,
    required this.usAggregateTotalTax,
    required this.usAggregateNetBonus,
    required this.betterMethod,
    required this.usState,
    required this.caFederalTax,
    required this.caProvincialTax,
    required this.caTotalTax,
    required this.caNetBonus,
    required this.caProvince,
    required this.ukExtraTax,
    required this.ukNetBonus,
    required this.fr,
    required this.es,
  });
}

class _TaxBreakdownPdfParams {
  final double grossAnnual;
  // Bracket fields serialized as parallel lists (records not sendable)
  final List<double> bMin, bMax, bRate, bAmountInBracket, bTaxOwed;
  final bool fr, es;
  const _TaxBreakdownPdfParams({
    required this.grossAnnual,
    required this.bMin,
    required this.bMax,
    required this.bRate,
    required this.bAmountInBracket,
    required this.bTaxOwed,
    required this.fr,
    required this.es,
  });
}

class _RaisePdfParams {
  final double currentSalary, newAnnual, raisePct, raiseGross, raiseNet,
      taxIncrease, oldMonthlyNet, newMonthlyNet, effectivePct, marginalRate;
  final bool fr, es;
  const _RaisePdfParams({
    required this.currentSalary,
    required this.newAnnual,
    required this.raisePct,
    required this.raiseGross,
    required this.raiseNet,
    required this.taxIncrease,
    required this.oldMonthlyNet,
    required this.newMonthlyNet,
    required this.effectivePct,
    required this.marginalRate,
    required this.fr,
    required this.es,
  });
}

class _RetirementPdfParams {
  final double grossIncome, contribution, contributionLimit, taxSaving, netCost,
      takeHomeChangeMonthly, projectedValue30yr, utilizationPct;
  final bool isMaxed, age50Plus, es;
  const _RetirementPdfParams({
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
    required this.es,
  });
}

class _RrspPdfParams {
  final double grossIncome, rrspRoom, contribution, taxSaving, netCost,
      remainingRoom, marginalRate;
  final String bracketLabel, province;
  final bool fr;
  const _RrspPdfParams({
    required this.grossIncome,
    required this.rrspRoom,
    required this.contribution,
    required this.taxSaving,
    required this.netCost,
    required this.remainingRoom,
    required this.marginalRate,
    required this.bracketLabel,
    required this.province,
    required this.fr,
  });
}

class _SalaryComparisonPdfParams {
  final double grossA, grossB, netAnnualA, netAnnualB, netMonthlyA, netMonthlyB;
  final double federalTaxA, federalTaxB, ficaTaxA, ficaTaxB, stateTaxA, stateTaxB;
  final double totalTaxA, totalTaxB, effectiveRateA, effectiveRateB;
  final String regionA, regionB;
  final bool fr, es;
  const _SalaryComparisonPdfParams({
    required this.grossA,
    required this.grossB,
    required this.netAnnualA,
    required this.netAnnualB,
    required this.netMonthlyA,
    required this.netMonthlyB,
    required this.federalTaxA,
    required this.federalTaxB,
    required this.ficaTaxA,
    required this.ficaTaxB,
    required this.stateTaxA,
    required this.stateTaxB,
    required this.totalTaxA,
    required this.totalTaxB,
    required this.effectiveRateA,
    required this.effectiveRateB,
    required this.regionA,
    required this.regionB,
    required this.fr,
    required this.es,
  });
}

// ── Top-level isolate functions ───────────────────────────────────────────────
// These run on a background isolate — no Flutter platform channel access.
// FlavorConfig uses const String.fromEnvironment so it is safe here.

Future<Uint8List> _buildSalaryPdfBytes(_SalaryPdfParams p) async {
  final pdf = pw.Document();
  pdf.addPage(pw.Page(
    pageFormat: PdfPageFormat.a4,
    margin: const pw.EdgeInsets.fromLTRB(36, 36, 36, 28),
    build: (_) => PdfExportService._buildSummaryPage(
      grossAnnual: p.grossAnnual,
      federalTax: p.federalTax,
      stateTax: p.stateTax,
      socialSecurity: p.socialSecurity,
      medicare: p.medicare,
      totalDeductions: p.totalDeductions,
      netAnnual: p.netAnnual,
      netMonthly: p.netMonthly,
      netBiweekly: p.netBiweekly,
      netHourly: p.netHourly,
      country: p.country,
      state: p.state,
      fr: p.fr,
      es: p.es,
    ),
  ));
  return await pdf.save();
}

Future<Uint8List> _buildBonusPdfBytes(_BonusPdfParams p) async {
  final pdf = pw.Document();
  pdf.addPage(pw.Page(
    pageFormat: PdfPageFormat.a4,
    margin: const pw.EdgeInsets.fromLTRB(36, 36, 36, 28),
    build: (_) => PdfExportService._buildBonusPage(
      grossAnnual: p.grossAnnual,
      bonusAmount: p.bonusAmount,
      usFlatFederalTax: p.usFlatFederalTax,
      usFlatStateTax: p.usFlatStateTax,
      usFlatTotalTax: p.usFlatTotalTax,
      usFlatNetBonus: p.usFlatNetBonus,
      usAggregateTotalTax: p.usAggregateTotalTax,
      usAggregateNetBonus: p.usAggregateNetBonus,
      betterMethod: p.betterMethod,
      usState: p.usState,
      caFederalTax: p.caFederalTax,
      caProvincialTax: p.caProvincialTax,
      caTotalTax: p.caTotalTax,
      caNetBonus: p.caNetBonus,
      caProvince: p.caProvince,
      ukExtraTax: p.ukExtraTax,
      ukNetBonus: p.ukNetBonus,
      fr: p.fr,
      es: p.es,
    ),
  ));
  return await pdf.save();
}

Future<Uint8List> _buildTaxBreakdownPdfBytes(_TaxBreakdownPdfParams p) async {
  // Reconstruct named-record list from parallel arrays
  final brackets = List.generate(p.bMin.length, (i) => (
    min: p.bMin[i],
    max: p.bMax[i],
    rate: p.bRate[i],
    amountInBracket: p.bAmountInBracket[i],
    taxOwed: p.bTaxOwed[i],
  ));
  final pdf = pw.Document();
  pdf.addPage(pw.Page(
    pageFormat: PdfPageFormat.a4,
    margin: const pw.EdgeInsets.fromLTRB(36, 36, 36, 28),
    build: (_) => PdfExportService._buildTaxBreakdownPage(
      grossAnnual: p.grossAnnual,
      brackets: brackets,
      fr: p.fr,
      es: p.es,
    ),
  ));
  return await pdf.save();
}

Future<Uint8List> _buildRaisePdfBytes(_RaisePdfParams p) async {
  final pdf = pw.Document();
  pdf.addPage(pw.Page(
    pageFormat: PdfPageFormat.a4,
    margin: const pw.EdgeInsets.fromLTRB(36, 36, 36, 28),
    build: (_) => PdfExportService._buildRaisePage(
      currentSalary: p.currentSalary,
      newAnnual: p.newAnnual,
      raisePct: p.raisePct,
      raiseGross: p.raiseGross,
      raiseNet: p.raiseNet,
      taxIncrease: p.taxIncrease,
      oldMonthlyNet: p.oldMonthlyNet,
      newMonthlyNet: p.newMonthlyNet,
      effectivePct: p.effectivePct,
      marginalRate: p.marginalRate,
      fr: p.fr,
      es: p.es,
    ),
  ));
  return await pdf.save();
}

Future<Uint8List> _buildRetirementPdfBytes(_RetirementPdfParams p) async {
  final pdf = pw.Document();
  pdf.addPage(pw.Page(
    pageFormat: PdfPageFormat.a4,
    margin: const pw.EdgeInsets.fromLTRB(36, 36, 36, 28),
    build: (_) => PdfExportService._buildRetirementPage(
      grossIncome: p.grossIncome,
      contribution: p.contribution,
      contributionLimit: p.contributionLimit,
      taxSaving: p.taxSaving,
      netCost: p.netCost,
      takeHomeChangeMonthly: p.takeHomeChangeMonthly,
      projectedValue30yr: p.projectedValue30yr,
      utilizationPct: p.utilizationPct,
      isMaxed: p.isMaxed,
      age50Plus: p.age50Plus,
      es: p.es,
    ),
  ));
  return await pdf.save();
}

Future<Uint8List> _buildRrspPdfBytes(_RrspPdfParams p) async {
  final pdf = pw.Document();
  pdf.addPage(pw.Page(
    pageFormat: PdfPageFormat.a4,
    margin: const pw.EdgeInsets.fromLTRB(36, 36, 36, 28),
    build: (_) => PdfExportService._buildRrspPage(
      grossIncome: p.grossIncome,
      rrspRoom: p.rrspRoom,
      contribution: p.contribution,
      taxSaving: p.taxSaving,
      netCost: p.netCost,
      remainingRoom: p.remainingRoom,
      marginalRate: p.marginalRate,
      bracketLabel: p.bracketLabel,
      province: p.province,
      fr: p.fr,
    ),
  ));
  return await pdf.save();
}

Future<Uint8List> _buildSalaryComparisonPdfBytes(
    _SalaryComparisonPdfParams p) async {
  final pdf = pw.Document();
  pdf.addPage(pw.Page(
    pageFormat: PdfPageFormat.a4,
    margin: const pw.EdgeInsets.fromLTRB(36, 36, 36, 28),
    build: (_) => PdfExportService._buildSalaryComparisonPage(
      grossA: p.grossA,
      grossB: p.grossB,
      netAnnualA: p.netAnnualA,
      netAnnualB: p.netAnnualB,
      netMonthlyA: p.netMonthlyA,
      netMonthlyB: p.netMonthlyB,
      federalTaxA: p.federalTaxA,
      federalTaxB: p.federalTaxB,
      ficaTaxA: p.ficaTaxA,
      ficaTaxB: p.ficaTaxB,
      stateTaxA: p.stateTaxA,
      stateTaxB: p.stateTaxB,
      totalTaxA: p.totalTaxA,
      totalTaxB: p.totalTaxB,
      effectiveRateA: p.effectiveRateA,
      effectiveRateB: p.effectiveRateB,
      regionA: p.regionA,
      regionB: p.regionB,
      fr: p.fr,
      es: p.es,
    ),
  ));
  return await pdf.save();
}

class PdfExportService {
  static NumberFormat get _cur2 => NumberFormat.currency(
      locale: FlavorConfig.locale,
      symbol: FlavorConfig.currencySymbol,
      decimalDigits: 2);
  static NumberFormat get _cur0 => NumberFormat.currency(
      locale: FlavorConfig.locale,
      symbol: FlavorConfig.currencySymbol,
      decimalDigits: 0);
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
    bool fr = false,
    bool es = false,
  }) async {
    final bytes = await Isolate.run(() => _buildSalaryPdfBytes(_SalaryPdfParams(
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
          fr: fr,
          es: es,
        )));

    await Printing.sharePdf(
      bytes: bytes,
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
    bool fr = false,
    bool es = false,
  }) {
    final now = DateTime.now();
    final isCA = country.toLowerCase() == 'ca';

    // ── Localized labels ─────────────────────────────────────────────────────
    final lTitle =
        es ? 'Calculadora de Salario' : fr ? 'Calculatrice de Salaire' : 'Salary Calculator';
    final lSubtitle =
        es ? 'Informe de Salario Neto' : fr ? 'Rapport de Salaire Net' : 'Take-Home Pay Report';
    final lGrossIncome =
        es ? 'INGRESO BRUTO' : fr ? 'REVENU BRUT' : 'GROSS INCOME';
    final lAnnualGross =
        es ? 'Bruto Anual' : fr ? 'Annuel Brut' : 'Annual Gross';
    final lMonthlyGross =
        es ? 'Bruto Mensual' : fr ? 'Mensuel Brut' : 'Monthly Gross';
    final lBiWeeklyGross =
        es ? 'Bruto Quincenal' : fr ? 'Bihebdomadaire Brut' : 'Bi-Weekly Gross';
    final lHourly =
        es ? 'Por Hora (40h/sem)' : fr ? 'Horaire (40h/sem)' : 'Hourly (40hr/wk)';
    final lDeductions =
        es ? 'DEDUCCIONES' : fr ? 'RETENUES' : 'DEDUCTIONS';
    final lFederalTax = isCA
        ? (es ? 'Impuesto Federal' : fr ? 'Impôt fédéral' : 'Federal Income Tax')
        : (es ? 'Impuesto Federal' : 'Federal Income Tax');
    final lStateTax = es
        ? 'Impuesto Estatal'
        : fr
            ? 'Impôt provincial'
            : 'State/Provincial Income Tax';
    final lSocialSecurity = isCA
        ? (es ? 'RPC' : fr ? 'RPC' : 'CPP')
        : (es ? 'Seguro Social' : 'Social Security');
    final lMedicare = isCA ? (es ? 'AE' : fr ? 'AE' : 'EI') : 'Medicare';
    final lTotalDeductions =
        es ? 'Total Deducciones' : fr ? 'Total retenues' : 'Total Deductions';
    final lTakeHome =
        es ? 'SALARIO NETO' : fr ? 'SALAIRE NET' : 'TAKE-HOME PAY';
    final lAnnualNet =
        es ? 'Neto Anual' : fr ? 'Net annuel' : 'Annual Net';
    final lMonthlyNet =
        es ? 'Neto Mensual' : fr ? 'Mensuel net' : 'Monthly Net';
    final lBiWeeklyNet =
        es ? 'Neto Quincenal' : fr ? 'Bihebdomadaire net' : 'Bi-Weekly Net';
    final lHourlyNet =
        es ? 'Por Hora Neto' : fr ? 'Horaire net' : 'Hourly Net';
    final lEffectiveRate =
        es ? 'TASA EFECTIVA' : fr ? 'TAUX EFFECTIF' : 'EFFECTIVE TAX RATE';
    final lKeep = es ? '% retiene' : fr ? '% gardé' : '% keep';
    final lTax = es ? '% impuesto' : fr ? '% impôt' : '% tax';
    final lFooter = es
        ? 'Generado por Salary Calculator · Solo para fines ilustrativos.'
        : fr
            ? 'Généré par Calculatrice de Salaire · À titre indicatif seulement.'
            : 'Generated by Salary Calculator · For illustration purposes only. Not financial advice.';

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
                  pw.Text(lTitle,
                      style: pw.TextStyle(
                          fontSize: AppTextSize.title,
                          fontWeight: pw.FontWeight.bold,
                          color: _navy)),
                  pw.Text(
                      '$lSubtitle · ${state.toUpperCase()}, ${country.toUpperCase()}',
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
            _sectionBox(lGrossIncome, [
              _row2(lAnnualGross, _cur0.format(grossAnnual),
                  bold: true, color: _navy),
              _row2(lMonthlyGross, _cur0.format(grossAnnual / 12)),
              _row2(lBiWeeklyGross, _cur0.format(grossAnnual / 26)),
              _row2(lHourly, _cur2.format(grossAnnual / 2080)),
            ]),
            pw.SizedBox(height: 10),
            _sectionBox(lDeductions, [
              _row2(lFederalTax, _cur0.format(federalTax)),
              _row2(lStateTax, _cur0.format(stateTax)),
              _row2(lSocialSecurity, _cur0.format(socialSecurity)),
              _row2(lMedicare, _cur0.format(medicare)),
              pw.Divider(color: PdfColors.grey300, height: 6),
              _row2(lTotalDeductions, _cur0.format(totalDeductions),
                  bold: true),
            ]),
          ])),
          pw.SizedBox(width: 14),
          pw.Expanded(
              child: pw.Column(children: [
            _sectionBox(lTakeHome, [
              _row2(lAnnualNet, _cur0.format(netAnnual),
                  bold: true, color: _green),
              _row2(lMonthlyNet, _cur0.format(netMonthly),
                  bold: true, color: _navy),
              _row2(lBiWeeklyNet, _cur0.format(netBiweekly)),
              _row2(lHourlyNet, _cur2.format(netHourly)),
            ]),
            pw.SizedBox(height: 10),
            _effectiveRateBar(lEffectiveRate, lKeep, lTax, grossAnnual, totalDeductions),
          ])),
        ]),
        pw.Spacer(),
        _footerNote(lFooter),
      ],
    );
  }

  static pw.Widget _effectiveRateBar(
      String title, String keepLabel, String taxLabel, double gross, double deductions) {
    final effectiveRate = gross > 0 ? deductions / gross : 0.0;
    final takeHome = 1.0 - effectiveRate;
    return _sectionBox(title, [
      pw.SizedBox(height: 6),
      pw.Row(children: [
        pw.Expanded(
          flex: (takeHome * 100).round().clamp(1, 99),
          child: pw.Container(
              height: 14,
              color: _green,
              child: pw.Center(
                  child: pw.Text(
                '${(takeHome * 100).toStringAsFixed(0)}$keepLabel',
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
                '${(effectiveRate * 100).toStringAsFixed(1)}$taxLabel',
                style: pw.TextStyle(
                    fontSize: 7,
                    color: PdfColors.white,
                    fontWeight: pw.FontWeight.bold),
              ))),
        ),
      ]),
    ]);
  }

  static pw.Widget _footerNote(String text) => pw.Column(children: [
        pw.Divider(color: PdfColors.grey300, height: 12),
        pw.Text(text,
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

  // ── Bonus Calculator export ───────────────────────────────────────────────
  //
  // US:  bonusTax / netBonus = values for the better method (flat or aggregate).
  //      flatFederalTax / flatStateTax are only set when flat method is better.
  // CA:  caFederalTax / caProvincialTax / caTotalTax / caNetBonus.
  // UK:  ukExtraTax / ukNetBonus.

  static Future<void> exportBonus({
    required BuildContext context,
    required double grossAnnual,
    required double bonusAmount,
    // US params
    double usFlatFederalTax = 0,
    double usFlatStateTax = 0,
    double usFlatTotalTax = 0,
    double usFlatNetBonus = 0,
    double usAggregateTotalTax = 0,
    double usAggregateNetBonus = 0,
    String betterMethod = 'flat', // 'flat' or 'aggregate'
    String usState = '',
    // CA params
    double caFederalTax = 0,
    double caProvincialTax = 0,
    double caTotalTax = 0,
    double caNetBonus = 0,
    String caProvince = '',
    // UK params
    double ukExtraTax = 0,
    double ukNetBonus = 0,
    // locale
    bool fr = false,
    bool es = false,
  }) async {
    final bytes = await Isolate.run(() => _buildBonusPdfBytes(_BonusPdfParams(
          grossAnnual: grossAnnual,
          bonusAmount: bonusAmount,
          usFlatFederalTax: usFlatFederalTax,
          usFlatStateTax: usFlatStateTax,
          usFlatTotalTax: usFlatTotalTax,
          usFlatNetBonus: usFlatNetBonus,
          usAggregateTotalTax: usAggregateTotalTax,
          usAggregateNetBonus: usAggregateNetBonus,
          betterMethod: betterMethod,
          usState: usState,
          caFederalTax: caFederalTax,
          caProvincialTax: caProvincialTax,
          caTotalTax: caTotalTax,
          caNetBonus: caNetBonus,
          caProvince: caProvince,
          ukExtraTax: ukExtraTax,
          ukNetBonus: ukNetBonus,
          fr: fr,
          es: es,
        )));
    await Printing.sharePdf(
      bytes: bytes,
      filename:
          'BonusCalc_${bonusAmount.round()}_${DateTime.now().millisecondsSinceEpoch}.pdf',
    );
  }

  static pw.Widget _buildBonusPage({
    required double grossAnnual,
    required double bonusAmount,
    double usFlatFederalTax = 0,
    double usFlatStateTax = 0,
    double usFlatTotalTax = 0,
    double usFlatNetBonus = 0,
    double usAggregateTotalTax = 0,
    double usAggregateNetBonus = 0,
    String betterMethod = 'flat',
    String usState = '',
    double caFederalTax = 0,
    double caProvincialTax = 0,
    double caTotalTax = 0,
    double caNetBonus = 0,
    String caProvince = '',
    double ukExtraTax = 0,
    double ukNetBonus = 0,
    bool fr = false,
    bool es = false,
  }) {
    final now = DateTime.now();
    final isCA = FlavorConfig.isCA;
    final isUK = FlavorConfig.isUK;

    // ── Localized labels ──────────────────────────────────────────────────────
    final lTitle = es
        ? 'Calculadora de Bonificación'
        : fr
            ? 'Calculateur de Prime'
            : 'Bonus Calculator';
    final lSubtitle = es
        ? 'Informe de Prima Neta'
        : fr
            ? 'Rapport de Prime Nette'
            : 'Net Bonus Report';
    final lRegionValue = isCA ? caProvince : isUK ? 'UK' : usState;
    final lInputs = es ? 'ENTRADAS' : fr ? 'PARAMÈTRES' : 'INPUTS';
    final lBaseSalary =
        es ? 'Salario anual bruto' : fr ? 'Salaire annuel brut' : 'Annual Gross Salary';
    final lGrossBonus =
        es ? 'Prima bruta' : fr ? 'Prime brute' : 'Gross Bonus';
    final lResults = es ? 'RESULTADOS' : fr ? 'RÉSULTATS' : 'RESULTS';
    final lNetBonus =
        es ? 'Prima neta' : fr ? 'Prime nette' : 'Net Bonus Pay';
    final lEffRate = es
        ? 'Tasa efectiva sobre la prima'
        : fr
            ? 'Taux effectif sur la prime'
            : 'Effective Rate on Bonus';
    final lFooter = es
        ? 'Generado por Salary Calculator · Solo para fines ilustrativos.'
        : fr
            ? 'Généré par Calculatrice de Salaire · À titre indicatif seulement.'
            : 'Generated by Salary Calculator · For illustration purposes only. Not financial advice.';

    // ── Build result rows based on flavor ─────────────────────────────────────
    final List<pw.Widget> resultRows;
    final double taxOnBonus;
    final double netBonus;

    if (isUK) {
      taxOnBonus = ukExtraTax;
      netBonus = ukNetBonus;
      final effRate = bonusAmount > 0 ? taxOnBonus / bonusAmount : 0.0;
      resultRows = [
        _row2('Tax & NI on Bonus', _cur2.format(taxOnBonus)),
        _row2(lNetBonus, _cur2.format(netBonus), bold: true, color: _green),
        _row2(lEffRate, '${(effRate * 100).toStringAsFixed(1)}%'),
      ];
    } else if (isCA) {
      taxOnBonus = caTotalTax;
      netBonus = caNetBonus;
      final effRate = bonusAmount > 0 ? taxOnBonus / bonusAmount : 0.0;
      resultRows = [
        _row2(fr ? 'Impôt fédéral' : 'Federal Tax', _cur2.format(caFederalTax)),
        _row2(fr ? 'Impôt provincial' : 'Provincial Tax', _cur2.format(caProvincialTax)),
        pw.Divider(color: PdfColors.grey300, height: 6),
        _row2(fr ? 'Total retenu' : 'Total Tax Withheld', _cur2.format(taxOnBonus)),
        _row2(lNetBonus, _cur2.format(netBonus), bold: true, color: _green),
        _row2(lEffRate, '${(effRate * 100).toStringAsFixed(1)}%'),
      ];
    } else {
      // US — show better method
      final flatBetter = betterMethod == 'flat';
      taxOnBonus = flatBetter ? usFlatTotalTax : usAggregateTotalTax;
      netBonus = flatBetter ? usFlatNetBonus : usAggregateNetBonus;
      final effRate = bonusAmount > 0 ? taxOnBonus / bonusAmount : 0.0;
      final methodLabel = flatBetter
          ? (es ? 'Tasa fija (recomendada)' : 'Flat Rate (recommended)')
          : (es ? 'Método agregado (recomendado)' : 'Aggregate Method (recommended)');
      resultRows = [
        _row2(es ? 'Método' : 'Method', methodLabel),
        if (flatBetter) ...[
          _row2(es ? 'Impuesto federal supl.' : 'Supplemental Federal Tax',
              _cur2.format(usFlatFederalTax)),
          _row2(es ? 'Impuesto estatal' : 'State Tax',
              _cur2.format(usFlatStateTax)),
        ],
        _row2(es ? 'Total impuesto retenido' : 'Total Tax Withheld',
            _cur2.format(taxOnBonus)),
        _row2(lNetBonus, _cur2.format(netBonus), bold: true, color: _green),
        _row2(lEffRate, '${(effRate * 100).toStringAsFixed(1)}%'),
      ];
    }

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
                  pw.Text(lTitle,
                      style: pw.TextStyle(
                          fontSize: AppTextSize.title,
                          fontWeight: pw.FontWeight.bold,
                          color: _navy)),
                  pw.Text(
                      '$lSubtitle${lRegionValue.isNotEmpty ? ' · ${lRegionValue.toUpperCase()}' : ''}',
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
            _sectionBox(lInputs, [
              _row2(lBaseSalary, _cur0.format(grossAnnual)),
              _row2(lGrossBonus, _cur0.format(bonusAmount),
                  bold: true, color: _navy),
              if (!isUK && lRegionValue.isNotEmpty)
                _row2(isCA ? (fr ? 'Province' : 'Province') : 'State',
                    lRegionValue),
            ]),
            pw.SizedBox(height: 10),
            _effectiveRateBar(
                lEffRate,
                isUK ? '% net' : (fr ? '% net' : '% keep'),
                fr ? '% impôt' : (es ? '% impuesto' : '% tax'),
                bonusAmount,
                taxOnBonus),
          ])),
          pw.SizedBox(width: 14),
          pw.Expanded(child: _sectionBox(lResults, resultRows)),
        ]),
        pw.Spacer(),
        _footerNote(lFooter),
      ],
    );
  }

  // ── Tax Breakdown export ──────────────────────────────────────────────────
  //
  // brackets: list of (min, max, rate, amountInBracket, taxOwed) records.

  static Future<void> exportTaxBreakdown({
    required BuildContext context,
    required double grossAnnual,
    required List<({double min, double max, double rate, double amountInBracket, double taxOwed})>
        brackets,
    bool fr = false,
    bool es = false,
  }) async {
    // Serialize named-record list to parallel primitive lists (records not sendable)
    final bytes = await Isolate.run(() => _buildTaxBreakdownPdfBytes(
          _TaxBreakdownPdfParams(
            grossAnnual: grossAnnual,
            bMin: brackets.map((b) => b.min).toList(),
            bMax: brackets.map((b) => b.max).toList(),
            bRate: brackets.map((b) => b.rate).toList(),
            bAmountInBracket: brackets.map((b) => b.amountInBracket).toList(),
            bTaxOwed: brackets.map((b) => b.taxOwed).toList(),
            fr: fr,
            es: es,
          ),
        ));
    await Printing.sharePdf(
      bytes: bytes,
      filename:
          'TaxBreakdown_${grossAnnual.round()}_${DateTime.now().millisecondsSinceEpoch}.pdf',
    );
  }

  static pw.Widget _buildTaxBreakdownPage({
    required double grossAnnual,
    required List<({double min, double max, double rate, double amountInBracket, double taxOwed})>
        brackets,
    bool fr = false,
    bool es = false,
  }) {
    final now = DateTime.now();
    final isCA = FlavorConfig.isCA;
    final isUK = FlavorConfig.isUK;

    final totalFederal = brackets.fold(0.0, (s, b) => s + b.taxOwed);
    final deduction = isCA ? 16129.0 : isUK ? 12570.0 : 15000.0;
    final taxable = (grossAnnual - deduction).clamp(0.0, double.infinity);
    final effectiveRate = grossAnnual > 0 ? totalFederal / grossAnnual : 0.0;
    final takeHome = grossAnnual - totalFederal;

    // ── Localized labels ──────────────────────────────────────────────────────
    final lTitle = isCA
        ? (fr ? 'Calculatrice de Salaire CA' : 'Salary Calculator CA')
        : isUK
            ? 'Salary Calculator UK'
            : (es ? 'Calculadora de Salario' : 'Salary Calculator');
    final lSubtitle = isCA
        ? (fr
            ? 'Tranches d\'imposition fédérale 2025'
            : 'Federal Tax Brackets 2025')
        : isUK
            ? 'Income Tax Bands 2025'
            : (es
                ? 'Tramos del impuesto federal 2025'
                : 'Tax Bracket Breakdown 2025');
    final lSummary = es ? 'RESUMEN' : fr ? 'RÉSUMÉ' : 'SUMMARY';
    final lGross = es
        ? 'Ingreso bruto anual'
        : fr
            ? 'Revenu brut annuel'
            : 'Annual Gross Income';
    final lDeduction = isCA
        ? (fr ? 'Montant personnel de base' : 'Basic Personal Amount')
        : isUK
            ? 'Personal Allowance'
            : (es ? 'Deducción estándar' : 'Standard Deduction');
    final lTaxable =
        es ? 'Ingreso imponible' : fr ? 'Revenu imposable' : 'Taxable Income';
    final lFederal = isCA
        ? (fr ? 'Impôt fédéral total' : 'Total Federal Tax')
        : isUK
            ? 'Total Income Tax'
            : (es ? 'Impuesto federal total' : 'Total Federal Tax');
    final lEffective =
        es ? 'Tasa efectiva' : fr ? 'Taux effectif' : 'Effective Rate';
    final lTakeHome = isCA
        ? (fr
            ? 'Revenu net (avant prov./RPC/AE)'
            : 'Net (before prov./CPP/EI)')
        : isUK
            ? 'Net (before NI)'
            : (es
                ? 'Take-home (antes estado/FICA)'
                : 'Take-Home (before state/FICA)');
    final lBrackets = es
        ? 'TRAMOS FISCALES'
        : fr
            ? 'TRANCHES D\'IMPOSITION'
            : 'TAX BRACKETS';
    final lBracket = fr ? 'Tranche' : (es ? 'Tramo' : 'Bracket');
    final lRate = fr ? 'Taux' : (es ? 'Tasa' : 'Rate');
    final lInBracket =
        fr ? 'Dans la tranche' : (es ? 'En el tramo' : 'In Bracket');
    final lTaxOwed = fr ? 'Impôt dû' : (es ? 'Impuesto' : 'Tax Owed');
    const lTotal = 'Total';
    final lFooter = es
        ? 'Generado por Salary Calculator · Solo para fines ilustrativos.'
        : fr
            ? 'Généré par Calculatrice de Salaire · À titre indicatif seulement.'
            : 'Generated by Salary Calculator · For illustration purposes only. Not financial advice.';

    String shortNum(double v) {
      if (v >= 1000000) return '${(v / 1000000).toStringAsFixed(1)}M';
      if (v >= 1000) return '${(v / 1000).toStringAsFixed(0)}k';
      return v.toStringAsFixed(0);
    }

    final sym = FlavorConfig.currencySymbol;

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
                  pw.Text(lTitle,
                      style: pw.TextStyle(
                          fontSize: AppTextSize.title,
                          fontWeight: pw.FontWeight.bold,
                          color: _navy)),
                  pw.Text(lSubtitle,
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
            _sectionBox(lSummary, [
              _row2(lGross, _cur0.format(grossAnnual), bold: true, color: _navy),
              _row2(lDeduction, _cur0.format(deduction)),
              _row2(lTaxable, _cur0.format(taxable)),
              pw.Divider(color: PdfColors.grey300, height: 6),
              _row2(lFederal, _cur0.format(totalFederal)),
              _row2(lEffective, '${(effectiveRate * 100).toStringAsFixed(1)}%'),
              _row2(lTakeHome, _cur0.format(takeHome), bold: true, color: _green),
            ]),
            pw.SizedBox(height: 10),
            _effectiveRateBar(
                lEffective,
                isUK ? '% net' : (fr ? '% gardé' : '% keep'),
                fr ? '% impôt' : (es ? '% impuesto' : '% tax'),
                grossAnnual,
                totalFederal),
          ])),
          pw.SizedBox(width: 14),
          pw.Expanded(
              child: _sectionBox(lBrackets, [
            pw.SizedBox(height: 4),
            pw.Table(
              columnWidths: const {
                0: pw.FlexColumnWidth(3),
                1: pw.FlexColumnWidth(1.5),
                2: pw.FlexColumnWidth(2.5),
                3: pw.FlexColumnWidth(2.5),
              },
              children: [
                pw.TableRow(
                  decoration: const pw.BoxDecoration(
                      border: pw.Border(
                          bottom: pw.BorderSide(
                              color: PdfColors.grey400, width: 0.5))),
                  children: [
                    _pdfTh(lBracket),
                    _pdfTh(lRate),
                    _pdfTh(lInBracket),
                    _pdfTh(lTaxOwed),
                  ],
                ),
                for (final b in brackets)
                  pw.TableRow(children: [
                    _pdfTd(
                        '$sym${shortNum(b.min)}–${b.max == double.infinity ? '∞' : '$sym${shortNum(b.max)}'}'),
                    _pdfTd(
                        '${(b.rate * 100).toStringAsFixed(b.rate * 100 == (b.rate * 100).roundToDouble() ? 0 : 1)}%'),
                    _pdfTd(_cur0.format(b.amountInBracket)),
                    _pdfTd(_cur0.format(b.taxOwed)),
                  ]),
                pw.TableRow(
                  decoration: const pw.BoxDecoration(
                      border: pw.Border(
                          top: pw.BorderSide(
                              color: PdfColors.grey400, width: 0.5))),
                  children: [
                    _pdfTd(lTotal, bold: true),
                    _pdfTd(''),
                    _pdfTd(''),
                    _pdfTd(_cur0.format(totalFederal), bold: true),
                  ],
                ),
              ],
            ),
          ])),
        ]),
        pw.Spacer(),
        _footerNote(lFooter),
      ],
    );
  }

  static pw.Widget _pdfTh(String text) => pw.Padding(
        padding: const pw.EdgeInsets.only(bottom: 4),
        child: pw.Text(text,
            style: pw.TextStyle(
                fontSize: 7,
                fontWeight: pw.FontWeight.bold,
                color: PdfColors.grey700)),
      );

  static pw.Widget _pdfTd(String text, {bool bold = false}) => pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 3),
        child: pw.Text(text,
            style: pw.TextStyle(
                fontSize: 8,
                fontWeight:
                    bold ? pw.FontWeight.bold : pw.FontWeight.normal)),
      );

  // ── Raise Calculator export ───────────────────────────────────────────────

  static Future<void> exportRaise({
    required BuildContext context,
    required double currentSalary,
    required double newAnnual,
    required double raisePct,
    required double raiseGross,
    required double raiseNet,
    required double taxIncrease,
    required double oldMonthlyNet,
    required double newMonthlyNet,
    required double effectivePct,
    required double marginalRate,
    bool fr = false,
    bool es = false,
  }) async {
    final bytes = await Isolate.run(() => _buildRaisePdfBytes(_RaisePdfParams(
          currentSalary: currentSalary,
          newAnnual: newAnnual,
          raisePct: raisePct,
          raiseGross: raiseGross,
          raiseNet: raiseNet,
          taxIncrease: taxIncrease,
          oldMonthlyNet: oldMonthlyNet,
          newMonthlyNet: newMonthlyNet,
          effectivePct: effectivePct,
          marginalRate: marginalRate,
          fr: fr,
          es: es,
        )));
    await Printing.sharePdf(
      bytes: bytes,
      filename:
          'RaiseCalc_${currentSalary.round()}_${DateTime.now().millisecondsSinceEpoch}.pdf',
    );
  }

  static pw.Widget _buildRaisePage({
    required double currentSalary,
    required double newAnnual,
    required double raisePct,
    required double raiseGross,
    required double raiseNet,
    required double taxIncrease,
    required double oldMonthlyNet,
    required double newMonthlyNet,
    required double effectivePct,
    required double marginalRate,
    bool fr = false,
    bool es = false,
  }) {
    final now = DateTime.now();
    final isCA = FlavorConfig.isCA;
    final isUK = FlavorConfig.isUK;

    final lTitle = es
        ? 'Calculadora de Aumento'
        : fr
            ? 'Calculateur d\'Augmentation'
            : 'Raise Impact Calculator';
    final lSubtitle = es
        ? 'Informe de Impacto Salarial'
        : fr
            ? 'Rapport d\'Impact Salarial'
            : 'Salary Raise Impact Report';
    final lInputs = es ? 'ENTRADAS' : fr ? 'PARAMÈTRES' : 'INPUTS';
    final lCurrentSalary = es
        ? 'Salario actual (anual)'
        : fr
            ? 'Salaire actuel (annuel)'
            : 'Current Annual Salary';
    final lRaisePct =
        es ? 'Porcentaje de aumento' : fr ? 'Pourcentage d\'augmentation' : 'Raise %';
    final lGrossRaise =
        es ? 'Aumento bruto' : fr ? 'Augmentation brute' : 'Gross Raise';
    final lResults = es ? 'RESULTADOS' : fr ? 'RÉSULTATS' : 'RESULTS';
    final lNewSalary = es
        ? 'Nuevo salario anual'
        : fr
            ? 'Nouveau salaire annuel'
            : 'New Annual Salary';
    final lExtraTax = es
        ? 'Impuestos adicionales/año'
        : fr
            ? 'Impôts supplémentaires/an'
            : 'Extra Tax / Year';
    final lNetRaise = es
        ? 'Ganancia neta real/año'
        : fr
            ? 'Vrai gain net annuel'
            : 'Real Net Gain / Year';
    final lOldMonthly = es
        ? 'Neto mensual actual'
        : fr
            ? 'Mensuel net actuel'
            : 'Current Monthly Net';
    final lNewMonthly = es
        ? 'Nuevo neto mensual'
        : fr
            ? 'Nouveau mensuel net'
            : 'New Monthly Net';
    final lEffectivePct = es
        ? 'Aumento efectivo del neto'
        : fr
            ? 'Hausse effective du revenu net'
            : 'Effective Take-Home Raise';
    final lMarginalRate = isCA
        ? (fr ? 'Taux marginal fédéral' : 'Federal Marginal Rate')
        : isUK
            ? 'Marginal Rate'
            : (es ? 'Tasa marginal' : 'Marginal Rate on New Income');
    final lRetirementTip = isCA
        ? (fr
            ? 'Cotisez au REER pour récupérer une partie de l\'impôt sur ce surplus.'
            : 'Contribute to RRSP to claw back some tax on this raise.')
        : isUK
            ? 'Consider salary sacrifice into your pension to reduce tax on your raise.'
            : (es
                ? 'Maximiza tu 401(k) para recuperar parte del impuesto sobre el aumento.'
                : 'Max your 401(k) to claw back some tax on your raise.');
    final lFooter = es
        ? 'Generado por Salary Calculator · Solo para fines ilustrativos.'
        : fr
            ? 'Généré par Calculatrice de Salaire · À titre indicatif seulement.'
            : 'Generated by Salary Calculator · For illustration purposes only. Not financial advice.';

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
                  pw.Text(lTitle,
                      style: pw.TextStyle(
                          fontSize: AppTextSize.title,
                          fontWeight: pw.FontWeight.bold,
                          color: _navy)),
                  pw.Text(lSubtitle,
                      style: const pw.TextStyle(
                          fontSize: AppTextSize.xs, color: PdfColors.grey700)),
                ]),
            pw.Text(_date.format(now),
                style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey600)),
          ],
        ),
        pw.Container(
            height: 2,
            color: _navy,
            margin: const pw.EdgeInsets.only(top: 6, bottom: 14)),
        pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          pw.Expanded(
              child: pw.Column(children: [
            _sectionBox(lInputs, [
              _row2(lCurrentSalary, _cur0.format(currentSalary),
                  bold: true, color: _navy),
              _row2(lRaisePct, '${raisePct.toStringAsFixed(1)}%'),
              _row2(lGrossRaise, _cur0.format(raiseGross),
                  bold: true, color: _navy),
            ]),
            pw.SizedBox(height: 10),
            _sectionBox(
                fr
                    ? 'COMPARAISON MENSUELLE'
                    : (es ? 'COMPARACIÓN MENSUAL' : 'MONTHLY COMPARISON'),
                [
                  _row2(lOldMonthly, _cur0.format(oldMonthlyNet)),
                  _row2(lNewMonthly, _cur0.format(newMonthlyNet),
                      bold: true, color: _green),
                  pw.Divider(color: PdfColors.grey300, height: 6),
                  _row2(
                      fr
                          ? 'Gain mensuel net'
                          : (es ? 'Ganancia neta mensual' : 'Monthly Net Gain'),
                      '+${_cur0.format((newMonthlyNet - oldMonthlyNet).abs())}',
                      bold: true,
                      color: _green),
                ]),
          ])),
          pw.SizedBox(width: 14),
          pw.Expanded(
              child: pw.Column(children: [
            _sectionBox(lResults, [
              _row2(lNewSalary, _cur0.format(newAnnual),
                  bold: true, color: _green),
              _row2(lExtraTax, _cur0.format(taxIncrease),
                  color: const PdfColor(0.8, 0.2, 0.2)),
              _row2(lNetRaise, '+${_cur0.format(raiseNet)}',
                  bold: true, color: _green),
              pw.Divider(color: PdfColors.grey300, height: 6),
              _row2(lEffectivePct, '+${effectivePct.toStringAsFixed(1)}%'),
              _row2(lMarginalRate,
                  '${(marginalRate * 100).toStringAsFixed(0)}%'),
            ]),
            pw.SizedBox(height: 10),
            pw.Container(
              padding: const pw.EdgeInsets.all(AppSpacing.sm),
              decoration: pw.BoxDecoration(
                  color: _light,
                  border: pw.Border.all(color: _green, width: 0.5),
                  borderRadius:
                      const pw.BorderRadius.all(pw.Radius.circular(4))),
              child: pw.Text(lRetirementTip,
                  style: pw.TextStyle(
                      fontSize: 8, color: _navy, fontStyle: pw.FontStyle.italic)),
            ),
          ])),
        ]),
        pw.Spacer(),
        _footerNote(lFooter),
      ],
    );
  }

  // ── Retirement / 401(k) Optimizer export ─────────────────────────────────

  static Future<void> exportRetirement({
    required BuildContext context,
    required double grossIncome,
    required double contribution,
    required double contributionLimit,
    required double taxSaving,
    required double netCost,
    required double takeHomeChangeMonthly,
    required double projectedValue30yr,
    required double utilizationPct,
    required bool isMaxed,
    required bool age50Plus,
    bool es = false,
  }) async {
    final bytes =
        await Isolate.run(() => _buildRetirementPdfBytes(_RetirementPdfParams(
              grossIncome: grossIncome,
              contribution: contribution,
              contributionLimit: contributionLimit,
              taxSaving: taxSaving,
              netCost: netCost,
              takeHomeChangeMonthly: takeHomeChangeMonthly,
              projectedValue30yr: projectedValue30yr,
              utilizationPct: utilizationPct,
              isMaxed: isMaxed,
              age50Plus: age50Plus,
              es: es,
            )));
    await Printing.sharePdf(
      bytes: bytes,
      filename:
          '401k_${grossIncome.round()}_${DateTime.now().millisecondsSinceEpoch}.pdf',
    );
  }

  static pw.Widget _buildRetirementPage({
    required double grossIncome,
    required double contribution,
    required double contributionLimit,
    required double taxSaving,
    required double netCost,
    required double takeHomeChangeMonthly,
    required double projectedValue30yr,
    required double utilizationPct,
    required bool isMaxed,
    required bool age50Plus,
    bool es = false,
  }) {
    final now = DateTime.now();

    String fmtLarge(double v) {
      if (v >= 1000000) return '\$${(v / 1000000).toStringAsFixed(2)}M';
      if (v >= 1000) return '\$${(v / 1000).toStringAsFixed(0)}K';
      return _cur0.format(v);
    }

    final lTitle =
        es ? 'Optimizador 401(k)' : '401(k) Optimizer';
    final lSubtitle = es
        ? 'Informe de Ahorro para el Retiro'
        : '401(k) Tax Optimization Report';
    final lInputs = es ? 'ENTRADAS' : 'INPUTS';
    final lGross = es ? 'Salario bruto anual' : 'Annual Gross Salary';
    final lContribAmount =
        es ? 'Aportación anual al 401(k)' : '401(k) Annual Contribution';
    final lIrsLimit = es ? 'Límite IRS 2025' : 'IRS 2025 Limit';
    final lAgeGroup = es
        ? (age50Plus ? '50+ (catch-up)' : 'Menor de 50')
        : (age50Plus ? '50+ (catch-up)' : 'Under 50');
    final lResults = es ? 'RESULTADOS' : 'RESULTS';
    final lTaxSaving =
        es ? 'Ahorro en impuestos federales' : 'Federal Tax Savings';
    final lNetCost =
        es ? 'Costo neto después de ahorros' : 'Net Cost After Tax Savings';
    final lTakeHomeChange =
        es ? 'Cambio mensual en salario neto' : 'Take-Home Change / Month';
    final lUtilization =
        es ? 'Utilización del límite IRS' : 'IRS Limit Usage';
    final lProjection = es
        ? 'PROYECCIÓN A 30 AÑOS (7%)'
        : '30-YEAR PROJECTION AT 7%';
    final lMaxedNote = isMaxed
        ? (es ? 'Máximo IRS alcanzado' : 'IRS maximum reached')
        : null;
    final lFooter = es
        ? 'Generado por Salary Calculator · Basado en tasas federales IRS 2025. Las proyecciones asumen tasa constante. No es asesoramiento financiero.'
        : 'Generated by Salary Calculator · Based on IRS 2025 federal rates. Projections assume constant return. Not financial advice.';

    final takeHomeSign = takeHomeChangeMonthly >= 0 ? '' : '−';
    final takeHomeStr =
        '$takeHomeSign${_cur0.format(takeHomeChangeMonthly.abs())}';

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
                  pw.Text(lTitle,
                      style: pw.TextStyle(
                          fontSize: AppTextSize.title,
                          fontWeight: pw.FontWeight.bold,
                          color: _navy)),
                  pw.Text(lSubtitle,
                      style: const pw.TextStyle(
                          fontSize: AppTextSize.xs, color: PdfColors.grey700)),
                ]),
            pw.Text(_date.format(now),
                style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey600)),
          ],
        ),
        pw.Container(
            height: 2,
            color: _navy,
            margin: const pw.EdgeInsets.only(top: 6, bottom: 14)),
        pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          pw.Expanded(
              child: pw.Column(children: [
            _sectionBox(lInputs, [
              _row2(lGross, _cur0.format(grossIncome), bold: true, color: _navy),
              _row2(lAgeGroup, ''),
              _row2(lIrsLimit, _cur0.format(contributionLimit)),
              _row2(lContribAmount, _cur0.format(contribution),
                  bold: true, color: _navy),
              if (lMaxedNote != null)
                pw.Padding(
                  padding: const pw.EdgeInsets.only(top: 4),
                  child: pw.Text(lMaxedNote,
                      style: pw.TextStyle(
                          fontSize: 8,
                          color: _green,
                          fontWeight: pw.FontWeight.bold)),
                ),
            ]),
            pw.SizedBox(height: 10),
            _sectionBox(lProjection, [
              pw.SizedBox(height: 6),
              pw.Text(
                fmtLarge(projectedValue30yr),
                style: pw.TextStyle(
                    fontSize: 22,
                    fontWeight: pw.FontWeight.bold,
                    color: _navy),
              ),
              pw.SizedBox(height: 4),
              pw.Text(
                es
                    ? 'Si contribuyes ${_cur0.format(contribution)}/año durante 30 años al 7%.'
                    : 'Contributing ${_cur0.format(contribution)}/yr for 30 years at 7%.',
                style: const pw.TextStyle(
                    fontSize: 8, color: PdfColors.grey600),
              ),
            ]),
          ])),
          pw.SizedBox(width: 14),
          pw.Expanded(
              child: _sectionBox(lResults, [
            _row2(lTaxSaving, _cur0.format(taxSaving),
                bold: true, color: _green),
            _row2(lNetCost, _cur0.format(netCost), color: _navy),
            _row2(lTakeHomeChange, takeHomeStr),
            pw.Divider(color: PdfColors.grey300, height: 6),
            _row2(lUtilization, '${utilizationPct.toStringAsFixed(0)}%'),
            _effectiveRateBar(
                es ? 'Utilización' : 'Utilization',
                es ? '% no usado' : '% unused',
                es ? '% 401k' : '% 401k',
                100,
                utilizationPct),
          ])),
        ]),
        pw.Spacer(),
        _footerNote(lFooter),
      ],
    );
  }

  // ── RRSP Optimizer export (CA flavor) ─────────────────────────────────────

  static Future<void> exportRrsp({
    required BuildContext context,
    required double grossIncome,
    required double rrspRoom,
    required double contribution,
    required double taxSaving,
    required double netCost,
    required double remainingRoom,
    required double marginalRate,
    required String bracketLabel,
    required String province,
    bool fr = false,
  }) async {
    final bytes = await Isolate.run(() => _buildRrspPdfBytes(_RrspPdfParams(
          grossIncome: grossIncome,
          rrspRoom: rrspRoom,
          contribution: contribution,
          taxSaving: taxSaving,
          netCost: netCost,
          remainingRoom: remainingRoom,
          marginalRate: marginalRate,
          bracketLabel: bracketLabel,
          province: province,
          fr: fr,
        )));
    await Printing.sharePdf(
      bytes: bytes,
      filename:
          'RRSPCalc_${grossIncome.round()}_${DateTime.now().millisecondsSinceEpoch}.pdf',
    );
  }

  static pw.Widget _buildRrspPage({
    required double grossIncome,
    required double rrspRoom,
    required double contribution,
    required double taxSaving,
    required double netCost,
    required double remainingRoom,
    required double marginalRate,
    required String bracketLabel,
    required String province,
    bool fr = false,
  }) {
    final now = DateTime.now();

    final sym = FlavorConfig.currencySymbol; // CA$ or $
    String fmtCa(double v) =>
        NumberFormat.currency(symbol: sym, decimalDigits: 0).format(v);
    String fmtPct(double v) => '${(v * 100).toStringAsFixed(1)}%';

    final lTitle = fr ? 'Optimiseur REER' : 'RRSP Optimizer';
    final lSubtitle = fr
        ? 'Rapport d\'Optimisation REER · $province'
        : 'RRSP Tax Optimization Report · $province';
    final lInputs = fr ? 'PARAMÈTRES' : 'INPUTS';
    final lGross = fr ? 'Revenu annuel brut' : 'Gross Annual Income';
    final lRoom = fr ? 'Droits REER disponibles' : 'RRSP Contribution Room';
    final lContrib = fr ? 'Cotisation recommandée' : 'Recommended Contribution';
    final lResults = fr ? 'RÉSULTATS' : 'RESULTS';
    final lRefund = fr ? 'Remboursement fiscal estimé' : 'Estimated Tax Refund';
    final lNetCostLabel = fr ? 'Coût net après remboursement' : 'Net Cost After Refund';
    final lMarginal = fr ? 'Taux marginal combiné' : 'Combined Marginal Rate';
    final lBracketAfter =
        fr ? 'Tranche après cotisation' : 'Bracket After Contribution';
    final lRemaining = fr ? 'Droits REER restants' : 'Remaining RRSP Room';
    final lProjection =
        fr ? 'PROJECTION REER À 65 ANS (6%)' : 'RRSP PROJECTION TO AGE 65 (6%)';
    final lTip = fr
        ? 'Le remboursement fiscal réduit votre coût réel. Réinvestissez-le dans votre REER pour maximiser la croissance.'
        : 'The tax refund reduces your real cost. Reinvest it into your RRSP to maximize growth.';
    final lFooter = fr
        ? 'Généré par Calculatrice de Salaire · Estimations basées sur les taux fédéraux 2025 et les taux provinciaux approximatifs. À titre indicatif seulement.'
        : 'Generated by Salary Calculator · Based on 2025 federal rates and approximate provincial rates. For illustration only.';

    // Project RRSP balance to age 65 assuming 25 years of contributions at 6%
    const double projReturn = 0.06;
    const int projYears = 25;
    final projBalance =
        contribution * ((pow(1 + projReturn, projYears) - 1) / projReturn);
    String fmtLarge(double v) {
      if (v >= 1000000) return '$sym${(v / 1000000).toStringAsFixed(2)}M';
      if (v >= 1000) return '$sym${(v / 1000).toStringAsFixed(0)}K';
      return fmtCa(v);
    }

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
                  pw.Text(lTitle,
                      style: pw.TextStyle(
                          fontSize: AppTextSize.title,
                          fontWeight: pw.FontWeight.bold,
                          color: _navy)),
                  pw.Text(lSubtitle,
                      style: const pw.TextStyle(
                          fontSize: AppTextSize.xs, color: PdfColors.grey700)),
                ]),
            pw.Text(_date.format(now),
                style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey600)),
          ],
        ),
        pw.Container(
            height: 2,
            color: _navy,
            margin: const pw.EdgeInsets.only(top: 6, bottom: 14)),
        pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          pw.Expanded(
              child: pw.Column(children: [
            _sectionBox(lInputs, [
              _row2(lGross, fmtCa(grossIncome), bold: true, color: _navy),
              _row2(lRoom, fmtCa(rrspRoom)),
              _row2(lContrib, fmtCa(contribution), bold: true, color: _navy),
            ]),
            pw.SizedBox(height: 10),
            _sectionBox(lProjection, [
              pw.SizedBox(height: 6),
              pw.Text(
                fmtLarge(projBalance),
                style: pw.TextStyle(
                    fontSize: 22,
                    fontWeight: pw.FontWeight.bold,
                    color: _navy),
              ),
              pw.SizedBox(height: 4),
              pw.Text(
                fr
                    ? '${fmtCa(contribution)}/an pendant 25 ans à 6%.'
                    : '${fmtCa(contribution)}/yr for 25 years at 6%.',
                style: const pw.TextStyle(
                    fontSize: 8, color: PdfColors.grey600),
              ),
            ]),
          ])),
          pw.SizedBox(width: 14),
          pw.Expanded(
              child: pw.Column(children: [
            _sectionBox(lResults, [
              _row2(lRefund, fmtCa(taxSaving), bold: true, color: _green),
              _row2(lNetCostLabel, fmtCa(netCost), color: _navy),
              _row2(lMarginal, fmtPct(marginalRate)),
              _row2(lBracketAfter, bracketLabel, color: _green),
              pw.Divider(color: PdfColors.grey300, height: 6),
              _row2(lRemaining, fmtCa(remainingRoom)),
            ]),
            pw.SizedBox(height: 10),
            pw.Container(
              padding: const pw.EdgeInsets.all(AppSpacing.sm),
              decoration: pw.BoxDecoration(
                  color: _light,
                  border: pw.Border.all(color: _green, width: 0.5),
                  borderRadius:
                      const pw.BorderRadius.all(pw.Radius.circular(4))),
              child: pw.Text(lTip,
                  style: pw.TextStyle(
                      fontSize: 8,
                      color: _navy,
                      fontStyle: pw.FontStyle.italic)),
            ),
          ])),
        ]),
        pw.Spacer(),
        _footerNote(lFooter),
      ],
    );
  }

  // ── Salary Comparison export ──────────────────────────────────────────────

  static Future<void> exportSalaryComparison({
    required BuildContext context,
    required double grossA,
    required double grossB,
    required double netAnnualA,
    required double netAnnualB,
    required double netMonthlyA,
    required double netMonthlyB,
    required double federalTaxA,
    required double federalTaxB,
    required double ficaTaxA,
    required double ficaTaxB,
    required double stateTaxA,
    required double stateTaxB,
    required double totalTaxA,
    required double totalTaxB,
    required double effectiveRateA,
    required double effectiveRateB,
    required String regionA,
    required String regionB,
    bool fr = false,
    bool es = false,
  }) async {
    final bytes = await Isolate.run(
        () => _buildSalaryComparisonPdfBytes(_SalaryComparisonPdfParams(
              grossA: grossA,
              grossB: grossB,
              netAnnualA: netAnnualA,
              netAnnualB: netAnnualB,
              netMonthlyA: netMonthlyA,
              netMonthlyB: netMonthlyB,
              federalTaxA: federalTaxA,
              federalTaxB: federalTaxB,
              ficaTaxA: ficaTaxA,
              ficaTaxB: ficaTaxB,
              stateTaxA: stateTaxA,
              stateTaxB: stateTaxB,
              totalTaxA: totalTaxA,
              totalTaxB: totalTaxB,
              effectiveRateA: effectiveRateA,
              effectiveRateB: effectiveRateB,
              regionA: regionA,
              regionB: regionB,
              fr: fr,
              es: es,
            )));
    await Printing.sharePdf(
      bytes: bytes,
      filename:
          'SalaryComparison_${DateTime.now().millisecondsSinceEpoch}.pdf',
    );
  }

  static pw.Widget _buildSalaryComparisonPage({
    required double grossA,
    required double grossB,
    required double netAnnualA,
    required double netAnnualB,
    required double netMonthlyA,
    required double netMonthlyB,
    required double federalTaxA,
    required double federalTaxB,
    required double ficaTaxA,
    required double ficaTaxB,
    required double stateTaxA,
    required double stateTaxB,
    required double totalTaxA,
    required double totalTaxB,
    required double effectiveRateA,
    required double effectiveRateB,
    required String regionA,
    required String regionB,
    bool fr = false,
    bool es = false,
  }) {
    final now = DateTime.now();
    final isCA = FlavorConfig.isCA;
    final isUK = FlavorConfig.isUK;
    final isUS = !isCA && !isUK;

    // Determine winner
    final deltaNet = netAnnualB - netAnnualA;
    final aWins = deltaNet < 0;
    final isTie = deltaNet.abs() < 1;
    final winnerColor = isTie ? PdfColors.orange : _green;

    final lTitle = fr
        ? 'Comparaison de Salaires'
        : (es ? 'Comparación de Salarios' : 'Salary Comparison');
    final lSubtitle = fr
        ? 'Offre A vs Offre B'
        : (es ? 'Oferta A vs Oferta B' : 'Offer A vs Offer B');
    final lOfferA = fr ? 'Offre A' : (es ? 'Oferta A' : 'Offer A');
    final lOfferB = fr ? 'Offre B' : (es ? 'Oferta B' : 'Offer B');
    final lDiff = fr ? 'Écart' : (es ? 'Delta' : 'Diff');
    final lGross = fr
        ? 'Salaire brut'
        : (es ? 'Salario bruto' : 'Gross Salary');
    final lFederal = isUK
        ? 'Income Tax'
        : (fr ? 'Impôt fédéral' : (es ? 'Impuesto federal' : 'Federal Tax'));
    final lFica = isUS
        ? 'FICA (SS + Medicare)'
        : (isUK
            ? 'National Insurance'
            : (fr ? 'RPC + AE' : 'CPP + EI'));
    final lState = isUK
        ? ''
        : (fr
            ? 'Impôt provincial'
            : (es ? 'Impuesto estatal' : 'State/Prov. Tax'));
    final lTotalTax =
        fr ? 'Total impôts' : (es ? 'Impuesto total' : 'Total Tax');
    final lNetAnnual =
        fr ? 'Net annuel' : (es ? 'Neto anual' : 'Net Annual');
    final lNetMonthly =
        fr ? 'Net mensuel' : (es ? 'Neto mensual' : 'Net Monthly');
    final lEffRate = fr
        ? 'Taux effectif'
        : (es ? 'Tasa efectiva' : 'Effective Rate');
    final lWinnerTitle = isTie
        ? (fr ? 'Résultat : Égalité' : (es ? 'Resultado: Empate' : 'Result: Tie'))
        : (aWins
            ? (fr ? 'Meilleure offre : Offre A' : (es ? 'Mejor oferta: Oferta A' : 'Best Offer: Offer A'))
            : (fr ? 'Meilleure offre : Offre B' : (es ? 'Mejor oferta: Oferta B' : 'Best Offer: Offer B')));
    final lWinnerDetail = isTie
        ? (fr ? 'Les deux offres sont équivalentes.' : (es ? 'Ambas ofertas son equivalentes.' : 'Both offers are equivalent.'))
        : (fr
            ? 'Avantage net annuel : ${_cur0.format(deltaNet.abs())}'
            : (es
                ? 'Ventaja neta anual: ${_cur0.format(deltaNet.abs())}'
                : 'Net annual advantage: ${_cur0.format(deltaNet.abs())}'));
    final lFooter = fr
        ? 'Généré par Calculatrice de Salaire · À titre indicatif seulement.'
        : (es
            ? 'Generado por Salary Calculator · Solo para fines ilustrativos.'
            : 'Generated by Salary Calculator · For illustration purposes only. Not financial advice.');

    pw.Widget compRow(String label, double valA, double valB,
        {bool bold = false,
        bool isPct = false,
        bool invertDelta = false,
        bool skipDelta = false}) {
      final delta = valB - valA;
      final positive = invertDelta ? delta <= 0 : delta >= 0;
      final deltaColor = delta.abs() < 0.5
          ? PdfColors.grey600
          : positive
              ? _green
              : const PdfColor(0.8, 0.2, 0.2);
      final sign = delta >= 0 ? '+' : '−';
      final deltaStr = skipDelta
          ? ''
          : isPct
              ? '$sign${delta.abs().toStringAsFixed(1)}pp'
              : '$sign${_cur0.format(delta.abs())}';
      final vStyle = pw.TextStyle(
          fontSize: 8.5,
          fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal);
      return pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 2.5),
        child: pw.Row(children: [
          pw.Expanded(
              flex: 4,
              child: pw.Text(label,
                  style: pw.TextStyle(
                      fontSize: 8.5,
                      fontWeight:
                          bold ? pw.FontWeight.bold : pw.FontWeight.normal,
                      color: PdfColors.grey800))),
          pw.Expanded(
              flex: 3,
              child: pw.Text(
                  isPct
                      ? '${valA.toStringAsFixed(1)}%'
                      : _cur0.format(valA),
                  textAlign: pw.TextAlign.center,
                  style: vStyle.copyWith(color: _navy))),
          pw.Expanded(
              flex: 3,
              child: pw.Text(
                  isPct
                      ? '${valB.toStringAsFixed(1)}%'
                      : _cur0.format(valB),
                  textAlign: pw.TextAlign.center,
                  style: vStyle.copyWith(
                      color: const PdfColor(0.1, 0.55, 0.8)))),
          pw.Expanded(
              flex: 2,
              child: pw.Text(deltaStr,
                  textAlign: pw.TextAlign.right,
                  style:
                      pw.TextStyle(fontSize: 8, color: deltaColor))),
        ]),
      );
    }

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        // Header
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          crossAxisAlignment: pw.CrossAxisAlignment.end,
          children: [
            pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(lTitle,
                      style: pw.TextStyle(
                          fontSize: AppTextSize.title,
                          fontWeight: pw.FontWeight.bold,
                          color: _navy)),
                  pw.Text(lSubtitle,
                      style: const pw.TextStyle(
                          fontSize: AppTextSize.xs, color: PdfColors.grey700)),
                ]),
            pw.Text(_date.format(now),
                style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey600)),
          ],
        ),
        pw.Container(
            height: 2,
            color: _navy,
            margin: const pw.EdgeInsets.only(top: 6, bottom: 14)),

        // Table header row
        _sectionBox(
            fr
                ? 'COMPARAISON DÉTAILLÉE'
                : (es ? 'COMPARACIÓN DETALLADA' : 'DETAILED COMPARISON'),
            [
              pw.SizedBox(height: 4),
              // Sub-header
              pw.Row(children: [
                pw.Expanded(
                    flex: 4,
                    child: pw.Text(
                        fr ? 'Métrique' : (es ? 'Métrica' : 'Metric'),
                        style: pw.TextStyle(
                            fontSize: 8,
                            fontWeight: pw.FontWeight.bold,
                            color: PdfColors.grey600))),
                pw.Expanded(
                    flex: 3,
                    child: pw.Text(
                        '$lOfferA${regionA.isNotEmpty ? ' ($regionA)' : ''}',
                        textAlign: pw.TextAlign.center,
                        style: pw.TextStyle(
                            fontSize: 8,
                            fontWeight: pw.FontWeight.bold,
                            color: _navy))),
                pw.Expanded(
                    flex: 3,
                    child: pw.Text(
                        '$lOfferB${regionB.isNotEmpty ? ' ($regionB)' : ''}',
                        textAlign: pw.TextAlign.center,
                        style: pw.TextStyle(
                            fontSize: 8,
                            fontWeight: pw.FontWeight.bold,
                            color: const PdfColor(0.1, 0.55, 0.8)))),
                pw.Expanded(
                    flex: 2,
                    child: pw.Text(lDiff,
                        textAlign: pw.TextAlign.right,
                        style: pw.TextStyle(
                            fontSize: 8,
                            fontWeight: pw.FontWeight.bold,
                            color: PdfColors.grey600))),
              ]),
              pw.Divider(color: PdfColors.grey300, height: 6),
              compRow(lGross, grossA, grossB, bold: true),
              pw.Divider(color: PdfColors.grey300, height: 6),
              compRow(lFederal, federalTaxA, federalTaxB, invertDelta: true),
              compRow(lFica, ficaTaxA, ficaTaxB, invertDelta: true),
              if (!isUK)
                compRow(lState, stateTaxA, stateTaxB, invertDelta: true),
              compRow(lTotalTax, totalTaxA, totalTaxB,
                  bold: true, invertDelta: true),
              pw.Divider(color: PdfColors.grey300, height: 6),
              compRow(lNetAnnual, netAnnualA, netAnnualB, bold: true),
              compRow(lNetMonthly, netMonthlyA, netMonthlyB, bold: true),
              pw.Divider(color: PdfColors.grey300, height: 6),
              compRow(lEffRate, effectiveRateA, effectiveRateB,
                  isPct: true, invertDelta: true),
            ]),
        pw.SizedBox(height: 10),

        // Winner banner
        pw.Container(
          width: double.infinity,
          padding: const pw.EdgeInsets.all(10),
          decoration: pw.BoxDecoration(
              color: winnerColor == _green
                  ? _light
                  : const PdfColor(1.0, 0.95, 0.85),
              border: pw.Border.all(color: winnerColor, width: 0.8),
              borderRadius:
                  const pw.BorderRadius.all(pw.Radius.circular(4))),
          child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(lWinnerTitle,
                    style: pw.TextStyle(
                        fontSize: 10,
                        fontWeight: pw.FontWeight.bold,
                        color: winnerColor)),
                pw.SizedBox(height: 3),
                pw.Text(lWinnerDetail,
                    style: const pw.TextStyle(
                        fontSize: 8.5, color: PdfColors.grey700)),
                if (!isTie) ...[
                  pw.SizedBox(height: 2),
                  pw.Text(
                    fr
                        ? '+${_cur0.format(deltaNet.abs() / 12)} par mois'
                        : (es
                            ? '+${_cur0.format(deltaNet.abs() / 12)} por mes'
                            : '+${_cur0.format(deltaNet.abs() / 12)} per month'),
                    style: pw.TextStyle(
                        fontSize: 8,
                        color: winnerColor,
                        fontWeight: pw.FontWeight.bold),
                  ),
                ],
              ]),
        ),

        pw.Spacer(),
        _footerNote(lFooter),
      ],
    );
  }

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
            ? 'Premium (illimité)'
            : 'Premium (ilimitado)')
        : 'Premium (unlimited)';
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
                fontSize: AppTextSize.md,
                color: CalcwiseTheme.of(context).textSecondary)),
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
                style:
                    TextStyle(color: CalcwiseTheme.of(context).textSecondary))),
      ]),
    );
  }
}
