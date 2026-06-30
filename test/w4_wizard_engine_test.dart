import 'package:flutter_test/flutter_test.dart';
import 'package:calcwise_core/calcwise_core.dart' show CalcwiseTax;
import 'package:salary_app/screens/w4_wizard_screen.dart' show W4WizardScreen;

/// Regression test for the P1 fix: the W-4 wizard was hardcoded to query
/// `us_federal 2025` (and embedded its own 2025 bracket tables) while the
/// rest of the app (salary_engine.dart) had already moved to 2026. The
/// wizard now reads the tax year dynamically from the shared TaxRegistry via
/// [W4WizardScreen.debugTaxYear], matching the pattern in salary_engine.dart.
void main() {
  group('W4WizardScreen — tax year sourcing (P1 fix)', () {
    test('taxYear reflects the latest year present in TaxRegistry (2026)', () {
      // The baked dataset carries both 2025 and 2026 us_federal data; the
      // wizard must prefer 2026 (current year), not the stale 2025 default.
      expect(W4WizardScreen.debugTaxYear, 2026);
    });

    test('taxYear matches what us_federal 2026 actually has in the registry',
        () {
      final reg = CalcwiseTax.registry;
      expect(reg.annual('us_federal', 2026), isNotNull,
          reason: 'us_federal 2026 must exist in the baked dataset for the '
              'wizard to source it instead of falling back to 2025.');
    });

    test('single-filer standard deduction matches the 2026 registry value '
        '(not the stale 2025 \$15,750 literal)', () {
      final reg = CalcwiseTax.registry;
      final expected = reg.annual('us_federal', 2026)?.basicPersonalAmount;
      expect(expected, isNotNull);
      // 2026 IRS Rev. Proc. 2025-32 single standard deduction is $16,100,
      // distinct from the 2025 value ($15,750) the wizard used to hardcode.
      expect(expected, 16100.0);
      expect(W4WizardScreen.debugStandardDeduction('single'), expected);
    });

    test(
        'married-filing-jointly standard deduction matches the 2026 mfj '
        'registry entry (not the stale 2025 \$31,500 literal)', () {
      final reg = CalcwiseTax.registry;
      final expected =
          reg.annual('us_federal', 2026, status: 'mfj')?.basicPersonalAmount;
      expect(expected, isNotNull);
      expect(expected, 32200.0);
      expect(W4WizardScreen.debugStandardDeduction('marriedJointly'), expected);
    });

    test('headOfHousehold standard deduction is derived as 1.5x single '
        '(IRS convention), using the 2026 single base', () {
      final single = W4WizardScreen.debugStandardDeduction('single');
      expect(W4WizardScreen.debugStandardDeduction('headOfHousehold'),
          single * 1.5);
    });
  });
}
