// Golden reference tests — SalaryApp (3 flavors: CA / UK / US)
// Focus: cross-flavor consistency + jurisdiction boundary guards
//        SalaryApp already has salary_engine_test.dart with bracket golden values.
//        This file focuses on cross-flavor net ordering and UK-specific NI/PAYE.
// Sources: CRA T4032 (CA 2025), HMRC PAYE tables (UK 2025/26), IRS Rev. Proc. 2024-40.
//
// CalcwiseTax.registry is pre-seeded at class load — no init() needed.

import 'package:flutter_test/flutter_test.dart';
import 'package:salary_app/core/salary_engine.dart';

void main() {
  void approx(double actual, double expected, {double tol = 1.0}) {
    expect(actual, closeTo(expected, tol),
        reason: 'Expected ~$expected, got $actual');
  }

  // ── US Engine — FICA + federal tax ordering ───────────────────────────────

  group('UsSalaryEngine — net income ordering and FICA floor', () {
    test('SA-G1: \$0 income → \$0 federal tax, \$0 FICA', () {
      approx(UsSalaryEngine.federalTax(0), 0.0, tol: 0.01);
      approx(UsSalaryEngine.fica(0), 0.0, tol: 0.01);
    });

    test('SA-G2: \$60k → net take-home > \$0 and < gross', () {
      final result = UsSalaryEngine.calculate(60000, 'TX');
      expect(result.netAnnual, greaterThan(0));
      expect(result.netAnnual, lessThan(60000));
    });

    test('SA-G3: higher gross → higher net (monotonic)', () {
      final r60 = UsSalaryEngine.calculate(60000, 'TX');
      final r80 = UsSalaryEngine.calculate(80000, 'TX');
      expect(r80.netAnnual, greaterThan(r60.netAnnual));
    });

    test('SA-G4: TX (no state tax) → higher net than CA at same gross', () {
      final tx = UsSalaryEngine.calculate(100000, 'TX');
      final ca = UsSalaryEngine.calculate(100000, 'CA');
      expect(tx.netAnnual, greaterThan(ca.netAnnual));
    });
  });

  // ── UK Engine — PAYE + NI 2025/26 ────────────────────────────────────────

  group('UkSalaryEngine — 2025/26 PAYE + NI', () {
    test('SA-G5: £50k gross → income tax £7,486 + NI £2,994.40', () {
      // PA = £12,570; taxable = £37,430; 20% → £7,486
      // NI: (50,000-12,570)×8% = 37,430×0.08 = £2,994.40
      final result = UkSalaryEngine.calculate(50000);
      approx(result.federalTax, 7486, tol: 2);   // UK income tax
      approx(result.ficaTax, 2994.40, tol: 2);   // NI Class 1
    });

    test('SA-G6: £50k gross → net annual ≈ £39,519.60', () {
      // net = 50,000 - 7,486 - 2,994.40 = £39,519.60
      final result = UkSalaryEngine.calculate(50000);
      approx(result.netAnnual, 39519.60, tol: 5);
    });

    test('SA-G7: UK netMonthly = netAnnual / 12 (consistency)', () {
      final result = UkSalaryEngine.calculate(50000);
      approx(result.netMonthly, result.netAnnual / 12, tol: 0.01);
    });

    test('SA-G8: £12,570 (PA) → zero income tax, NI also £0 (at PT)', () {
      final result = UkSalaryEngine.calculate(12570);
      approx(result.federalTax, 0.0, tol: 0.01);
      approx(result.ficaTax, 0.0, tol: 0.01);
    });
  });

  // ── Cross-flavor: net ordering at equivalent purchasing power ─────────────

  group('Cross-flavor effective rate sanity', () {
    test('SA-G9: CA effective rate at \$80k > 0% and < 50%', () {
      final result = CaSalaryEngine.calculate(80000, 'ON');
      expect(result.effectiveRate, greaterThan(0));
      expect(result.effectiveRate, lessThan(50));
    });

    test('SA-G10: effectiveRate = totalTax / grossAnnual × 100 (integrity)', () {
      final result = UkSalaryEngine.calculate(60000);
      final computed = result.totalTax / result.grossAnnual * 100;
      approx(result.effectiveRate, computed, tol: 0.01);
    });
  });

  // ── CA — provincial bracket ordering (ON vs BC vs QC) ────────────────────

  group('CaSalaryEngine — provincial net ordering at \$80k', () {
    test('SA-G11: BC net > QC net (QC highest provincial rates + QPIP)', () {
      final netBC = CaSalaryEngine.calculate(80000, 'BC').netAnnual;
      final netQC = CaSalaryEngine.calculate(80000, 'QC').netAnnual;
      expect(netBC, greaterThan(netQC));
    });

    test('SA-G12: ON / BC / QC nets all within 15% of gross (same federal base)', () {
      final nets = [
        CaSalaryEngine.calculate(80000, 'ON').netAnnual,
        CaSalaryEngine.calculate(80000, 'BC').netAnnual,
        CaSalaryEngine.calculate(80000, 'QC').netAnnual,
      ];
      final minNet = nets.reduce((a, b) => a < b ? a : b);
      final maxNet = nets.reduce((a, b) => a > b ? a : b);
      expect((maxNet - minNet) / 80000, lessThan(0.15));
    });

    test('SA-G13: CA net is positive and less than gross for all provinces', () {
      for (final province in ['ON', 'BC', 'QC', 'AB', 'MB']) {
        final net = CaSalaryEngine.calculate(80000, province).netAnnual;
        expect(net, greaterThan(0), reason: '\$province net should be > 0');
        expect(net, lessThan(80000), reason: '\$province net should be < gross');
      }
    });

    test('SA-G14: CPP2 — \$85k deductions > \$70k proportionally (YAMPE threshold)', () {
      final deductions85 = 85000 - CaSalaryEngine.calculate(85000, 'ON').netAnnual;
      final deductions70 = 70000 - CaSalaryEngine.calculate(70000, 'ON').netAnnual;
      final marginal = (deductions85 - deductions70) / 15000;
      expect(marginal, greaterThan(0.20));
    });

    test('SA-G15: CA progressive — higher gross → lower take-home ratio', () {
      final ratio80 = CaSalaryEngine.calculate(80000, 'ON').netAnnual / 80000;
      final ratio150 = CaSalaryEngine.calculate(150000, 'ON').netAnnual / 150000;
      expect(ratio80, greaterThan(ratio150));
    });
  });
}
