// ignore_for_file: constant_identifier_names

import 'dart:math' show min;

import 'package:calcwise_core/calcwise_core.dart'
    show CalcwiseReverseSolver, TaxRegistry, taxOnIncome, CalcwiseTax;

// ─── Shared result model ──────────────────────────────────────────────────────

class SalaryResult {
  final double grossAnnual;
  final double federalTax;
  final double ficaTax; // US: FICA  |  UK: NI  |  CA: CPP+EI
  final double stateTax; // US: state |  UK: 0   |  CA: provincial
  final double totalTax;
  final double netAnnual;
  final double netMonthly;
  final double netBiWeekly;
  final double netWeekly;
  final double effectiveRate; // percentage

  const SalaryResult({
    required this.grossAnnual,
    required this.federalTax,
    required this.ficaTax,
    required this.stateTax,
    required this.totalTax,
    required this.netAnnual,
    required this.netMonthly,
    required this.netBiWeekly,
    required this.netWeekly,
    required this.effectiveRate,
  });

  Map<String, dynamic> toMap() => {
        'grossAnnual': grossAnnual,
        'federalTax': federalTax,
        'ficaTax': ficaTax,
        'stateTax': stateTax,
        'totalTax': totalTax,
        'netAnnual': netAnnual,
        'netMonthly': netMonthly,
        'netBiWeekly': netBiWeekly,
        'netWeekly': netWeekly,
        'effectiveRate': effectiveRate,
      };

  factory SalaryResult.fromMap(Map<String, dynamic> m) => SalaryResult(
        grossAnnual: (m['grossAnnual'] as num).toDouble(),
        federalTax: (m['federalTax'] as num).toDouble(),
        ficaTax: (m['ficaTax'] as num).toDouble(),
        stateTax: (m['stateTax'] as num).toDouble(),
        totalTax: (m['totalTax'] as num).toDouble(),
        netAnnual: (m['netAnnual'] as num).toDouble(),
        netMonthly: (m['netMonthly'] as num).toDouble(),
        netBiWeekly: (m['netBiWeekly'] as num).toDouble(),
        netWeekly: (m['netWeekly'] as num).toDouble(),
        effectiveRate: (m['effectiveRate'] as num).toDouble(),
      );
}

// ─── US Engine ────────────────────────────────────────────────────────────────

class UsSalaryEngine {
  UsSalaryEngine._();

  /// Centralized, effective-dated tax tables (calcwise_core). Baked-in floor;
  /// the same registry can be swapped for a remote-updated dataset.
  static TaxRegistry get _reg => CalcwiseTax.registry;

  /// Federal income tax 2025 — brackets + standard deduction now sourced from
  /// the shared [TaxRegistry] (`us_federal` 2025; default = single filer, `mfj`
  /// variant for married filing jointly). [preTaxDeductions] reduces taxable
  /// income (e.g. 401k, HSA, FSA). Data verified vs IRS (Rev. Proc. 2024-40 +
  /// OBBBA standard deduction). See the calcwise-tax-data repo.
  static double federalTax(
    double grossAnnual, {
    bool marriedFilingJointly = false,
    double preTaxDeductions = 0,
  }) {
    final set = _reg.annual('us_federal', 2025,
            status: marriedFilingJointly ? 'mfj' : null) ??
        _reg.annual('us_federal', 2025);
    if (set == null) return 0.0; // baked data guarantees presence; guard only
    final taxable =
        (grossAnnual - (set.basicPersonalAmount ?? 0) - preTaxDeductions)
            .clamp(0.0, double.infinity);
    return taxOnIncome(set.bands, taxable);
  }

  /// FICA 2025: Social Security (6.2% up to $176,100 SS wage base) +
  /// Medicare (1.45%) + Additional Medicare surtax (0.9% above $200,000 single).
  static double fica(double grossAnnual) {
    const double ssWageBase2025 = 176100;
    const double additionalMedicareThreshold = 200000;
    final ss = min(grossAnnual, ssWageBase2025) * 0.062;
    final medicare = grossAnnual * 0.0145;
    final additionalMedicare = grossAnnual > additionalMedicareThreshold
        ? (grossAnnual - additionalMedicareThreshold) * 0.009
        : 0.0;
    return ss + medicare + additionalMedicare;
  }

  /// Applies progressive tax brackets to [income].
  /// [brackets] is a list of (upperBound, rate) pairs in ascending order;
  /// the last entry's upperBound is ignored (treated as infinity).
  static double _progressive(
      double income, List<(double upper, double rate)> brackets) {
    double tax = 0;
    double prev = 0;
    for (int i = 0; i < brackets.length; i++) {
      final upper = i < brackets.length - 1 ? brackets[i].$1 : double.infinity;
      final rate = brackets[i].$2;
      if (income <= prev) break;
      final taxable = (income < upper ? income : upper) - prev;
      tax += taxable * rate;
      prev = upper;
    }
    return tax;
  }

