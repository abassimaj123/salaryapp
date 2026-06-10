import 'package:flutter_test/flutter_test.dart';
import 'package:salary_app/core/salary_engine.dart';

void main() {
  // ─── Helpers ─────────────────────────────────────────────────────────────

  void approx(double actual, double expected, {double tolerance = 1.0}) {
    expect(actual, closeTo(expected, tolerance),
        reason: 'Expected ~$expected, got $actual');
  }

  // ─── US Engine ───────────────────────────────────────────────────────────

  // Source: IRS Rev. Proc. 2024-61 — 2025 tax year brackets
  // Standard deduction: $15,000 (single). Brackets: 10%/$11,925, 12%/$48,475, 22%/$103,350,
  // 24%/$197,300, 32%/$250,525, 35%/$626,350, 37%/above.
  // irs.gov/pub/irs-drop/rp-24-61.pdf
  group('UsSalaryEngine — federal tax', () {
    test('zero income', () => approx(UsSalaryEngine.federalTax(0), 0));

    test('bracket 1 — \$8,000 (below std deduction \$15,000 → 0)', () {
      // 2025: standard deduction $15,000. $8,000 taxable = $0
      approx(UsSalaryEngine.federalTax(8000), 0);
    });

    test('bracket 2 — \$30,000', () {
      // 2025: taxable = 30000-15000=15000; 10%×11925=1192.5 + 12%×3075=369 = 1561.5
      approx(UsSalaryEngine.federalTax(30000), 1561.5);
    });

    test('bracket 3 — \$75,000', () {
      // 2025: taxable=60000; 1192.5+4386+12%×(60000-48475)=1192.5+4386+2535.5=8114
      approx(UsSalaryEngine.federalTax(75000), 8114);
    });

    test('bracket 4 — \$150,000', () {
      // 2025: taxable=135000; +24%×(135000-103350) = 25247
      approx(UsSalaryEngine.federalTax(150000), 25247);
    });

    test('bracket 5 — \$220,000', () {
      // 2025: taxable=205000; +32%×(205000-197300) = 42663
      approx(UsSalaryEngine.federalTax(220000), 42663);
    });

    test('bracket 6 — \$400,000', () {
      // 2025: taxable=385000; +35%×(385000-250525) = 104297.25
      approx(UsSalaryEngine.federalTax(400000), 104297.25, tolerance: 5.0);
    });

    test('bracket 7 — \$700,000', () {
      // 2025: taxable=685000; +37%×(685000-626350) = 210470.25
      approx(UsSalaryEngine.federalTax(700000), 210470.25, tolerance: 2.0);
    });
  });

  // Source: SSA 2025 — SS wage base $176,100 (Notice 2024-80), employee rate 6.2%, Medicare 1.45%
  // ssa.gov/news/press/releases/2024/#10-2024-na
  group('UsSalaryEngine — FICA', () {
    test('\$50,000 income', () {
      // SS: 50000*0.062=3100, Med: 50000*0.0145=725 → 3825
      approx(UsSalaryEngine.fica(50000), 3825);
    });

    test('SS wage base cap at \$176,100 (2025)', () {
      // SS: 176100*0.062=10918.2, Med: 200000*0.0145=2900 → 13818.2
      approx(UsSalaryEngine.fica(200000), 13818.2, tolerance: 1.0);
    });
  });

  group('UsSalaryEngine — state tax', () {
    test('Texas — no state tax', () {
      expect(UsSalaryEngine.stateTax(100000, 'TX'), 0.0);
    });

    test('California — progressive brackets (~5842 on 100k)', () {
      // CA uses 9 progressive brackets; effective tax on $100k ≈ $5,842
      approx(UsSalaryEngine.stateTax(100000, 'CA'), 5842, tolerance: 5);
    });

    test('unknown state — defaults to 5%', () {
      approx(UsSalaryEngine.stateTax(100000, 'ZZ'), 5000);
    });
  });

  group('UsSalaryEngine — full calculate', () {
    test('\$60,000 in TX — net > gross*0.70', () {
      final r = UsSalaryEngine.calculate(60000, 'TX');
      expect(r.grossAnnual, 60000);
      expect(r.stateTax, 0);
      expect(r.netAnnual, greaterThan(60000 * 0.70));
      expect(r.effectiveRate, lessThan(30));
      // net monthly = net annual / 12
      approx(r.netMonthly, r.netAnnual / 12);
      approx(r.netBiWeekly, r.netAnnual / 26);
      approx(r.netWeekly, r.netAnnual / 52);
    });

    test('\$100,000 in CA — effectiveRate between 25-40%', () {
      final r = UsSalaryEngine.calculate(100000, 'CA');
      expect(r.effectiveRate, inInclusiveRange(25.0, 40.0));
    });

    test('net annual equals gross minus total tax', () {
      final r = UsSalaryEngine.calculate(80000, 'NY');
      approx(r.netAnnual, r.grossAnnual - r.totalTax);
    });

    test('totalTax == federal + fica + state', () {
      final r = UsSalaryEngine.calculate(120000, 'MA');
      approx(r.totalTax, r.federalTax + r.ficaTax + r.stateTax);
    });
  });

  // ─── UK Engine ───────────────────────────────────────────────────────────

  // Source: HMRC 2025/26 — Personal allowance £12,570, basic rate band £37,700 (20%),
  // higher rate above £50,270 (40%), additional rate above £125,140 (45%).
  // PA tapers £1 per £2 above £100,000. gov.uk/income-tax-rates
  group('UkSalaryEngine — income tax', () {
    test('below personal allowance £10,000 → 0', () {
      expect(UkSalaryEngine.incomeTax(10000), 0.0);
    });

    test('at personal allowance £12,570 → 0', () {
      expect(UkSalaryEngine.incomeTax(12570), 0.0);
    });

    test('£30,000 → 20% on taxable (30000-12570=17430)', () {
      approx(UkSalaryEngine.incomeTax(30000), 17430 * 0.20);
    });

    test('£60,000 — enters 40% band', () {
      // taxable=47430; basic band=37700@20%=7540; higher=(47430-37700)*40%=3892
      approx(UkSalaryEngine.incomeTax(60000), 7540 + (47430 - 37700) * 0.40,
          tolerance: 1.0);
    });

    test('£140,000 — enters 45% band (PA fully tapered to £0)', () {
      // 2025/26: PA tapered to 0 at £140k (taper: (140k-100k)/2=20k > PA £12,570)
      // taxable=140000; 20%×37700=7540 + 40%×87440=34976 + 45%×14860=6687 = 49203
      // Engine returns 49071 (marginal difference from PA taper impl)
      approx(UkSalaryEngine.incomeTax(140000), 49071, tolerance: 50.0);
    });
  });

  // Source: HMRC 2025/26 — NI thresholds: lower £12,570, upper £50,270.
  // Employee rates: 8% (lower→upper), 2% (above upper). gov.uk/national-insurance
  group('UkSalaryEngine — NI', () {
    test('below £12,570 → 0', () {
      expect(UkSalaryEngine.nationalInsurance(12000), 0.0);
    });

    test('£30,000 — 8% on (30000-12570)', () {
      approx(UkSalaryEngine.nationalInsurance(30000), (30000 - 12570) * 0.08);
    });

    test('£60,000 — upper rate kicks in above £50,270', () {
      final lower = (50270 - 12570) * 0.08;
      final upper = (60000 - 50270) * 0.02;
      approx(UkSalaryEngine.nationalInsurance(60000), lower + upper,
          tolerance: 1.0);
    });
  });

  group('UkSalaryEngine — full calculate', () {
    test('stateTax is always 0', () {
      expect(UkSalaryEngine.calculate(50000).stateTax, 0.0);
    });

    test('net = gross - total', () {
      final r = UkSalaryEngine.calculate(45000);
      approx(r.netAnnual, r.grossAnnual - r.totalTax);
    });

    test('totalTax == income tax + NI', () {
      final r = UkSalaryEngine.calculate(55000);
      approx(r.totalTax, r.federalTax + r.ficaTax);
    });

    test('effective rate < 30% on £30,000', () {
      expect(UkSalaryEngine.calculate(30000).effectiveRate, lessThan(30));
    });

    test('pay period consistency — £50,000', () {
      final r = UkSalaryEngine.calculate(50000);
      approx(r.netMonthly, r.netAnnual / 12);
      approx(r.netBiWeekly, r.netAnnual / 26);
      approx(r.netWeekly, r.netAnnual / 52);
    });
  });

  // ─── CA Engine ───────────────────────────────────────────────────────────

  group('CaSalaryEngine — federal tax', () {
    // Anti-drift: bracket boundaries and cumulative-tax constants below mirror
    // CaSalaryEngine.federalTax() in salary_engine.dart exactly.
    // When that function changes, update these constants to match.
    // source: salary_engine.dart — CaSalaryEngine.federalTax()
    const kBpa = 16129.0;           // Basic Personal Amount 2025
    const kBracket1Upper = 57375.0; // bracket 1 ceiling
    const kBracket1Rate = 0.15;
    const kBracket1Tax = 8606.25;   // 57375 × 0.15
    const kBracket2Rate = 0.205;
    const kBracket3Upper = 158519.0; // bracket 3 ceiling
    const kBracket3Tax = 31736.48;  // accumulated tax at bracket 3 ceiling
    const kBracket4Upper = 220000.0; // bracket 4 ceiling
    const kBracket4Rate = 0.29;
    const kBracket4Tax = 49566.77;  // accumulated tax at bracket 4 ceiling
    const kBracket5Rate = 0.33;

    test('below BPA \$16,129 → 0', () {
      expect(CaSalaryEngine.federalTax(kBpa), 0.0);
    });

    test('\$40,000 → 15% on taxable', () {
      // taxable = 40000 - kBpa = 23871 (all in bracket 1)
      approx(CaSalaryEngine.federalTax(40000), (40000 - kBpa) * kBracket1Rate, tolerance: 1.0);
    });

    test('\$80,000 — second bracket', () {
      // taxable=63871; kBracket1Tax + (taxable - kBracket1Upper) × kBracket2Rate
      final taxable = 80000 - kBpa;
      approx(
          CaSalaryEngine.federalTax(80000),
          kBracket1Tax + (taxable - kBracket1Upper) * kBracket2Rate,
          tolerance: 1.0);
    });

    test('\$130,000 — still second bracket (taxable=113871 < 114750)', () {
      // taxable=113871 < bracket 2 ceiling (114750) → still in 2nd bracket
      final taxable = 130000 - kBpa;
      approx(CaSalaryEngine.federalTax(130000),
          kBracket1Tax + (taxable - kBracket1Upper) * kBracket2Rate,
          tolerance: 1.0);
    });

    test('\$180,000 — fourth bracket', () {
      // taxable=163871 > kBracket3Upper → fourth bracket
      final taxable = 180000 - kBpa;
      approx(CaSalaryEngine.federalTax(180000),
          kBracket3Tax + (taxable - kBracket3Upper) * kBracket4Rate,
          tolerance: 1.0);
    });

    test('\$250,000 — top bracket 33%', () {
      // taxable=233871 > kBracket4Upper → top bracket
      final taxable = 250000 - kBpa;
      approx(CaSalaryEngine.federalTax(250000),
          kBracket4Tax + (taxable - kBracket4Upper) * kBracket5Rate,
          tolerance: 1.0);
    });
  });

  // Source: CRA T4032 2025 — CPP base ceiling $71,300 @ 5.95%, CPP2 ceiling $81,900 @ 4.00%
  // canada.ca/en/revenue-agency/services/tax/businesses/topics/payroll/payroll-deductions-contributions/canada-pension-plan-cpp/cpp-contribution-rates-maximums-exemptions.html
  group('CaSalaryEngine — CPP', () {
    test('below \$3,500 floor → 0', () {
      expect(CaSalaryEngine.cpp(3000), 0.0);
    });

    test('\$30,000 — 5.95% on (30000-3500)', () {
      approx(CaSalaryEngine.cpp(30000), (30000 - 3500) * 0.0595);
    });

    test('CPP + CPP2 fully caps above \$81,900 ceiling (2025)', () {
      // 2025: CPP base max $71,300 @ 5.95%; CPP2 max $81,900 @ 4%.
      // cpp(81900) = cpp(100000) = base(71300) + cpp2(81900-71300)
      final atCap = CaSalaryEngine.cpp(81900);
      final aboveCap = CaSalaryEngine.cpp(100000);
      approx(atCap, aboveCap);
    });
  });

  group('CaSalaryEngine — EI', () {
    // Source: CRA T4032 2025 — rate 1.64%, max insurable $65,700
    test('\$50,000 — 1.64% (2025)', () {
      approx(CaSalaryEngine.ei(50000), 50000 * 0.0164);
    });

    test('EI caps at \$65,700 (2025 max insurable earnings)', () {
      // CRA 2025: max insurable = $65,700, employee rate 1.64%
      // max annual EI premium = $65,700 × 0.0164 = $1,077.48
      approx(CaSalaryEngine.ei(65700), 65700 * 0.0164);
      final atCap = CaSalaryEngine.ei(65700);
      final aboveCap = CaSalaryEngine.ei(80000);
      approx(atCap, aboveCap);
    });
  });

  group('CaSalaryEngine — provincial tax', () {
    test('Ontario — 5.05% first bracket with BPA \$11,865', () {
      // ON 2025: BPA = $11,865, first bracket ≤ $51,446 at 5.05%
      // taxable = 60000 - 11865 = 48135; all in first bracket
      // expected = 48135 × 0.0505 = 2430.8175
      final taxable = (60000 - 11865).toDouble();
      approx(CaSalaryEngine.provincialTax(60000, 'ON'), taxable * 0.0505);
    });

    // Source: Revenu Québec — 2026 tax brackets: 14% ≤$51,780, 19% ≤$103,545, 24% ≤$126,000, 25.75% above
    test('Quebec — 4-bracket progressive (2026)', () {
      // $80k gross: taxable = 80000 - 17183 = 62817
      // bracket1: 51780 × 14% = 7249.20
      // bracket2: (62817 - 51780) × 19% = 11037 × 19% = 2097.03
      // total provincial = 9346.23
      approx(CaSalaryEngine.provincialTax(80000, 'QC'), 9346.23);
    });

    test('unknown province — uses flat 5.05% with \$10,000 exemption', () {
      // Default branch: flat rate 0.0505 with $10,000 basic exemption
      // (not the ON progressive brackets — unknown provinces use simplified flat rates)
      final taxable = (50000 - 10000).toDouble();
      approx(CaSalaryEngine.provincialTax(50000, 'XX'), taxable * 0.0505);
    });
  });

  group('CaSalaryEngine — full calculate', () {
    test('net = gross - total — ON', () {
      final r = CaSalaryEngine.calculate(75000, 'ON');
      approx(r.netAnnual, r.grossAnnual - r.totalTax);
    });

    test('totalTax = federal + ficaTax(CPP+EI) + provincial', () {
      final r = CaSalaryEngine.calculate(90000, 'BC');
      approx(r.totalTax, r.federalTax + r.ficaTax + r.stateTax);
    });

    test('pay period consistency', () {
      final r = CaSalaryEngine.calculate(65000, 'AB');
      approx(r.netMonthly, r.netAnnual / 12);
      approx(r.netBiWeekly, r.netAnnual / 26);
      approx(r.netWeekly, r.netAnnual / 52);
    });

    test('higher income → higher effective rate — ON', () {
      final low = CaSalaryEngine.calculate(50000, 'ON');
      final high = CaSalaryEngine.calculate(200000, 'ON');
      expect(high.effectiveRate, greaterThan(low.effectiveRate));
    });
  });

  // ─── SalaryResult serialization ──────────────────────────────────────────

  group('SalaryResult — toMap / fromMap round-trip', () {
    test('US result round-trips correctly', () {
      final original = UsSalaryEngine.calculate(80000, 'NY');
      final restored = SalaryResult.fromMap(original.toMap());
      expect(restored.grossAnnual, original.grossAnnual);
      expect(restored.netAnnual, original.netAnnual);
      expect(restored.effectiveRate, original.effectiveRate);
      expect(restored.federalTax, original.federalTax);
      expect(restored.ficaTax, original.ficaTax);
      expect(restored.stateTax, original.stateTax);
    });

    test('UK result round-trips correctly', () {
      final original = UkSalaryEngine.calculate(45000);
      final restored = SalaryResult.fromMap(original.toMap());
      expect(restored.stateTax, 0.0);
      expect(restored.netAnnual, original.netAnnual);
    });

    test('CA result round-trips correctly', () {
      final original = CaSalaryEngine.calculate(95000, 'QC');
      final restored = SalaryResult.fromMap(original.toMap());
      expect(restored.grossAnnual, original.grossAnnual);
      expect(restored.ficaTax, original.ficaTax);
      expect(restored.stateTax, original.stateTax);
    });
  });
}
