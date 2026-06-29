import 'package:flutter_test/flutter_test.dart';
import 'package:salary_app/core/salary_engine.dart';

void main() {
  // ─── Helpers ─────────────────────────────────────────────────────────────

  void approx(double actual, double expected, {double tolerance = 1.0}) {
    expect(actual, closeTo(expected, tolerance),
        reason: 'Expected ~$expected, got $actual');
  }

  // ─── US Engine ───────────────────────────────────────────────────────────

  // Source: CalcwiseTax registry (us_federal 2026, single filer). Standard
  // deduction (BPA) = $16,100. Brackets (taxable-income ceilings):
  // 10%/$12,400, 12%/$50,400, 22%/$105,700, 24%/$201,775, 32%/$256,225,
  // 35%/$640,600, 37%/above. Migrated 2025→2026; goldens recomputed from the
  // registry (the verified source of truth).
  group('UsSalaryEngine — federal tax', () {
    test('zero income', () => approx(UsSalaryEngine.federalTax(0), 0));

    test('bracket 1 — \$8,000 (below std deduction \$16,100 → 0)', () {
      // 2026: standard deduction $16,100. $8,000 taxable = $0
      approx(UsSalaryEngine.federalTax(8000), 0);
    });

    test('bracket 2 — \$30,000', () {
      // 2026: taxable = 30000-16100=13900; 10%×12400=1240 + 12%×1500=180 = 1420
      approx(UsSalaryEngine.federalTax(30000), 1420.0);
    });

    test('bracket 3 — \$75,000', () {
      // 2026: taxable=58900; 1240 + 12%×(50400-12400)=4560 + 22%×(58900-50400)=1870 = 7670
      approx(UsSalaryEngine.federalTax(75000), 7670);
    });

    test('bracket 4 — \$150,000', () {
      // 2026: taxable=133900; thru 22% band = 17682 + 24%×(133900-105700) = 24734
      approx(UsSalaryEngine.federalTax(150000), 24734);
    });

    test('bracket 5 — \$220,000', () {
      // 2026: taxable=203900; thru 24% band + 32%×(203900-201775) = 41704
      approx(UsSalaryEngine.federalTax(220000), 41704);
    });

    test('bracket 6 — \$400,000', () {
      // 2026: taxable=383900; thru 32% band + 35%×(383900-256225) = 103134.25
      approx(UsSalaryEngine.federalTax(400000), 103134.25, tolerance: 5.0);
    });

    test('bracket 7 — \$700,000', () {
      // 2026: taxable=683900; thru 35% band + 37%×(683900-640600) = 209000.25
      approx(UsSalaryEngine.federalTax(700000), 209000.25, tolerance: 2.0);
    });
  });

  // Source: CalcwiseTax registry (us_federal 2026) — SS wage base $184,500,
  // employee rate 6.2%, Medicare 1.45%, additional Medicare 0.9% above $200k.
  group('UsSalaryEngine — FICA', () {
    test('\$50,000 income', () {
      // SS: 50000*0.062=3100, Med: 50000*0.0145=725 → 3825
      approx(UsSalaryEngine.fica(50000), 3825);
    });

    test('SS wage base cap at \$184,500 (2026)', () {
      // SS: 184500*0.062=11439, Med: 200000*0.0145=2900 → 14339
      approx(UsSalaryEngine.fica(200000), 14339.0, tolerance: 1.0);
    });
  });

  group('UsSalaryEngine — state tax', () {
    test('Texas — no state tax', () {
      expect(UsSalaryEngine.stateTax(100000, 'TX'), 0.0);
    });

    test('California — registry brackets w/ std deduction (~5223 on 100k)', () {
      // Now sourced from CalcwiseTax registry (us_ca 2026, single filer):
      // standard deduction (BPA) $5,540 → taxable $94,460, applied across the
      // verified 2026 bands. taxOn(100000) = $5,223.42. The old hardcoded copy
      // returned ~$5,842 (stale 2025 thresholds + no std deduction); the
      // registry (Tax Foundation 2026, verified) is the source of truth.
      approx(UsSalaryEngine.stateTax(100000, 'CA'), 5223.42, tolerance: 1.0);
    });

    test('Pennsylvania — flat 3.07%, no std deduction (registry)', () {
      // us_pa 2026: flat 3.07%, no standard deduction → 85000 × 0.0307 = 2609.5
      approx(UsSalaryEngine.stateTax(85000, 'PA'), 2609.5, tolerance: 1.0);
    });

    test('unknown state — defaults to 5% (registry has no us_zz)', () {
      // Codes absent from the registry keep the legacy 5% flat approximation.
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
      // Now correct: registry-sourced bands fixed the old £42,384 additional-rate
      // cumulative (should be 42,516) that previously made the engine return 49071.
      approx(UkSalaryEngine.incomeTax(140000), 49203, tolerance: 1.0);
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
    // the CalcwiseTax registry (ca_federal 2026) used by
    // CaSalaryEngine.federalTax(). When the registry changes, update to match.
    // source: calcwise-tax-data (ca_federal 2026), verified source of truth.
    const kBpa = 16452.0;           // Basic Personal Amount 2026
    const kBracket1Upper = 58523.0; // bracket 1 ceiling (taxable income)
    const kBracket1Rate = 0.14;     // 2026 lowest rate (first full year @ 14%)
    const kBracket1Tax = 8193.22;   // 58523 × 0.14
    const kBracket2Upper = 117045.0; // bracket 2 ceiling
    const kBracket2Rate = 0.205;
    const kBracket2Tax = 20190.23;  // accumulated tax at bracket 2 ceiling
    const kBracket3Rate = 0.26;
    const kBracket3Upper = 181440.0; // bracket 3 ceiling
    const kBracket3Tax = 36932.93;  // accumulated tax at bracket 3 ceiling
    const kBracket4Rate = 0.29;

    test('below BPA \$16,452 → 0', () {
      expect(CaSalaryEngine.federalTax(kBpa), 0.0);
    });

    test('\$40,000 → 14% on taxable', () {
      // taxable = 40000 - kBpa = 23548 (all in bracket 1, 2026 rate 14%)
      approx(CaSalaryEngine.federalTax(40000), (40000 - kBpa) * kBracket1Rate, tolerance: 1.0);
    });

    test('\$80,000 — second bracket', () {
      // taxable=63548; kBracket1Tax + (taxable - kBracket1Upper) × kBracket2Rate
      final taxable = 80000 - kBpa;
      approx(
          CaSalaryEngine.federalTax(80000),
          kBracket1Tax + (taxable - kBracket1Upper) * kBracket2Rate,
          tolerance: 1.0);
    });

    test('\$130,000 — still second bracket (taxable=113548 < 117045)', () {
      // taxable=113548 < bracket 2 ceiling (117045) → still in 2nd bracket
      final taxable = 130000 - kBpa;
      approx(CaSalaryEngine.federalTax(130000),
          kBracket1Tax + (taxable - kBracket1Upper) * kBracket2Rate,
          tolerance: 1.0);
    });

    test('\$180,000 — third bracket', () {
      // taxable=163548 → in bracket 3 (117045 < 163548 ≤ 181440) @ 26%
      final taxable = 180000 - kBpa;
      approx(CaSalaryEngine.federalTax(180000),
          kBracket2Tax + (taxable - kBracket2Upper) * kBracket3Rate,
          tolerance: 1.0);
    });

    test('\$250,000 — fourth bracket 29%', () {
      // taxable=233548 → in bracket 4 (181440 < 233548 ≤ 258482) @ 29%
      final taxable = 250000 - kBpa;
      approx(CaSalaryEngine.federalTax(250000),
          kBracket3Tax + (taxable - kBracket3Upper) * kBracket4Rate,
          tolerance: 1.0);
    });
  });

  // Source: CRA 2026 — CPP base ceiling (YMPE) $74,600 @ 5.95%, CPP2 ceiling (YAMPE) $85,000 @ 4.00%
  // canada.ca/en/revenue-agency/services/tax/businesses/topics/payroll/payroll-deductions-contributions/canada-pension-plan-cpp/cpp-contribution-rates-maximums-exemptions.html
  group('CaSalaryEngine — CPP', () {
    test('below \$3,500 floor → 0', () {
      expect(CaSalaryEngine.cpp(3000), 0.0);
    });

    test('\$30,000 — 5.95% on (30000-3500)', () {
      approx(CaSalaryEngine.cpp(30000), (30000 - 3500) * 0.0595);
    });

    test('CPP + CPP2 fully caps above \$85,000 ceiling (2026)', () {
      // 2026: CPP base ceiling (YMPE) $74,600 @ 5.95%; CPP2 ceiling (YAMPE) $85,000 @ 4%.
      // cpp(85000) = cpp(100000) = base(74600) + cpp2(85000-74600)
      final atCap = CaSalaryEngine.cpp(85000);
      final aboveCap = CaSalaryEngine.cpp(100000);
      approx(atCap, aboveCap);
    });
  });

  group('CaSalaryEngine — EI', () {
    // Source: CRA 2026 — employee rate 1.63% (rest of Canada), max insurable $68,900
    test('\$50,000 — 1.63% (2026)', () {
      approx(CaSalaryEngine.ei(50000), 50000 * 0.0163);
    });

    test('EI caps at \$68,900 (2026 max insurable earnings)', () {
      // CRA 2026: max insurable = $68,900, employee rate 1.63%
      // max annual EI premium = $68,900 × 0.0163 = $1,123.07
      approx(CaSalaryEngine.ei(68900), 68900 * 0.0163);
      final atCap = CaSalaryEngine.ei(68900);
      final aboveCap = CaSalaryEngine.ei(80000);
      approx(atCap, aboveCap);
    });
  });

  group('CaSalaryEngine — provincial tax', () {
    test('Ontario — 5.05% first bracket with BPA \$12,989 (registry 2026)', () {
      // ca_on 2026: BPA = $12,989, first bracket ≤ $53,891 at 5.05%
      // taxable = 60000 - 12989 = 47011; all in first bracket
      // expected = 47011 × 0.0505 = 2374.0555
      final taxable = (60000 - 12989).toDouble();
      approx(CaSalaryEngine.provincialTax(60000, 'ON'), taxable * 0.0505);
    });

    // Source: CalcwiseTax registry (ca_qc 2026): 14% ≤$54,345, 19% ≤$108,680,
    // 24% ≤$132,245, 25.75% above. Basic personal amount $18,952 (2026).
    test('Quebec — 4-bracket progressive (registry 2026)', () {
      // $80k gross: taxable = 80000 - 18952 = 61048
      // bracket1: 54345 × 14% = 7608.30
      // bracket2: (61048 - 54345) × 19% = 6703 × 19% = 1273.57
      // total provincial = 8881.87
      approx(CaSalaryEngine.provincialTax(80000, 'QC'), 8881.87);
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