  /// State income tax — progressive brackets where applicable (2025, single filer).
  static double stateTax(double grossAnnual, String state) {
    switch (state) {
      // ── No state income tax ──────────────────────────────────────────────
      case 'TX':
      case 'FL':
      case 'NV':
      case 'WA':
      case 'AK':
      case 'SD':
      case 'WY':
      case 'NH': // only taxes interest/dividends, not wages
      case 'TN': // Hall tax fully repealed
        return 0;

      // ── Progressive states ───────────────────────────────────────────────

      // California: 9 brackets + 1 % mental-health surcharge above $1 M
      case 'CA':
        final baseTax = _progressive(grossAnnual, [
          (10756, 0.01),
          (25499, 0.02),
          (40245, 0.04),
          (55866, 0.06),
          (70606, 0.08),
          (360659, 0.093),
          (432787, 0.103),
          (721314, 0.113),
          (double.infinity, 0.123),
        ]);
        final surcharge =
            grossAnnual > 1000000 ? (grossAnnual - 1000000) * 0.01 : 0.0;
        return baseTax + surcharge;

      // New York: 9 brackets
      case 'NY':
        return _progressive(grossAnnual, [
          (17150, 0.04),
          (23600, 0.045),
          (27900, 0.0525),
          (161550, 0.0585),
          (323200, 0.0625),
          (2155350, 0.0685),
          (5000000, 0.0965),
          (25000000, 0.103),
          (double.infinity, 0.109),
        ]);

      // New Jersey: 7 brackets
      case 'NJ':
        return _progressive(grossAnnual, [
          (20000, 0.014),
          (35000, 0.0175),
          (40000, 0.035),
          (75000, 0.05525),
          (500000, 0.0637),
          (1000000, 0.0897),
          (double.infinity, 0.1075),
        ]);

      // Minnesota: 4 brackets
      case 'MN':
        return _progressive(grossAnnual, [
          (31690, 0.0535),
          (104090, 0.068),
          (193240, 0.0785),
          (double.infinity, 0.0985),
        ]);

      // Oregon: 4 brackets
      case 'OR':
        return _progressive(grossAnnual, [
          (4050, 0.0475),
          (10200, 0.0675),
          (125000, 0.0875),
          (double.infinity, 0.099),
        ]);

      // Wisconsin: 4 brackets
      case 'WI':
        return _progressive(grossAnnual, [
          (14320, 0.035),
          (28640, 0.044),
          (315310, 0.053),
          (double.infinity, 0.0765),
        ]);

      // ── Flat-rate states ─────────────────────────────────────────────────
      case 'IL':
        return grossAnnual * 0.0495;
      case 'PA':
        return grossAnnual * 0.0307;
      // Ohio 2025: progressive brackets (no standard deduction applied here)
      case 'OH':
        return _progressive(grossAnnual, [
          (26050, 0.0),
          (100000, 0.02765),
          (115300, 0.03226),
          (1000000, 0.03688),
          (double.infinity, 0.0399),
        ]);
      case 'GA':
        return grossAnnual * 0.0539; // 5.39% flat (2025)
      case 'NC':
        return grossAnnual * 0.0425; // 4.25% flat (2025)
      // Virginia 2025: progressive brackets
      case 'VA':
        return _progressive(grossAnnual, [
          (3000, 0.02),
          (5000, 0.03),
          (17000, 0.05),
          (double.infinity, 0.0575),
        ]);
      case 'MA':
        return grossAnnual * 0.05;
      case 'CO':
        return grossAnnual * 0.044;
      case 'AZ':
        return grossAnnual * 0.025;
      case 'MD':
        return grossAnnual * 0.0575;
      case 'MI':
        return grossAnnual * 0.0425;
      case 'IN':
        return grossAnnual * 0.0323;
      case 'KY':
        return grossAnnual * 0.045;
      case 'MO':
        return grossAnnual * 0.0495;
      case 'AL':
        return grossAnnual * 0.05;
      case 'SC':
        return grossAnnual * 0.064; // 6.4% flat (2024, stepped down from 7%)
      case 'LA':
        return grossAnnual * 0.030; // 3.0% flat (HB 10, eff. Jan 1 2025)
      case 'AR':
        return grossAnnual * 0.044; // 4.4% flat (Act 1 of 2024 session)
      case 'MS':
        return grossAnnual * 0.05;
      case 'ID':
        return grossAnnual * 0.05695; // 5.695% flat (2024+)
      case 'NM':
        return grossAnnual * 0.059;
      case 'MT':
        return grossAnnual * 0.059; // 5.9% flat (HB 192, eff. Jan 1 2024)
      case 'UT':
        return grossAnnual * 0.0465;
      case 'ND':
        return grossAnnual * 0.029;
      case 'HI':
        return grossAnnual * 0.11;
      case 'VT':
        return grossAnnual * 0.0875;
      case 'ME':
        return grossAnnual * 0.0715;
      case 'CT':
        return grossAnnual * 0.0699;
      case 'RI':
        return grossAnnual * 0.0599;
      case 'DE':
        return grossAnnual * 0.066;
      case 'DC':
        return grossAnnual * 0.0895;
      case 'WV':
        return grossAnnual * 0.0512; // 5.12% top rate (SB 2, 2023)
      case 'KS':
        return grossAnnual * 0.057;
      case 'NE':
        return grossAnnual * 0.0584; // 5.84% flat (LB 754, eff. Jan 1 2024)
      case 'IA':
        return grossAnnual * 0.038; // 3.8% flat (eff. Jan 2025)
      case 'OK':
        return grossAnnual * 0.0475;
      default:
        return grossAnnual * 0.05;
    }
  }

