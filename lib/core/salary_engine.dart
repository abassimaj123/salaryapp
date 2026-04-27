// ignore_for_file: constant_identifier_names

// ─── Shared result model ──────────────────────────────────────────────────────

class SalaryResult {
  final double grossAnnual;
  final double federalTax;
  final double ficaTax;   // US: FICA  |  UK: NI  |  CA: CPP+EI
  final double stateTax;  // US: state |  UK: 0   |  CA: provincial
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

  /// Simplified flat state income-tax rates.
  static double stateTax(double grossAnnual, String state) {
    const rates = <String, double>{
      'CA': 0.093, 'NY': 0.0685, 'TX': 0.0, 'FL': 0.0,
      'WA': 0.0,   'NV': 0.0,   'IL': 0.0495, 'PA': 0.0307,
      'OH': 0.04,  'GA': 0.055, 'NC': 0.0475, 'VA': 0.0575,
      'MA': 0.05,  'NJ': 0.0637,'CO': 0.044,  'AZ': 0.025,
      'MN': 0.0985,'WI': 0.0765,'OR': 0.099,  'MD': 0.0575,
      'MI': 0.0425,'IN': 0.0323,'KY': 0.045,  'MO': 0.0495,
      'AL': 0.05,  'SC': 0.07,  'LA': 0.0425, 'AR': 0.059,
      'MS': 0.05,  'ID': 0.058, 'NM': 0.059,  'MT': 0.0675,
      'UT': 0.0465,'ND': 0.029, 'SD': 0.0,    'WY': 0.0,
      'AK': 0.0,   'HI': 0.11,  'VT': 0.0875, 'ME': 0.0715,
      'NH': 0.0,   'CT': 0.0699,'RI': 0.0599, 'DE': 0.066,
      'DC': 0.0895,'WV': 0.065, 'TN': 0.0,    'KS': 0.057,
      'NE': 0.0664,'IA': 0.06,  'OK': 0.0475,
    };
    return grossAnnual * (rates[state] ?? 0.05);
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
    'AK', 'AL', 'AR', 'AZ', 'CA', 'CO', 'CT', 'DC', 'DE', 'FL',
    'GA', 'HI', 'IA', 'ID', 'IL', 'IN', 'KS', 'KY', 'LA', 'MA',
    'MD', 'ME', 'MI', 'MN', 'MO', 'MS', 'MT', 'NC', 'ND', 'NE',
    'NH', 'NJ', 'NM', 'NV', 'NY', 'OH', 'OK', 'OR', 'PA', 'RI',
    'SC', 'SD', 'TN', 'TX', 'UT', 'VA', 'VT', 'WA', 'WI', 'WV', 'WY',
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

  static SalaryResult calculate(double grossAnnual) {
    final income = incomeTax(grossAnnual);
    final ni = nationalInsurance(grossAnnual);
    final total = income + ni;
    final net = grossAnnual - total;
    return SalaryResult(
      grossAnnual: grossAnnual,
      federalTax: income,
      ficaTax: ni,
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

  /// Simplified provincial income-tax rates.
  static double provincialTax(double grossAnnual, String province) {
    const rates = <String, double>{
      'ON': 0.0505, 'BC': 0.0506, 'AB': 0.10, 'QC': 0.14,
      'MB': 0.108,  'SK': 0.105,  'NS': 0.0879, 'NB': 0.094,
      'NL': 0.087,  'PE': 0.098,
    };
    final taxable = (grossAnnual - 10000).clamp(0.0, double.infinity);
    return taxable * (rates[province] ?? 0.0505);
  }

  static SalaryResult calculate(double grossAnnual, String province) {
    final fed = federalTax(grossAnnual);
    final cppAmt = cpp(grossAnnual);
    final eiAmt = ei(grossAnnual);
    final prov = provincialTax(grossAnnual, province);
    final total = fed + cppAmt + eiAmt + prov;
    final net = grossAnnual - total;
    return SalaryResult(
      grossAnnual: grossAnnual,
      federalTax: fed,
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
    'AB', 'BC', 'MB', 'NB', 'NL', 'NS', 'ON', 'PE', 'QC', 'SK',
  ];
}
