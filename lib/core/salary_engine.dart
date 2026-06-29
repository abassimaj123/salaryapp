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

  /// Federal income tax 2026 — brackets + standard deduction now sourced from
  /// the shared [TaxRegistry] (`us_federal` 2026; default = single filer, `mfj`
  /// variant for married filing jointly). [preTaxDeductions] reduces taxable
  /// income (e.g. 401k, HSA, FSA). Data verified vs IRS (Rev. Proc. 2025 +
  /// OBBBA standard deduction). See the calcwise-tax-data repo.
  static double federalTax(
    double grossAnnual, {
    bool marriedFilingJointly = false,
    double preTaxDeductions = 0,
  }) {
    final set = _reg.annual('us_federal', 2026,
            status: marriedFilingJointly ? 'mfj' : null) ??
        _reg.annual('us_federal', 2026);
    if (set == null) return 0.0; // baked data guarantees presence; guard only
    final taxable =
        (grossAnnual - (set.basicPersonalAmount ?? 0) - preTaxDeductions)
            .clamp(0.0, double.infinity);
    return taxOnIncome(set.bands, taxable);
  }

  /// FICA 2026: Social Security (6.2% up to the $184,500 SS wage base) +
  /// Medicare (1.45%) + Additional Medicare surtax (0.9% above $200,000 single).
  /// Wage base, Medicare rate and additional-Medicare surtax now sourced from
  /// the shared [TaxRegistry] (`us_federal` 2026 contributions), not hardcoded.
  static double fica(double grossAnnual) {
    final ssC = _reg.contribution('us_federal', 2026, 'socialSecurity');
    final medC = _reg.contribution('us_federal', 2026, 'medicare');
    final ssRate = ssC?.rate ?? 0.062;
    final ssWageBase = ssC?.ceiling ?? 184500;
    final medRate = medC?.rate ?? 0.0145;
    final addlMedRate = medC?.additionalRate ?? 0.009;
    final addlMedThreshold = medC?.additionalThreshold ?? 200000;
    final ss = min(grossAnnual, ssWageBase) * ssRate;
    final medicare = grossAnnual * medRate;
    final additionalMedicare = grossAnnual > addlMedThreshold
        ? (grossAnnual - addlMedThreshold) * addlMedRate
        : 0.0;
    return ss + medicare + additionalMedicare;
  }

  /// State income tax — sourced from the shared [TaxRegistry] (`us_<postal>`
  /// 2026, single filer), not hardcoded here. This eliminates the previous
  /// divergent-duplicate copy of all 51 state tables.
  ///
  /// Each jurisdiction's bracket set carries the verified 2026 bands plus the
  /// state standard deduction (`basicPersonalAmount`), so [AnnualBracketSet.taxOn]
  /// applies the standard deduction first and then the marginal bands — the
  /// accurate single-filer model. No-tax states (TX/FL/NV/…) carry a single
  /// rate-0 band, so `taxOn` returns 0 naturally.
  ///
  /// Data: Tax Foundation 2026, verified 2026-06-29 (calcwise-tax-data repo,
  /// `research/us_states_2026.md`). MFJ state brackets are NOT yet in the
  /// registry; this path is single-filer for every state regardless of the
  /// [calculate] `marriedFilingJointly` flag (federal MFJ is honoured; state is
  /// approximated with single brackets — flagged for a follow-up migration).
  ///
  /// Unknown / unrecognised state codes (no `us_<code>` jurisdiction) fall back
  /// to a 5% flat approximation, preserving the previous default contract.
  static double stateTax(double grossAnnual, String state) {
    final set = _reg.annual('us_${state.toLowerCase()}', 2026);
    if (set == null) {
      // Code not present in the registry → 5% flat approximation (legacy default).
      return grossAnnual * 0.05;
    }
    return set.taxOn(grossAnnual);
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

  /// England, Wales & N. Ireland income tax 2026/27. Bands sourced from the
  /// shared [TaxRegistry] (`uk` 2026); the HMRC tax code (allowance/taper/K/0T)
  /// is resolved by [_taxableForCode] first. (Computing bands via the registry
  /// also corrects the old £42,384 additional-rate cumulative discontinuity.)
  static double _englandWalesIncomeTax(double grossAnnual,
      {double salarySacrifice = 0, UkTaxCode? taxCode}) {
    final adjustedGross = grossAnnual - salarySacrifice;
    final taxable = _taxableForCode(adjustedGross, taxCode ?? UkTaxCode.standard);
    if (taxable <= 0) return 0;
    final ukBands = _reg.annual('uk', 2026)?.bands;
    if (ukBands == null) return 0.0; // baked data guarantees presence; guard only
    return taxOnIncome(ukBands, taxable);
  }

  /// Scottish income tax 2026/27 (6 bands). Bands sourced from the shared
  /// [TaxRegistry] (`uk_scotland` 2026). The HMRC tax code is resolved by
  /// [_taxableForCode].
  static double _scottishIncomeTax(double grossAnnual,
      {double salarySacrifice = 0, UkTaxCode? taxCode}) {
    final adjustedGross = grossAnnual - salarySacrifice;
    final taxable = _taxableForCode(adjustedGross, taxCode ?? UkTaxCode.standard);
    if (taxable <= 0) return 0;
    final scotBands = _reg.annual('uk_scotland', 2026)?.bands;
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
  /// Salary sacrifice reduces NIable earnings. Thresholds and rates now sourced
  /// from the shared [TaxRegistry] (`uk` 2026 `niClass1`), not hardcoded.
  static double nationalInsurance(double grossAnnual,
      {double salarySacrifice = 0}) {
    final ni = _reg.contribution('uk', 2026, 'niClass1');
    final pt = ni?.primaryThreshold ?? _niPrimaryThreshold;
    final uel = ni?.upperEarningsLimit ?? _niUpperEarningsLimit;
    final mainRate = ni?.mainRate ?? 0.08;
    final upperRate = ni?.upperRate ?? 0.02;
    final niableGross = grossAnnual - salarySacrifice;
    if (niableGross <= pt) return 0;
    final lower = (niableGross.clamp(pt, uel) - pt) * mainRate;
    final upper = niableGross > uel ? (niableGross - uel) * upperRate : 0.0;
    return lower + upper;
  }

  /// Student loan repayment 2026/27 (9% above plan threshold). Thresholds + rate
  /// now sourced from the shared [TaxRegistry] (`studentLoan('uk',2026,plan)`):
  /// Plan 1: £26,900 | Plan 2: £29,385 | Plan 4 (Scotland): £33,795 | Plan 5: £25,000
  /// Plan 0 / negative = none. Sources: gov.uk / House of Commons Library.
  static double studentLoanRepayment(double grossAnnual, {int plan = 2}) {
    final planKey = switch (plan) {
      1 => 'plan1',
      4 => 'plan4',
      5 => 'plan5',
      _ => 'plan2',
    };
    final sl = _reg.studentLoan('uk', 2026, planKey);
    final threshold = sl?.threshold ??
        switch (plan) {
          1 => 26900.0,
          4 => 33795.0,
          5 => 25000.0,
          _ => 29385.0,
        };
    final rate = sl?.rate ?? 0.09;
    if (grossAnnual <= threshold) return 0;
    return (grossAnnual - threshold) * rate;
  }

  /// Postgraduate Loan (Plan 3) repayment 2026/27: 6% above £21,000. Threshold +
  /// rate sourced from the shared [TaxRegistry] (`studentLoan('uk',2026,'postgrad')`).
  /// Cumulable with a main undergraduate plan (1/2/4/5).
  static double postgradLoanRepayment(double grossAnnual) {
    final sl = _reg.studentLoan('uk', 2026, 'postgrad');
    final threshold = sl?.threshold ?? 21000.0;
    final rate = sl?.rate ?? 0.06;
    if (grossAnnual <= threshold) return 0;
    return (grossAnnual - threshold) * rate;
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

  /// Federal tax 2026 — brackets + Basic Personal Amount now sourced from the
  /// shared [TaxRegistry] (`ca_federal` 2026), not hardcoded here. The lowest
  /// band carries the 2026 lowest rate (14%, the first full year after the
  /// 15%→14% reduction took effect mid-2025).
  /// Source of the data: canada.ca (CRA). See the calcwise-tax-data repo for
  /// the canonical dataset + golden tests.
  static double federalTax(double grossAnnual) {
    final set = _reg.annual('ca_federal', 2026);
    if (set == null) return 0.0; // baked data guarantees presence; guard only
    final taxable = (grossAnnual - (set.basicPersonalAmount ?? 0))
        .clamp(0.0, double.infinity);
    return taxOnIncome(set.bands, taxable);
  }

  // ── 2026 CPP / QPP / EI — sourced from the shared TaxRegistry ────────────────
  // All rates/ceilings now come from CalcwiseTax (`ca_federal` / `ca_qc` 2026
  // contributions) rather than hardcoded constants:
  //  - ca_federal cpp  {rate .0595, exemption 3500, ceiling 74600 (YMPE)}
  //  - ca_federal cpp2 {rate .04, lowerThreshold 74600, ceiling 85000 (YAMPE)}
  //  - ca_federal ei   {rate .0163, ceiling 68900}
  //  - ca_qc      qpp  {rate .063, exemption 3500, ceiling 74600}
  //  - ca_qc      qpp2 {rate .04, lowerThreshold 74600, ceiling 85000}
  //  - ca_qc      ei   {rate .013, ceiling 68900} (reduced — QC runs QPIP)
  // Literals below are FALLBACKS only (baked data guarantees the registry path).
  static const double _cpp1BasicExemption = 3500;
  static const double _ympe2026 = 74600; // CPP1 / QPP1 first ceiling (YMPE)
  static const double _yampe2026 = 85000; // CPP2 / QPP2 second ceiling (YAMPE)
  static const double _eiInsurableMax2026 = 68900;

  /// CPP1 2026: 5.95% on earnings $3,500–$74,600 (YMPE). Registry-sourced.
  static double cpp1(double grossAnnual) {
    final c = _reg.contribution('ca_federal', 2026, 'cpp');
    final exemption = c?.exemption ?? _cpp1BasicExemption;
    final ceiling = c?.ceiling ?? _ympe2026;
    final rate = c?.rate ?? 0.0595;
    final pensionable = grossAnnual.clamp(exemption, ceiling) - exemption;
    return pensionable * rate;
  }

  /// CPP2 / QPP2 2026: 4.00% on earnings from YMPE ($74,600) up to YAMPE
  /// ($85,000). Second additional contribution, fully effective since 2025.
  /// Registry-sourced (`ca_federal` `cpp2`).
  static double cpp2(double grossAnnual) {
    final c = _reg.contribution('ca_federal', 2026, 'cpp2');
    final lower = c?.lowerThreshold ?? _ympe2026;
    final ceiling = c?.ceiling ?? _yampe2026;
    final rate = c?.rate ?? 0.04;
    if (grossAnnual <= lower) return 0;
    return (min(grossAnnual, ceiling) - lower) * rate;
  }

  /// Combined CPP (CPP1 + CPP2) 2026.
  static double cpp(double grossAnnual) =>
      cpp1(grossAnnual) + cpp2(grossAnnual);

  /// QPP1 2026: 6.30% on earnings $3,500–$74,600 (Quebec employees only).
  /// Registry-sourced (`ca_qc` `qpp`).
  static double qpp1(double grossAnnual) {
    final c = _reg.contribution('ca_qc', 2026, 'qpp');
    final exemption = c?.exemption ?? _cpp1BasicExemption;
    final ceiling = c?.ceiling ?? _ympe2026;
    final rate = c?.rate ?? 0.063;
    final pensionable = grossAnnual.clamp(exemption, ceiling) - exemption;
    return pensionable * rate;
  }

  /// QPP2 2026: second additional QPP contribution (YMPE→YAMPE).
  /// Registry-sourced (`ca_qc` `qpp2`); rate/ceiling = CPP2.
  static double qpp2(double grossAnnual) {
    final c = _reg.contribution('ca_qc', 2026, 'qpp2');
    final lower = c?.lowerThreshold ?? _ympe2026;
    final ceiling = c?.ceiling ?? _yampe2026;
    final rate = c?.rate ?? 0.04;
    if (grossAnnual <= lower) return 0;
    return (min(grossAnnual, ceiling) - lower) * rate;
  }

  /// Combined QPP (QPP1 + QPP2) 2026.
  static double qpp(double grossAnnual) =>
      qpp1(grossAnnual) + qpp2(grossAnnual);

  /// EI 2026: 1.63% (rest of Canada) up to insurable max $68,900.
  /// Registry-sourced (`ca_federal` `ei`).
  static double ei(double grossAnnual) {
    final c = _reg.contribution('ca_federal', 2026, 'ei');
    final ceiling = c?.ceiling ?? _eiInsurableMax2026;
    final rate = c?.rate ?? 0.0163;
    return grossAnnual.clamp(0, ceiling) * rate;
  }

  /// EI 2026 Quebec: 1.30% up to insurable max $68,900 (QPIP offset).
  /// Registry-sourced (`ca_qc` `ei`).
  static double eiQc(double grossAnnual) {
    final c = _reg.contribution('ca_qc', 2026, 'ei');
    final ceiling = c?.ceiling ?? _eiInsurableMax2026;
    final rate = c?.rate ?? 0.013;
    return grossAnnual.clamp(0, ceiling) * rate;
  }

  /// Maps a two-letter province postal code to its registry jurisdiction code.
  static const Map<String, String> _provinceJurisdiction = {
    'ON': 'ca_on',
    'QC': 'ca_qc',
    'BC': 'ca_bc',
    'AB': 'ca_ab',
    'MB': 'ca_mb',
    'SK': 'ca_sk',
    'NS': 'ca_ns',
    'NB': 'ca_nb',
    'NL': 'ca_nl',
    'PE': 'ca_pe',
  };

  /// Quebec federal tax abatement (2026): QC residents pay 16.5% less federal
  /// income tax because QC funds its own parallel social programs. The 0.165
  /// rate is read from the `ca_qc` jurisdiction's [federalAbatement] when
  /// present, falling back to the long-standing 0.165 constant.
  static double quebecFederalAbatement(double grossAnnual) {
    final abatement = _reg.jurisdiction('ca_qc')?.federalAbatement ?? 0.165;
    return federalTax(grossAnnual) * abatement;
  }

  /// Provincial income tax — all provinces now sourced from the shared
  /// [TaxRegistry] (`ca_<prov>` 2026, single filer): each jurisdiction carries
  /// its verified 2026 progressive bands plus its basic personal amount, and
  /// [AnnualBracketSet.taxOn] applies the BPA first then the marginal bands.
  /// This replaces the previous mix of hardcoded ON/BC/QC brackets and flat-rate
  /// approximations for the other provinces. Unknown codes fall back to a 5.05%
  /// flat approximation with a $10,000 exemption (legacy default contract).
  static double provincialTax(double grossAnnual, String province) {
    final code = _provinceJurisdiction[province];
    final set = code == null ? null : _reg.annual(code, 2026);
    if (set == null) {
      final taxable = (grossAnnual - 10000).clamp(0.0, double.infinity);
      return taxable * 0.0505;
    }
    return set.taxOn(grossAnnual);
  }

  /// [secondIncome] – additional employment income (annual). Cumulated with the
  /// primary income; federal + provincial brackets apply to the total.
  static SalaryResult calculate(double grossAnnual, String province,
      {double secondIncome = 0}) {
    grossAnnual = grossAnnual + (secondIncome > 0 ? secondIncome : 0);
    final fed = federalTax(grossAnnual);
    // Quebec residents receive a 16.5% abatement on their federal tax
    // (QC runs its own equivalent social programs).
    final isQc = province == 'QC';
    final fedAbatement = isQc ? quebecFederalAbatement(grossAnnual) : 0.0;
    final cppAmt = isQc ? qpp(grossAnnual) : cpp(grossAnnual);
    final eiAmt = isQc ? eiQc(grossAnnual) : ei(grossAnnual);
    final prov = provincialTax(grossAnnual, province);
    final total = (fed - fedAbatement) + cppAmt + eiAmt + prov;
    final net = grossAnnual - total;
    return SalaryResult(
      grossAnnual: grossAnnual,
      federalTax: fed - fedAbatement, // effective federal after QC abatement
      ficaTax: cppAmt + eiAmt, // CPP/QPP + EI lumped together
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