  /// [secondIncome] – additional W-2 gross income (annual). The two incomes are
  /// cumulated for federal/state income tax (brackets apply to the total).
  /// FICA Social Security is capped per employer, so cumulating taxable income
  /// is a reasonable simplification for a take-home calculator.
  static SalaryResult calculate(
    double grossAnnual,
    String state, {
    bool marriedFilingJointly = false,
    double preTaxDeductions = 0,
    double secondIncome = 0,
  }) {
    grossAnnual = grossAnnual + (secondIncome > 0 ? secondIncome : 0);
    final federal = federalTax(grossAnnual,
        marriedFilingJointly: marriedFilingJointly,
        preTaxDeductions: preTaxDeductions);
    final ficaAmt = fica(grossAnnual);
    final stateAmt = stateTax(grossAnnual, state);
    final total = federal + ficaAmt + stateAmt;
    final net = grossAnnual - total;
    return SalaryResult(
      grossAnnual: grossAnnual,
      federalTax: federal,
      ficaTax: ficaAmt,
      stateTax: stateAmt,
      totalTax: total,
      netAnnual: net,
      netMonthly: net / 12,
      netBiWeekly: net / 26,
      netWeekly: net / 52,
      effectiveRate: total / grossAnnual * 100,
    );
  }

  static const List<String> states = [
    'AK',
    'AL',
    'AR',
    'AZ',
    'CA',
    'CO',
    'CT',
    'DC',
    'DE',
    'FL',
    'GA',
    'HI',
    'IA',
    'ID',
    'IL',
    'IN',
    'KS',
    'KY',
    'LA',
    'MA',
    'MD',
    'ME',
    'MI',
    'MN',
    'MO',
    'MS',
    'MT',
    'NC',
    'ND',
    'NE',
    'NH',
    'NJ',
    'NM',
    'NV',
    'NY',
    'OH',
    'OK',
    'OR',
    'PA',
    'RI',
    'SC',
    'SD',
    'TN',
    'TX',
    'UT',
    'VA',
    'VT',
    'WA',
    'WI',
    'WV',
    'WY',
  ];
}

// ─── UK HMRC tax code ─────────────────────────────────────────────────────────

/// How a parsed HMRC tax code overrides the income-tax calculation.
///
/// Reference (HMRC, gov.uk):
///  - https://www.gov.uk/tax-codes/what-your-tax-code-means
///  - https://www.gov.uk/employee-tax-codes/letters
///  - https://www.gov.uk/employee-tax-codes/numbers
enum UkTaxCodeMode {
  /// Numeric code with an `L`-type suffix (e.g. `1257L`): the personal
  /// allowance equals the numeric part × 10 (1257L → £12,570).
  allowance,

  /// `K` codes (e.g. `K500`): deductions exceed the allowance, so the numeric
  /// part × 10 is *added* to taxable income (negative allowance).
  kCode,

  /// `BR`: all income taxed at the basic rate (20%).
  basicRate,

  /// `D0`: all income taxed at the higher rate (40%).
  higherRate,

  /// `D1`: all income taxed at the additional rate (45%).
  additionalRate,

  /// `NT`: no tax is deducted.
  noTax,

  /// `0T`: no personal allowance (allowance used up).
  noAllowance,
}

/// A parsed HMRC PAYE tax code (England/Wales/Scotland), 2025/26.
///
/// Numbers carry the tax-free allowance (numeric part × 10); letters carry the
/// rate treatment. Scottish (`S`) and Welsh (`C`) prefixes are accepted and the
/// remaining code is interpreted identically — Scottish *rate bands* are still
/// selected by the existing `scotland` flag on the engine, not by the prefix.
class UkTaxCode {
  const UkTaxCode({required this.mode, required this.allowance});

  final UkTaxCodeMode mode;

  /// The personal allowance implied by the code (£/yr). Zero for rate-letter
  /// codes (BR/D0/D1/0T/NT). For K codes this is the magnitude that is *added*
  /// to taxable income; [mode] disambiguates the sign.
  final double allowance;

  /// The default UK code for 2025/26 — standard personal allowance £12,570.
  static const UkTaxCode standard =
      UkTaxCode(mode: UkTaxCodeMode.allowance, allowance: 12570);

