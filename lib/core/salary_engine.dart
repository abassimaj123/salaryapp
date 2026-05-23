// ignore_for_file: constant_identifier_names

import 'dart:math' show min;

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

  // ── 2025 tax constants ──────────────────────────────────────────────────────
  static const double _stdDeductionSingle2025 = 15000;
  static const double _stdDeductionMfj2025 = 30000;

  /// Federal income tax brackets 2025 — single filer (post-standard deduction).
  /// Pass [taxableIncome] = grossAnnual − standard deduction − any pre-tax deductions.
  static double _federalTaxOnTaxable(double taxableIncome) {
    if (taxableIncome <= 0) return 0;
    if (taxableIncome <= 11925) return taxableIncome * 0.10;
    if (taxableIncome <= 48475) return 1192.50 + (taxableIncome - 11925) * 0.12;
    if (taxableIncome <= 103350) return 5578.50 + (taxableIncome - 48475) * 0.22;
    if (taxableIncome <= 197300) return 17651.00 + (taxableIncome - 103350) * 0.24;
    if (taxableIncome <= 250525) return 40199.00 + (taxableIncome - 197300) * 0.32;
    if (taxableIncome <= 626350) return 57231.00 + (taxableIncome - 250525) * 0.35;
    return 188769.75 + (taxableIncome - 626350) * 0.37;
  }

  /// Federal income tax brackets 2025 — married filing jointly (post-standard deduction).
  static double _federalTaxOnTaxableMfj(double taxableIncome) {
    if (taxableIncome <= 0) return 0;
    if (taxableIncome <= 23850) return taxableIncome * 0.10;
    if (taxableIncome <= 96950) return 2385.00 + (taxableIncome - 23850) * 0.12;
    if (taxableIncome <= 206700) return 11157.00 + (taxableIncome - 96950) * 0.22;
    if (taxableIncome <= 394600) return 35302.00 + (taxableIncome - 206700) * 0.24;
    if (taxableIncome <= 501050) return 80398.00 + (taxableIncome - 394600) * 0.32;
    if (taxableIncome <= 751600) return 114462.00 + (taxableIncome - 501050) * 0.35;
    return 202154.50 + (taxableIncome - 751600) * 0.37;
  }

  /// Federal income tax 2025. Supports single and MFJ filing statuses.
  /// [preTaxDeductions] reduces taxable income (e.g. 401k, HSA, FSA).
  static double federalTax(
    double grossAnnual, {
    bool marriedFilingJointly = false,
    double preTaxDeductions = 0,
  }) {
    final stdDeduction = marriedFilingJointly
        ? _stdDeductionMfj2025
        : _stdDeductionSingle2025;
    final taxableIncome =
        (grossAnnual - stdDeduction - preTaxDeductions).clamp(0.0, double.infinity);
    return marriedFilingJointly
        ? _federalTaxOnTaxableMfj(taxableIncome)
        : _federalTaxOnTaxable(taxableIncome);
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
      case 'OH':
        return grossAnnual * 0.04;
      case 'GA':
        return grossAnnual * 0.055;
      case 'NC':
        return grossAnnual * 0.0475;
      case 'VA':
        return grossAnnual * 0.0575;
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
        return grossAnnual * 0.07;
      case 'LA':
        return grossAnnual * 0.0425;
      case 'AR':
        return grossAnnual * 0.059;
      case 'MS':
        return grossAnnual * 0.05;
      case 'ID':
        return grossAnnual * 0.058;
      case 'NM':
        return grossAnnual * 0.059;
      case 'MT':
        return grossAnnual * 0.0675;
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
        return grossAnnual * 0.065;
      case 'KS':
        return grossAnnual * 0.057;
      case 'NE':
        return grossAnnual * 0.0664;
      case 'IA':
        return grossAnnual * 0.06;
      case 'OK':
        return grossAnnual * 0.0475;
      default:
        return grossAnnual * 0.05;
    }
  }

  static SalaryResult calculate(
    double grossAnnual,
    String state, {
    bool marriedFilingJointly = false,
    double preTaxDeductions = 0,
  }) {
    final federal =
        federalTax(grossAnnual, marriedFilingJointly: marriedFilingJointly, preTaxDeductions: preTaxDeductions);
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

// ─── UK Engine ────────────────────────────────────────────────────────────────

class UkSalaryEngine {
  UkSalaryEngine._();

  // ── 2026/27 constants ───────────────────────────────────────────────────────
  static const double _personalAllowance = 12570;
  static const double _niPrimaryThreshold = 12570;
  static const double _niUpperEarningsLimit = 50270;

  /// England & Wales income tax 2026/27. Personal allowance: £12,570.
  /// Allowance is tapered by £1 per £2 of income over £100,000.
  static double _englandWalesIncomeTax(double grossAnnual, {double salarySacrifice = 0}) {
    final adjustedGross = grossAnnual - salarySacrifice;
    // Taper personal allowance above £100,000: £1 reduction per £2 excess
    double pa = _personalAllowance;
    if (adjustedGross > 100000) {
      pa = (_personalAllowance - (adjustedGross - 100000) / 2).clamp(0.0, double.infinity);
    }
    final taxable = (adjustedGross - pa).clamp(0.0, double.infinity);
    if (taxable <= 0) return 0;
    if (taxable <= 37700) return taxable * 0.20;
    if (taxable <= 125140) return 7540 + (taxable - 37700) * 0.40;
    return 42384 + (taxable - 125140) * 0.45;
  }

  /// Scottish income tax 2026/27. Personal allowance: £12,570 (tapered above £100k).
  static double _scottishIncomeTax(double grossAnnual, {double salarySacrifice = 0}) {
    final adjustedGross = grossAnnual - salarySacrifice;
    // Taper personal allowance above £100,000
    double pa = _personalAllowance;
    if (adjustedGross > 100000) {
      pa = (_personalAllowance - (adjustedGross - 100000) / 2).clamp(0.0, double.infinity);
    }
    final taxable = (adjustedGross - pa).clamp(0.0, double.infinity);
    if (taxable <= 0) return 0;
    // Scottish bands (above personal allowance):
    // Starter  19%: £0       – £2,306  (£12,571–£14,876)
    // Basic    20%: £2,307   – £13,991 (£14,877–£26,561)
    // Intermediate 21%: £13,992 – £31,092 (£26,562–£43,662)
    // Higher   42%: £31,093  – £62,430 (£43,663–£75,000)
    // Advanced 45%: £62,431  – £112,570 (£75,001–£125,140)
    // Top      48%: over £112,570 (over £125,140)
    double tax = 0;
    double prev = 0;
    final bands = <(double upper, double rate)>[
      (2306, 0.19),
      (13991, 0.20),
      (31092, 0.21),
      (62430, 0.42),
      (112570, 0.45),
      (double.infinity, 0.48),
    ];
    for (int i = 0; i < bands.length; i++) {
      final upper = bands[i].$1;
      final rate = bands[i].$2;
      if (taxable <= prev) break;
      final slice = (taxable < upper ? taxable : upper) - prev;
      tax += slice * rate;
      prev = upper;
      if (upper == double.infinity) break;
    }
    return tax;
  }

  /// Compute income tax based on region (Scotland vs rest of UK).
  static double incomeTax(
    double grossAnnual, {
    bool scotland = false,
    double salarySacrifice = 0,
  }) =>
      scotland
          ? _scottishIncomeTax(grossAnnual, salarySacrifice: salarySacrifice)
          : _englandWalesIncomeTax(grossAnnual, salarySacrifice: salarySacrifice);

  /// NI Class 1 (employee) 2026/27: 8% on £12,570–£50,270, 2% above.
  /// Salary sacrifice reduces NIable earnings.
  static double nationalInsurance(double grossAnnual, {double salarySacrifice = 0}) {
    final niableGross = grossAnnual - salarySacrifice;
    if (niableGross <= _niPrimaryThreshold) return 0;
    final lower = (niableGross.clamp(_niPrimaryThreshold, _niUpperEarningsLimit) - _niPrimaryThreshold) * 0.08;
    final upper = niableGross > _niUpperEarningsLimit
        ? (niableGross - _niUpperEarningsLimit) * 0.02
        : 0.0;
    return lower + upper;
  }

  /// Student loan repayment 2026/27 (9% above plan threshold).
  /// Plan 1: £24,990 | Plan 2: £27,295 | Plan 5: £25,000 (2023+ starters, 40yr write-off)
  static double studentLoanRepayment(double grossAnnual, {int plan = 2}) {
    final threshold = switch (plan) {
      1 => 24990.0,
      5 => 25000.0,
      _ => 27295.0, // Plan 2
    };
    if (grossAnnual <= threshold) return 0;
    return (grossAnnual - threshold) * 0.09;
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
    final taxWith = incomeTax(grossAnnual, scotland: scotland, salarySacrifice: salarySacrifice);
    final niWithout = nationalInsurance(grossAnnual);
    final niWith = nationalInsurance(grossAnnual, salarySacrifice: salarySacrifice);
    return (taxWithout - taxWith, niWithout - niWith);
  }

  /// [studentLoan]    – include student loan repayment (default false).
  /// [loanPlan]       – 1, 2 (default), or 5.
  /// [scotland]       – use Scottish income tax rates (default false).
  /// [salarySacrifice] – annual salary sacrifice / SMART pension amount (£).
  static SalaryResult calculate(
    double grossAnnual, {
    bool studentLoan = false,
    int loanPlan = 2,
    bool scotland = false,
    double salarySacrifice = 0,
  }) {
    final income = incomeTax(grossAnnual, scotland: scotland, salarySacrifice: salarySacrifice);
    final ni = nationalInsurance(grossAnnual, salarySacrifice: salarySacrifice);
    final sl = studentLoan ? studentLoanRepayment(grossAnnual, plan: loanPlan) : 0.0;
    // ficaTax stores NI + student loan so the result model stays unchanged.
    final ficaTotal = ni + sl;
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
}

// ─── CA Engine ────────────────────────────────────────────────────────────────

class CaSalaryEngine {
  CaSalaryEngine._();

  /// Federal tax 2024. Basic Personal Amount (BPA): $15,705.
  static double federalTax(double grossAnnual) {
    final taxable = (grossAnnual - 15705).clamp(0.0, double.infinity);
    if (taxable <= 55867) return taxable * 0.15;
    if (taxable <= 111733) return 8380.05 + (taxable - 55867) * 0.205;
    if (taxable <= 154906) return 19832.48 + (taxable - 111733) * 0.26;
    if (taxable <= 220000) return 31064.73 + (taxable - 154906) * 0.29;
    return 49942.35 + (taxable - 220000) * 0.33;
  }

  // ── 2025 CPP / EI constants ─────────────────────────────────────────────────
  static const double _cpp1BasicExemption = 3500;
  static const double _ympe2025 = 71300; // CPP1 ceiling
  static const double _yampe2025 = 81900; // CPP2 ceiling
  static const double _cpp1Rate = 0.0595;
  static const double _cpp2Rate = 0.04;
  static const double _eiInsurableMax2025 = 65700;
  static const double _eiRate2025 = 0.0166; // employee rate

  /// CPP1 2025: 5.95% on earnings $3,500–$71,300 (YMPE).
  static double cpp1(double grossAnnual) {
    final pensionable = grossAnnual.clamp(_cpp1BasicExemption, _ympe2025) - _cpp1BasicExemption;
    return pensionable * _cpp1Rate;
  }

  /// CPP2 2025: 4.00% on earnings from YMPE ($71,300) up to YAMPE ($81,900).
  /// Introduced 2024, fully effective 2025.
  static double cpp2(double grossAnnual) {
    if (grossAnnual <= _ympe2025) return 0;
    return (min(grossAnnual, _yampe2025) - _ympe2025) * _cpp2Rate;
  }

  /// Combined CPP (CPP1 + CPP2) 2025.
  static double cpp(double grossAnnual) => cpp1(grossAnnual) + cpp2(grossAnnual);

  /// EI 2025: 1.66% up to insurable max $65,700.
  static double ei(double grossAnnual) {
    return grossAnnual.clamp(0, _eiInsurableMax2025) * _eiRate2025;
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

  /// Ontario 2025: 5 progressive brackets, BPA $11,865.
  static double _ontarioProvincialTax(double grossAnnual) {
    final taxable = (grossAnnual - 11865).clamp(0.0, double.infinity);
    return _progressive(taxable, [
      (51446, 0.0505),
      (102894, 0.0915),
      (150000, 0.1116),
      (220000, 0.1216),
      (double.infinity, 0.1316),
    ]);
  }

  /// British Columbia 2025: 6 progressive brackets, BPA $11,981.
  static double _bcProvincialTax(double grossAnnual) {
    final taxable = (grossAnnual - 11981).clamp(0.0, double.infinity);
    return _progressive(taxable, [
      (45654, 0.0506),
      (91310, 0.0770),
      (104835, 0.1050),
      (127299, 0.1229),
      (172602, 0.1470),
      (double.infinity, 0.1680),
    ]);
  }

  /// Quebec 2026 provincial tax — 4 progressive brackets.
  /// Personal basic amount: ~$17,183 CAD.
  static double _quebecProvincialTax(double grossAnnual) {
    // Taxable income after QC basic personal amount
    final taxable = (grossAnnual - 17183).clamp(0.0, double.infinity);
    if (taxable <= 51780) return taxable * 0.14;
    if (taxable <= 103545) return 7249.20 + (taxable - 51780) * 0.19;
    if (taxable <= 126000) return 17084.55 + (taxable - 103545) * 0.24;
    return 22474.75 + (taxable - 126000) * 0.2575;
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

  static SalaryResult calculate(double grossAnnual, String province) {
    final fed = federalTax(grossAnnual);
    // Quebec residents receive a 16.5% abatement on their federal tax
    // (QC runs its own equivalent social programs).
    final fedAbatement =
        province == 'QC' ? quebecFederalAbatement(grossAnnual) : 0.0;
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
  /// all deductions for [province]. Uses binary search (50 iterations ≈ ±0.01).
  static double grossFromNet(double targetNet, String province) {
    if (targetNet <= 0) return 0;
    double low = targetNet;
    double high = targetNet * 2;
    // Ensure upper bound is genuinely above target
    while (calculate(high, province).netAnnual < targetNet) {
      high *= 2;
    }
    for (int i = 0; i < 50; i++) {
      final mid = (low + high) / 2;
      final calculatedNet = calculate(mid, province).netAnnual;
      if (calculatedNet < targetNet) {
        low = mid;
      } else {
        high = mid;
      }
    }
    return (low + high) / 2;
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
