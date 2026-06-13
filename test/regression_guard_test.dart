import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:salary_app/core/salary_engine.dart';

void main() {
  group('Format — affichage', () {
    test('Formatage salaire annuel', () {
      final fmt = NumberFormat.currency(locale: 'en_US', symbol: r'$');
      expect(fmt.format(75000), r'$75,000.00');
    });

    test('Formatage salaire mensuel net', () {
      final fmt = NumberFormat.currency(locale: 'en_US', symbol: r'$');
      expect(fmt.format(5200.50), r'$5,200.50');
    });
  });

  group('Widget — éléments UI de base', () {
    testWidgets('Card salaire net affiche montant', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Card(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: const [
                  Text('Net Monthly'),
                  Text(r'$4,850.00',
                      style:
                          TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
                ],
              ),
            ),
          ),
        ),
      );
      expect(find.text('Net Monthly'), findsOneWidget);
      expect(find.text(r'$4,850.00'), findsOneWidget);
    });

    testWidgets('Champ salaire annuel brut accepte valeur', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: TextField(
              keyboardType: TextInputType.number,
              decoration: InputDecoration(labelText: 'Annual Salary'),
            ),
          ),
        ),
      );
      await tester.enterText(find.byType(TextField), '80000');
      expect(find.text('80000'), findsOneWidget);
    });
  });

  group('Regression guard — UsSalaryEngine', () {
    test(r'RG-US-1: federal tax 75k (2025: taxable=59,250 after $15,750 std deduction)', () {
      final tax = UsSalaryEngine.federalTax(75000);
      // 2025 (OBBBA std deduction $15,750): 1192.5+4386+22%×(59250-48475)=7949
      expect(tax, closeTo(7949, 50));
    });

    test('RG-US-2: FICA = SS 6.2% + Medicare 1.45% sur 75k', () {
      final fica = UsSalaryEngine.fica(75000);
      // SS = 75000 × 0.062 = 4650, Medicare = 75000 × 0.0145 = 1087.5
      expect(fica, closeTo(5737.5, 10));
    });

    test('RG-US-3: salaire net < salaire brut (impôts toujours positifs)', () {
      final r = UsSalaryEngine.calculate(75000, 'TX');
      expect(r.netAnnual, lessThan(75000));
      expect(r.netAnnual, greaterThan(0));
    });

    test('RG-US-4: salaire mensuel net = annuel / 12', () {
      final r = UsSalaryEngine.calculate(75000, 'TX');
      expect(r.netMonthly, closeTo(r.netAnnual / 12, 1));
    });

    test('RG-US-5: impôt effectif positif et inférieur au brut', () {
      final r = UsSalaryEngine.calculate(100000, 'CA');
      // totalTax = federal + FICA + state — peut dépasser 30% avec CA state tax
      expect(r.totalTax, greaterThan(0));
      expect(r.totalTax, lessThan(100000));
      expect(r.netAnnual, greaterThan(0));
    });

    test('RG-US-6: plus de salaire → plus d\'impôts', () {
      final r60k = UsSalaryEngine.calculate(60000, 'TX');
      final r120k = UsSalaryEngine.calculate(120000, 'TX');
      expect(r120k.totalTax, greaterThan(r60k.totalTax));
    });
  });
}