  /// Parses a raw HMRC tax-code string. Returns [standard] (1257L) for empty or
  /// unrecognised input so the calculator always produces a sensible result.
  ///
  /// Supported: `1257L` (and any nnnnL/M/N/T), `K500`, `BR`, `D0`, `D1`, `NT`,
  /// `0T`, optionally with an `S`/`C` prefix and a `W1`/`M1`/`X` emergency
  /// suffix (the emergency suffix does not change the annual figures here).
  static UkTaxCode parse(String? raw) {
    if (raw == null) return standard;
    var code = raw.toUpperCase().replaceAll(RegExp(r'\s'), '');
    if (code.isEmpty) return standard;

    // Strip a leading region prefix (S = Scotland, C = Wales/Cymru).
    if (code.startsWith('S') || code.startsWith('C')) {
      code = code.substring(1);
    }
    // Strip an emergency suffix (W1 / M1 / X) — non-cumulative flag only.
    code = code.replaceAll(RegExp(r'(W1|M1|X)$'), '');
    if (code.isEmpty) return standard;

    switch (code) {
      case 'BR':
        return const UkTaxCode(mode: UkTaxCodeMode.basicRate, allowance: 0);
      case 'D0':
        return const UkTaxCode(mode: UkTaxCodeMode.higherRate, allowance: 0);
      case 'D1':
        return const UkTaxCode(
            mode: UkTaxCodeMode.additionalRate, allowance: 0);
      case 'NT':
        return const UkTaxCode(mode: UkTaxCodeMode.noTax, allowance: 0);
      case '0T':
        return const UkTaxCode(mode: UkTaxCodeMode.noAllowance, allowance: 0);
    }

    // K code: deductions exceed allowance → add (digits × 10) to taxable income.
    final kMatch = RegExp(r'^K(\d+)$').firstMatch(code);
    if (kMatch != null) {
      final n = int.tryParse(kMatch.group(1)!) ?? 0;
      return UkTaxCode(mode: UkTaxCodeMode.kCode, allowance: n * 10.0);
    }

    // Numeric + allowance-letter (L/M/N/T): allowance = digits × 10.
    final lMatch = RegExp(r'^(\d+)[LMNT]$').firstMatch(code);
    if (lMatch != null) {
      final n = int.tryParse(lMatch.group(1)!) ?? 1257;
      return UkTaxCode(mode: UkTaxCodeMode.allowance, allowance: n * 10.0);
    }

    // Unrecognised → fall back to the standard code.
    return standard;
  }
}

// ─── UK Engine ────────────────────────────────────────────────────────────────

class UkSalaryEngine {
  UkSalaryEngine._();

  // ── 2026/27 constants ───────────────────────────────────────────────────────
  // The standard personal allowance (£12,570) now lives on UkTaxCode.standard;
  // the income-tax path derives the allowance from the supplied HMRC tax code.
  static const double _niPrimaryThreshold = 12570;
  static const double _niUpperEarningsLimit = 50270;

  // Income-tax band rates (rest-of-UK) — reused for flat-rate tax codes.
  static const double _basicRate = 0.20;
  static const double _higherRate = 0.40;
  static const double _additionalRate = 0.45;

  /// Resolves the personal allowance to apply for [adjustedGross], honouring the
  /// HMRC [taxCode] and the >£100k taper. Returns the *taxable income* directly
  /// because K codes add to (rather than subtract from) income.
  ///
  /// - allowance/0T: taxable = gross − allowance (allowance tapered above £100k).
  /// - K code: taxable = gross + (code allowance) — the >£100k taper does not
  ///   apply because a K code already has no positive allowance to taper.
  static double _taxableForCode(double adjustedGross, UkTaxCode taxCode) {
    if (taxCode.mode == UkTaxCodeMode.kCode) {
      return (adjustedGross + taxCode.allowance).clamp(0.0, double.infinity);
    }
    // Standard allowance from the code (0T → 0), then taper above £100,000.
    double pa = taxCode.allowance;
    if (adjustedGross > 100000) {
      pa = (pa - (adjustedGross - 100000) / 2).clamp(0.0, double.infinity);
    }
    return (adjustedGross - pa).clamp(0.0, double.infinity);
  }

  /// Centralized tax tables (calcwise_core). Baked-in floor; remote-updatable.
  static TaxRegistry get _reg => CalcwiseTax.registry;

  /// England, Wales & N. Ireland income tax 2025/26. Bands sourced from the
  /// shared [TaxRegistry] (`uk` 2025); the HMRC tax code (allowance/taper/K/0T)
  /// is resolved by [_taxableForCode] first. (Computing bands via the registry
  /// also corrects the old £42,384 additional-rate cumulative discontinuity.)
  static double _englandWalesIncomeTax(double grossAnnual,
      {double salarySacrifice = 0, UkTaxCode? taxCode}) {
    final adjustedGross = grossAnnual - salarySacrifice;
    final taxable = _taxableForCode(adjustedGross, taxCode ?? UkTaxCode.standard);
    if (taxable <= 0) return 0;
    final ukBands = _reg.annual('uk', 2025)?.bands;
    if (ukBands == null) return 0.0; // baked data guarantees presence; guard only
    return taxOnIncome(ukBands, taxable);
  }

