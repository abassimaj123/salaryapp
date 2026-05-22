// ignore_for_file: constant_identifier_names

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

  /// Federal income tax brackets 2024 (single filer).
  static double federalTax(double grossAnnual) {
    if (grossAnnual <= 11600) return grossAnnual * 0.10;
    if (grossAnnual <= 47150) return 1160 + (grossAnnual - 11600) * 0.12;
    if (grossAnnual <= 100525) return 5426 + (grossAnnual - 47150) * 0.22;
    if (grossAnnual <= 191950) return 17168.5 + (grossAnnual - 100525) * 0.24;
    if (grossAnnual <= 243725) return 39110.5 + (grossAnnual - 191950) * 0.32;
    if (grossAnnual <= 609350) return 55678.5 + (grossAnnual - 243725) * 0.35;
    return 183647.25 + (grossAnnual - 609350) * 0.37;
  }

  /// FICA: Social Security (6.2 % up to $168,600) + Medicare (1.45 %).
  static double fica(double grossAnnual) {
    final ss = grossAnnual.clamp(0, 168600) * 0.062;
    final medicare = grossAnnual * 0.0145;
    return ss + medicare;
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

  static SalaryResult calculate(double grossAnnual, String state) {
    final federal = federalTax(grossAnnual);
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

  /// Income tax 2024/25. Personal allowance: £12,570.
  static double incomeTax(double grossAnnual) {
    final taxable = (grossAnnual - 12570).clamp(0.0, double.infinity);
    if (taxable <= 0) return 0;
    if (taxable <= 37700) return taxable * 0.20;
    if (taxable <= 125140) return 7540 + (taxable - 37700) * 0.40;
    return 42384 + (taxable - 125140) * 0.45;
  }

  /// NI Class 1 (employee) 2024/25: 8 % on £12,570–£50,270, 2 % above.
  static double nationalInsurance(double grossAnnual) {
    if (grossAnnual <= 12570) return 0;
    final lower = (grossAnnual.clamp(12570, 50270) - 12570) * 0.08;
    final upper = grossAnnual > 50270 ? (grossAnnual - 50270) * 0.02 : 0.0;
    return lower + upper;
  }

  /// Student loan repayment 2024/25 (9% above plan threshold).
  /// Plan 1: £22,015 | Plan 2: £27,295 (default) | Plan 5: £25,000
  static double studentLoanRepayment(double grossAnnual, {int plan = 2}) {
    final threshold = switch (plan) {
      1 => 22015.0,
      5 => 25000.0,
      _ => 27295.0, // Plan 2
    };
    if (grossAnnual <= threshold) return 0;
    return (grossAnnual - threshold) * 0.09;
  }

  /// [studentLoan] – include Plan 2 student loan repayment (default false).
  /// [loanPlan]   – 1, 2 (default), or 5.
  static SalaryResult calculate(
    double grossAnnual, {
    bool studentLoan = false,
    int loanPlan = 2,
  }) {
    final income = incomeTax(grossAnnual);
    final ni = nationalInsurance(grossAnnual);
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

  /// CPP 2024: 5.95 % on earnings $3,500–$68,500.
  static double cpp(double grossAnnual) {
    final pensionable = grossAnnual.clamp(3500.0, 68500.0) - 3500;
    return pensionable * 0.0595;
  }

  /// EI 2024: 1.66 % up to insurable max $63,200.
  static double ei(double grossAnnual) {
    return grossAnnual.clamp(0, 63200) * 0.0166;
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
      ficaTax: cppAmt + eiAmt, // CPP + EI lumped together
      stateTax: prov,
      totalTax: total,
      netAnnual: net,
      netMonthly: net / 12,
      netBiWeekly: net / 26,
      netWeekly: net / 52,
      effectiveRate: total / grossAnnual * 100,
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
