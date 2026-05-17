import 'package:flutter_test/flutter_test.dart';
import 'package:salary_app/core/salary_engine.dart';

void main() {
  // ─── Helpers ─────────────────────────────────────────────────────────────

  void approx(double actual, double expected, {double tolerance = 1.0}) {
    expect(actual, closeTo(expected, tolerance),
        reason: 'Expected ~$expected, got $actual');
  }

  // ─── US Engine ───────────────────────────────────────────────────────────

  group('UsSalaryEngine — federal tax', () {
    test('zero income', () => approx(UsSalaryEngine.federalTax(0), 0));

    test('bracket 1 — \$8,000 → 10%', () {
      approx(UsSalaryEngine.federalTax(8000), 800);
    });

    test('bracket 2 — \$30,000', () {
      // 1160 + (30000-11600)*0.12 = 1160 + 2208 = 3368
      approx(UsSalaryEngine.federalTax(30000), 3368);
    });

    test('bracket 3 — \$75,000', () {
      // 5426 + (75000-47150)*0.22 = 5426 + 6127 = 11553
      approx(UsSalaryEngine.federalTax(75000), 11553);
    });

    test('bracket 4 — \$150,000', () {
      // 17168.5 + (150000-100525)*0.24 = 17168.5 + 11874 = 29042.5
      approx(UsSalaryEngine.federalTax(150000), 29042.5);
    });

    test('bracket 5 — \$220,000', () {
      // 39110.5 + (220000-191950)*0.32 = 39110.5 + 8976 = 48086.5
      approx(UsSalaryEngine.federalTax(220000), 48086.5);
    });

    test('bracket 6 — \$400,000', () {
      // 55678.5 + (400000-243725)*0.35 = 55678.5 + 54699.25 = 110377.75
      approx(UsSalaryEngine.federalTax(400000), 110375, tolerance: 5.0);
    });

    test('bracket 7 — \$700,000', () {
      // 183647.25 + (700000-609350)*0.37 = 183647.25 + 33539.5 = 217186.75
      approx(UsSalaryEngine.federalTax(700000), 217186.75, tolerance: 2.0);
    });
  });

  group('UsSalaryEngine — FICA', () {
    test('\$50,000 income', () {
      // SS: 50000*0.062=3100, Med: 50000*0.0145=725 → 3825
      approx(UsSalaryEngine.fica(50000), 3825);
    });

    test('SS wage base cap at \$168,600', () {
      // SS: 168600*0.062=10453.2, Med: 200000*0.0145=2900 → 13353.2
      approx(UsSalaryEngine.fica(200000), 13353.2, tolerance: 1.0);
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

    test('£140,000 — enters 45% band', () {
      // taxable=127430; 42384 + (127430-125140)*0.45
      approx(UkSalaryEngine.incomeTax(140000), 42384 + (127430 - 125140) * 0.45,
          tolerance: 1.0);
    });
  });

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
    test('below BPA \$15,705 → 0', () {
      expect(CaSalaryEngine.federalTax(15705), 0.0);
    });

    test('\$40,000 → 15% on taxable', () {
      // taxable = 40000-15705 = 24295
      approx(CaSalaryEngine.federalTax(40000), 24295 * 0.15, tolerance: 1.0);
    });

    test('\$80,000 — second bracket', () {
      // taxable=64295; 8380.05 + (64295-55867)*0.205
      approx(
          CaSalaryEngine.federalTax(80000), 8380.05 + (64295 - 55867) * 0.205,
          tolerance: 1.0);
    });

    test('\$130,000 — third bracket', () {
      // taxable=114295; 19832.48 + (114295-111733)*0.26
      approx(CaSalaryEngine.federalTax(130000),
          19832.48 + (114295 - 111733) * 0.26,
          tolerance: 1.0);
    });

    test('\$180,000 — fourth bracket', () {
      // taxable=164295; 31064.73 + (164295-154906)*0.29
      approx(CaSalaryEngine.federalTax(180000),
          31064.73 + (164295 - 154906) * 0.29,
          tolerance: 1.0);
    });

    test('\$250,000 — top bracket 33%', () {
      // taxable=234295; 49942.35 + (234295-220000)*0.33
      approx(CaSalaryEngine.federalTax(250000),
          49942.35 + (234295 - 220000) * 0.33,
          tolerance: 1.0);
    });
  });

  group('CaSalaryEngine — CPP', () {
    test('below \$3,500 floor → 0', () {
      expect(CaSalaryEngine.cpp(3000), 0.0);
    });

    test('\$30,000 — 5.95% on (30000-3500)', () {
      approx(CaSalaryEngine.cpp(30000), (30000 - 3500) * 0.0595);
    });

    test('CPP caps at \$68,500 ceiling', () {
      final atCap = CaSalaryEngine.cpp(68500);
      final aboveCap = CaSalaryEngine.cpp(100000);
      approx(atCap, aboveCap);
    });
  });

  group('CaSalaryEngine — EI', () {
    test('\$50,000 — 1.66%', () {
      approx(CaSalaryEngine.ei(50000), 50000 * 0.0166);
    });

    test('EI caps at \$63,200', () {
      final atCap = CaSalaryEngine.ei(63200);
      final aboveCap = CaSalaryEngine.ei(80000);
      approx(atCap, aboveCap);
    });
  });

  group('CaSalaryEngine — provincial tax', () {
    test('Ontario — 5.05%', () {
      final taxable = (60000 - 10000).toDouble();
      approx(CaSalaryEngine.provincialTax(60000, 'ON'), taxable * 0.0505);
    });

    test('Quebec — 14%', () {
      final taxable = (80000 - 10000).toDouble();
      approx(CaSalaryEngine.provincialTax(80000, 'QC'), taxable * 0.14);
    });

    test('unknown province — defaults to ON rate', () {
      final expected = CaSalaryEngine.provincialTax(50000, 'ON');
      approx(CaSalaryEngine.provincialTax(50000, 'XX'), expected);
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