  /// Scottish income tax 2025/26 (6 bands). Bands sourced from the shared
  /// [TaxRegistry] (`uk_scotland` 2025) — this CORRECTS previously stale 2024/25
  /// thresholds (starter £2,306→£2,827, basic £13,991→£14,921) and the
  /// advanced/top boundary. The HMRC tax code is resolved by [_taxableForCode].
  static double _scottishIncomeTax(double grossAnnual,
      {double salarySacrifice = 0, UkTaxCode? taxCode}) {
    final adjustedGross = grossAnnual - salarySacrifice;
    final taxable = _taxableForCode(adjustedGross, taxCode ?? UkTaxCode.standard);
    if (taxable <= 0) return 0;
    final scotBands = _reg.annual('uk_scotland', 2025)?.bands;
    if (scotBands == null) return 0.0; // baked data guarantees presence; guard only
    return taxOnIncome(scotBands, taxable);
  }

  /// Compute income tax based on region (Scotland vs rest of UK), honouring an
  /// optional HMRC [taxCode]. Flat-rate codes (BR/D0/D1) and NT bypass the bands
  /// entirely and apply to the full post-sacrifice income (no allowance).
  static double incomeTax(
    double grossAnnual, {
    bool scotland = false,
    double salarySacrifice = 0,
    UkTaxCode? taxCode,
  }) {
    final code = taxCode ?? UkTaxCode.standard;
    final taxableAll = (grossAnnual - salarySacrifice).clamp(0.0, double.infinity);
    switch (code.mode) {
      case UkTaxCodeMode.noTax:
        return 0;
      case UkTaxCodeMode.basicRate:
        return taxableAll * _basicRate;
      case UkTaxCodeMode.higherRate:
        return taxableAll * _higherRate;
      case UkTaxCodeMode.additionalRate:
        return taxableAll * _additionalRate;
      case UkTaxCodeMode.allowance:
      case UkTaxCodeMode.kCode:
      case UkTaxCodeMode.noAllowance:
        return scotland
            ? _scottishIncomeTax(grossAnnual,
                salarySacrifice: salarySacrifice, taxCode: code)
            : _englandWalesIncomeTax(grossAnnual,
                salarySacrifice: salarySacrifice, taxCode: code);
    }
  }

  /// NI Class 1 (employee) 2026/27: 8% on £12,570–£50,270, 2% above.
  /// Salary sacrifice reduces NIable earnings.
  static double nationalInsurance(double grossAnnual,
      {double salarySacrifice = 0}) {
    final niableGross = grossAnnual - salarySacrifice;
    if (niableGross <= _niPrimaryThreshold) return 0;
    final lower =
        (niableGross.clamp(_niPrimaryThreshold, _niUpperEarningsLimit) -
                _niPrimaryThreshold) *
            0.08;
    final upper = niableGross > _niUpperEarningsLimit
        ? (niableGross - _niUpperEarningsLimit) * 0.02
        : 0.0;
    return lower + upper;
  }

  /// Student loan repayment 2025/26 (9% above plan threshold).
  /// Plan 1: £24,990 | Plan 2: £27,295 | Plan 4 (Scotland): £31,395 | Plan 5: £25,000
  /// Plan 0 / negative = none.
  static double studentLoanRepayment(double grossAnnual, {int plan = 2}) {
    final threshold = switch (plan) {
      1 => 24990.0,
      4 => 31395.0, // Plan 4 (Scotland) 2025/26
      5 => 25000.0,
      _ => 27295.0, // Plan 2
    };
    if (grossAnnual <= threshold) return 0;
    return (grossAnnual - threshold) * 0.09;
  }

  /// Postgraduate Loan (Plan 3) repayment 2025/26: 6% above £21,000.
  /// Cumulable with a main undergraduate plan (1/2/4/5).
  static double postgradLoanRepayment(double grossAnnual) {
    const threshold = 21000.0;
    if (grossAnnual <= threshold) return 0;
    return (grossAnnual - threshold) * 0.06;
  }

  // ── Auto-enrolment / qualifying earnings (2025/26) ──────────────────────────
  static const double _aeLowerThreshold = 6240; // qualifying earnings band floor
  static const double _aeUpperThreshold = 50270; // qualifying earnings band ceiling

  /// Auto-enrolment pension contribution on "qualifying earnings": the slice of
  /// pay between £6,240 and £50,270. Statutory employee minimum is 5%.
  /// Returned amount is treated as salary sacrifice for tax/NI in [calculate].
  static double autoEnrolmentContribution(double grossAnnual,
      {double employeeRate = 0.05}) {
    final band = (grossAnnual.clamp(_aeLowerThreshold, _aeUpperThreshold) -
            _aeLowerThreshold)
        .clamp(0.0, double.infinity);
    return band * employeeRate;
  }

