import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:calcwise_core/calcwise_core.dart';
import 'package:salary_app/widgets/result_card.dart';

/// Minimal host — no Firebase, no AdMob, no IAP.
Widget _host(Widget child) => MaterialApp(
      theme: ThemeData.light().copyWith(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFFDC2626)),
        extensions: [CalcwiseTheme.light(primary: const Color(0xFFDC2626))],
      ),
      home: Scaffold(body: SingleChildScrollView(child: child)),
    );

void main() {
  group('ResultCard', () {
    testWidgets('renders label and value', (tester) async {
      await tester.pumpWidget(_host(
        const ResultCard(label: 'Net Pay', value: r'$3,200'),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Net Pay'), findsOneWidget);
      expect(find.text(r'$3,200'), findsOneWidget);
    });

    testWidgets('highlight variant renders without error', (tester) async {
      await tester.pumpWidget(_host(
        const ResultCard(
          label: 'Annual Salary',
          value: r'$72,000',
          highlight: true,
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Annual Salary'), findsOneWidget);
      expect(find.text(r'$72,000'), findsOneWidget);
    });

    testWidgets('renders subtitle when provided', (tester) async {
      await tester.pumpWidget(_host(
        const ResultCard(
          label: 'Hourly Rate',
          value: r'$34.62',
          subtitle: 'before tax',
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.text('before tax'), findsOneWidget);
    });

    testWidgets('does not render subtitle when omitted', (tester) async {
      await tester.pumpWidget(_host(
        const ResultCard(label: 'Tax', value: r'$12,000'),
      ));
      await tester.pumpAndSettle();

      expect(find.text(r'$12,000'), findsOneWidget);
    });

    testWidgets('renders icon when provided', (tester) async {
      await tester.pumpWidget(_host(
        const ResultCard(
          label: 'Benefits',
          value: r'$4,800',
          icon: Icons.health_and_safety,
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.health_and_safety), findsOneWidget);
    });

    testWidgets('default highlight is false — uses Card widget',
        (tester) async {
      await tester.pumpWidget(_host(
        const ResultCard(label: 'Deductions', value: r'$1,500'),
      ));
      await tester.pumpAndSettle();

      expect(find.byType(Card), findsOneWidget);
    });
  });

  group('MetricRow', () {
    testWidgets('renders label and value inline', (tester) async {
      await tester.pumpWidget(_host(
        const MetricRow(label: 'Federal Tax', value: '22%'),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Federal Tax'), findsOneWidget);
      expect(find.text('22%'), findsOneWidget);
    });

    testWidgets('renders custom valueColor without error', (tester) async {
      await tester.pumpWidget(_host(
        MetricRow(
          label: 'State Tax',
          value: '5%',
          valueColor: Colors.red,
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.text('State Tax'), findsOneWidget);
      expect(find.text('5%'), findsOneWidget);
    });
  });
}