  /// Calculate salary sacrifice tax + NI savings for display purposes.
  /// Returns (incomeTaxSaving, niSaving).
  static (double incomeTaxSaving, double niSaving) salarySacrificeSavings(
    double grossAnnual,
    double salarySacrifice, {
    bool scotland = false,
  }) {
    if (salarySacrifice <= 0) return (0, 0);
    final taxWithout = incomeTax(grossAnnual, scotland: scotland);
    final taxWith = incomeTax(grossAnnual,
        scotland: scotland, salarySacrifice: salarySacrifice);
    final niWithout = nationalInsurance(grossAnnual);
    final niWith =
        nationalInsurance(grossAnnual, salarySacrifice: salarySacrifice);
    return (taxWithout - taxWith, niWithout - niWith);
  }

  /// [studentLoan]    – include student loan repayment (default false).
  /// [loanPlan]       – 1, 2 (default), 4 or 5.
  /// [postgradLoan]   – include Postgraduate (Plan 3) loan, 6% above £21,000.
  /// [scotland]       – use Scottish income tax rates (default false).
  /// [salarySacrifice] – annual salary sacrifice / SMART pension amount (£).
  /// [autoEnrolment]  – when true, add a qualifying-earnings AE pension
  ///                    contribution ([autoEnrolmentRate], default 5%) on top
  ///                    of [salarySacrifice], treated as pre-tax.
  /// [secondIncome]   – additional gross income (£/yr) cumulated for tax/NI.
  static SalaryResult calculate(
    double grossAnnual, {
    bool studentLoan = false,
    int loanPlan = 2,
    bool postgradLoan = false,
    bool scotland = false,
    double salarySacrifice = 0,
    bool autoEnrolment = false,
    double autoEnrolmentRate = 0.05,
    double secondIncome = 0,
    UkTaxCode? taxCode,
  }) {
    // Cumulate the second income into the gross used for all UK calculations:
    // tax bands and NI apply to the combined total, which is the most useful
    // figure for a take-home calculator.
    grossAnnual = grossAnnual + (secondIncome > 0 ? secondIncome : 0);

    // Auto-enrolment contribution is added to any explicit salary sacrifice.
    final aeContribution = autoEnrolment
        ? autoEnrolmentContribution(grossAnnual, employeeRate: autoEnrolmentRate)
        : 0.0;
    final totalSacrifice = salarySacrifice + aeContribution;

    final income = incomeTax(grossAnnual,
        scotland: scotland, salarySacrifice: totalSacrifice, taxCode: taxCode);
    final ni =
        nationalInsurance(grossAnnual, salarySacrifice: totalSacrifice);
    final sl =
        studentLoan ? studentLoanRepayment(grossAnnual, plan: loanPlan) : 0.0;
    final pg = postgradLoan ? postgradLoanRepayment(grossAnnual) : 0.0;
    // ficaTax stores NI + student loan(s) so the result model stays unchanged.
    final ficaTotal = ni + sl + pg;
    final total = income + ficaTotal;
    final net = grossAnnual - total;
    return SalaryResult(
      grossAnnual: grossAnnual,
      federalTax: income,
      ficaTax: ficaTotal,
      stateTax: 0,
      totalTax: total,
      netAnnual: net,
      netMonthly: net / 12,
      netBiWeekly: net / 26,
      netWeekly: net / 52,
      effectiveRate: total / grossAnnual * 100,
    );
  }

  /// Reverse calculation: find the gross salary whose take-home equals
  /// [targetNet], given the same UK options used by [calculate].
  ///
  /// This introduces **no new tax values** — it wraps the existing forward
  /// [calculate] (which already applies the real 2025/26 PAYE bands, NI,
  /// pension sacrifice and student-loan rules) as the monotonic `forward`
  /// function for the shared [CalcwiseReverseSolver]. The reverse therefore
  /// inherits whatever rates the forward uses automatically.
  ///
  /// Bounds: `lo = 0`, `hi` = a generous multiple of the target net (gross is
  /// always >= net and effective rates stay well under ~50%, so 3x plus
  /// headroom covers every realistic case; the solver clamps gracefully).
  static double grossFromNet(
    double targetNet, {
    bool studentLoan = false,
    int loanPlan = 2,
    bool postgradLoan = false,
    bool scotland = false,
    double salarySacrifice = 0,
    bool autoEnrolment = false,
    double autoEnrolmentRate = 0.05,
    UkTaxCode? taxCode,
  }) {
    if (targetNet <= 0) return 0;

    double netFromGross(double gross) => calculate(
          gross,
          studentLoan: studentLoan,
          loanPlan: loanPlan,
          postgradLoan: postgradLoan,
          scotland: scotland,
          salarySacrifice: salarySacrifice,
          autoEnrolment: autoEnrolment,
          autoEnrolmentRate: autoEnrolmentRate,
          taxCode: taxCode,
        ).netAnnual;

    return CalcwiseReverseSolver.solve(
      forward: netFromGross,
      target: targetNet,
      lo: 0,
      hi: targetNet * 3 + 25000, // headroom for low targets near the allowance
    );
  }
}

// ─── CA Engine ────────────────────────────────────────────────────────────────

class CaSalaryEngine {
  CaSalaryEngine._();

  /// Centralized, effective-dated tax tables (calcwise_core). Baked-in floor;
  /// the same registry can be swapped for a remote-updated dataset.
  static TaxRegistry get _reg => CalcwiseTax.registry;

  /// Federal tax 2025 — brackets + Basic Personal Amount now sourced from the
  /// shared [TaxRegistry] (`ca_federal` 2025), not hardcoded here. The lowest
  /// band carries the official 14.5% blended 2025 rate (15%→14% on 2025-07-01).
  /// Source of the data: canada.ca (CRA), verified 2026-06-13. See the
  /// calcwise-tax-data repo for the canonical dataset + golden tests.
  static double federalTax(double grossAnnual) {
    final set = _reg.annual('ca_federal', 2025);
    if (set == null) return 0.0; // baked data guarantees presence; guard only
    final taxable = (grossAnnual - (set.basicPersonalAmount ?? 0))
        .clamp(0.0, double.infinity);
    return taxOnIncome(set.bands, taxable);
  }

  // ── 2026 CPP / EI constants ─────────────────────────────────────────────────
  // Sources (verified 2026-06-13):
  //  - CPP rates/maximums & CPP2: canada.ca/en/revenue-agency/.../canada-pension-plan-cpp/
  //    cpp-contribution-rates-maximums-exemptions.html
  //    YMPE 2026 = $74,600 · YAMPE 2026 = $85,000 · CPP1 5.95% · CPP2 4.00%.
  //    QPP 2026 (Revenu Québec) shares the same YMPE/YAMPE ceilings; QPP base
  //    employee rate is 5.4% vs CPP 5.95% — modelled here with the single CPP
  //    rate as a portfolio-wide simplification (see TODO in calculate()).
  //  - EI 2026: canada.ca/.../employment-insurance-ei/ei-premium-rates-maximums.html
  //    MIE 2026 = $68,900 · employee rate (rest of Canada) = 1.63%
  //    (Quebec employee rate is 1.30% due to QPIP — not modelled separately).
  static const double _cpp1BasicExemption = 3500;
  static const double _ympe2026 = 74600; // CPP1 / QPP1 first ceiling (YMPE)
  static const double _yampe2026 = 85000; // CPP2 / QPP2 second ceiling (YAMPE)
  static const double _cpp1Rate = 0.0595;
  static const double _cpp2Rate = 0.04;
  static const double _eiInsurableMax2026 = 68900;
  static const double _eiRate2026 = 0.0163; // employee rate (rest of Canada)

  /// CPP1 2026: 5.95% on earnings $3,500–$74,600 (YMPE).
  static double cpp1(double grossAnnual) {
    final pensionable =
        grossAnnual.clamp(_cpp1BasicExemption, _ympe2026) - _cpp1BasicExemption;
    return pensionable * _cpp1Rate;
  }

  /// CPP2 / QPP2 2026: 4.00% on earnings from YMPE ($74,600) up to YAMPE
  /// ($85,000). Second additional contribution, phased in 2024, fully effective
  /// since 2025.
  static double cpp2(double grossAnnual) {
    if (grossAnnual <= _ympe2026) return 0;
    return (min(grossAnnual, _yampe2026) - _ympe2026) * _cpp2Rate;
  }

  /// Combined CPP (CPP1 + CPP2) 2026.
  static double cpp(double grossAnnual) =>
      cpp1(grossAnnual) + cpp2(grossAnnual);

  /// EI 2026: 1.63% (rest of Canada) up to insurable max $68,900.
  static double ei(double grossAnnual) {
    return grossAnnual.clamp(0, _eiInsurableMax2026) * _eiRate2026;
  }

  /// Applies progressive brackets to [income].
  /// [brackets] is a list of (upperBound, rate) pairs in ascending order;
  /// the last entry's upperBound is treated as infinity.
  static double _progressive(
      double income, List<(double upper, double rate)> brackets) {
    double tax = 0;
    double prev = 0;
    for (int i = 0; i < brackets.length; i++) {
      final upper = i < brackets.length - 1 ? brackets[i].$1 : double.infinity;
      final rate = brackets[i].$2;
      if (income <= prev) break;
      final taxable = (income < upper ? income : upper) - prev;
      tax += taxable * rate;
      prev = upper;
    }
    return tax;
  }

  /// Ontario 2025: 5 progressive brackets, BPA $12,747.
  static double _ontarioProvincialTax(double grossAnnual) {
    final taxable = (grossAnnual - 12747).clamp(0.0, double.infinity);
    return _progressive(taxable, [
      (52886, 0.0505),
      (105775, 0.0915),
      (150000, 0.1116),
      (220000, 0.1216),
      (double.infinity, 0.1316),
    ]);
  }

  /// British Columbia 2025: 7 progressive brackets, BPA $11,981.
  static double _bcProvincialTax(double grossAnnual) {
    final taxable = (grossAnnual - 11981).clamp(0.0, double.infinity);
    return _progressive(taxable, [
      (49279, 0.0506),
      (98560, 0.0770),
      (113158, 0.1050),
      (137407, 0.1229),
      (186306, 0.1470),
      (259829, 0.1680),
      (double.infinity, 0.2050),
    ]);
  }

  /// Quebec 2025 provincial tax — 4 progressive brackets.
  /// Personal basic amount: $18,571 CAD (2025).
  static double _quebecProvincialTax(double grossAnnual) {
    // Taxable income after QC basic personal amount
    final taxable = (grossAnnual - 18571).clamp(0.0, double.infinity);
    if (taxable <= 53255) return taxable * 0.14;
    if (taxable <= 106495) return 7455.70 + (taxable - 53255) * 0.19;
    if (taxable <= 129590) return 17571.30 + (taxable - 106495) * 0.24;
    return 23113.10 + (taxable - 129590) * 0.2575;
  }

  /// Quebec federal tax abatement (2026): QC residents pay 16.5% less
  /// federal income tax because QC funds its own parallel social programs.
  static double quebecFederalAbatement(double grossAnnual) =>
      federalTax(grossAnnual) * 0.165;

  /// Provincial income-tax. ON and BC use proper progressive brackets (2025).
  /// Other provinces use calibrated flat rates as reasonable approximations.
  static double provincialTax(double grossAnnual, String province) {
    switch (province) {
      case 'QC':
        return _quebecProvincialTax(grossAnnual);
      case 'ON':
        return _ontarioProvincialTax(grossAnnual);
      case 'BC':
        return _bcProvincialTax(grossAnnual);
      default:
        // Flat-rate approximations for remaining provinces (2025 estimates).
        const rates = <String, double>{
          'AB': 0.10,
          'MB': 0.108,
          'SK': 0.105,
          'NS': 0.0879,
          'NB': 0.094,
          'NL': 0.087,
          'PE': 0.098,
        };
        final taxable = (grossAnnual - 10000).clamp(0.0, double.infinity);
        return taxable * (rates[province] ?? 0.0505);
    }
  }

  /// [secondIncome] – additional employment income (annual). Cumulated with the
  /// primary income; federal + provincial brackets apply to the total.
  static SalaryResult calculate(double grossAnnual, String province,
      {double secondIncome = 0}) {
    grossAnnual = grossAnnual + (secondIncome > 0 ? secondIncome : 0);
    final fed = federalTax(grossAnnual);
    // Quebec residents receive a 16.5% abatement on their federal tax
    // (QC runs its own equivalent social programs).
    final fedAbatement =
        province == 'QC' ? quebecFederalAbatement(grossAnnual) : 0.0;
    // TODO(qc): Quebec uses QPP (base employee rate 5.4%) and a lower EI rate
    // (1.30% vs 1.63%) because of the Quebec Parental Insurance Plan. We model
    // both QC and the rest of Canada with the single CPP rate (5.95%) and the
    // rest-of-Canada EI rate (1.63%) — a small over-estimate of QC deductions.
    // The CPP2/QPP2 second-ceiling logic ($74,600→$85,000 @ 4%) is identical.
    final cppAmt = cpp(grossAnnual);
    final eiAmt = ei(grossAnnual);
    final prov = provincialTax(grossAnnual, province);
    final total = (fed - fedAbatement) + cppAmt + eiAmt + prov;
    final net = grossAnnual - total;
    return SalaryResult(
      grossAnnual: grossAnnual,
      federalTax: fed - fedAbatement, // effective federal after QC abatement
      ficaTax: cppAmt + eiAmt, // CPP + EI lumped together (CPP1+CPP2+EI)
      stateTax: prov,
      totalTax: total,
      netAnnual: net,
      netMonthly: net / 12,
      netBiWeekly: net / 26,
      netWeekly: net / 52,
      effectiveRate: total / grossAnnual * 100,
    );
  }

  /// Reverse calculation: find the gross salary that yields [targetNet] after
  /// all deductions (federal + provincial tax, CPP/CPP2, EI) for [province].
  ///
  /// Wraps the existing FORWARD [calculate] function — `gross → netAnnual` — as
  /// the monotonic forward passed to [CalcwiseReverseSolver]. The reverse therefore
  /// inherits every verified tax rate/threshold of the forward; it introduces no
  /// new fiscal values. Bounds: lo = 0, hi = a generous multiple of the target
  /// net (the marginal take-home keeps gross < ~2.5× net even in the top band).
  static double grossFromNet(double targetNet, String province) {
    if (targetNet <= 0) return 0;
    return CalcwiseReverseSolver.solve(
      forward: (gross) => calculate(gross, province).netAnnual,
      target: targetNet,
      lo: 0,
      hi: targetNet * 3,
    );
  }

  static const List<String> provinces = [
    'AB',
    'BC',
    'MB',
    'NB',
    'NL',
    'NS',
    'ON',
    'PE',
    'QC',
    'SK',
  ];
}
