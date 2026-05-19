import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:calcwise_core/calcwise_core.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Minimal host — no Firebase, no AdMob, no IAP.
Widget _host(Widget child) => MaterialApp(
      theme: ThemeData.light().copyWith(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFFDC2626)),
        extensions: [CalcwiseTheme.light(primary: const Color(0xFFDC2626))],
      ),
      home: Scaffold(body: SingleChildScrollView(child: child)),
    );

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('ResultTile', () {
    testWidgets('renders label and value', (tester) async {
      await tester.pumpWidget(_host(
        const ResultTile(label: 'Net Pay', value: r'$3,200'),
      ));
      await tester.pump();
      expect(find.text('Net Pay'), findsOneWidget);
      expect(find.text(r'$3,200'), findsOneWidget);
    });

    testWidgets('highlighted tile renders without error', (tester) async {
      await tester.pumpWidget(_host(
        const ResultTile(
          label: 'Annual Salary',
          value: r'$72,000',
          isHighlight: true,
        ),
      ));
      await tester.pump();
      expect(find.text('Annual Salary'), findsOneWidget);
      expect(find.text(r'$72,000'), findsOneWidget);
    });

    testWidgets('renders salary breakdown tiles', (tester) async {
      await tester.pumpWidget(_host(
        const Column(
          children: [
            ResultTile(label: 'Federal Tax', value: r'$10,800'),
            ResultTile(label: 'State Tax', value: r'$3,600'),
            ResultTile(label: 'FICA', value: r'$5,508'),
            ResultTile(label: 'Net Pay', value: r'$52,092'),
          ],
        ),
      ));
      await tester.pump();
      expect(find.text('Federal Tax'), findsOneWidget);
      expect(find.text('State Tax'), findsOneWidget);
      expect(find.text('FICA'), findsOneWidget);
      expect(find.text('Net Pay'), findsOneWidget);
    });
  });

  group('CalcwiseHeroCard', () {
    testWidgets('renders label and value', (tester) async {
      await tester.pumpWidget(_host(
        const CalcwiseHeroCard(
          label: 'Monthly Take-Home',
          value: r'$4,341',
        ),
      ));
      await tester.pumpAndSettle();
      expect(find.text('MONTHLY TAKE-HOME'), findsOneWidget);
      expect(find.text(r'$4,341'), findsOneWidget);
    });

    testWidgets('renders secondary text', (tester) async {
      await tester.pumpWidget(_host(
        const CalcwiseHeroCard(
          label: 'Annual Net',
          value: r'$52,092',
          secondary: 'after all deductions',
        ),
      ));
      await tester.pumpAndSettle();
      expect(find.text('after all deductions'), findsOneWidget);
    });

    testWidgets('renders stats row with pay periods', (tester) async {
      await tester.pumpWidget(_host(
        const CalcwiseHeroCard(
          label: 'Monthly Take-Home',
          value: r'$4,341',
          stats: [
            (label: 'Bi-weekly', value: r'$2,004'),
            (label: 'Weekly', value: r'$1,002'),
          ],
        ),
      ));
      await tester.pumpAndSettle();
      expect(find.text('BI-WEEKLY'), findsOneWidget);
      expect(find.text('WEEKLY'), findsOneWidget);
    });

    testWidgets('renders badge', (tester) async {
      await tester.pumpWidget(_host(
        const CalcwiseHeroCard(
          label: 'Monthly Take-Home',
          value: r'$4,341',
          badges: [CalcwiseHeroBadge(label: 'CA State')],
        ),
      ));
      await tester.pumpAndSettle();
      expect(find.text('CA State'), findsOneWidget);
    });
  });

  group('SectionCard', () {
    testWidgets('renders title and children', (tester) async {
      await tester.pumpWidget(_host(
        const SectionCard(
          title: 'Deductions',
          children: [
            ResultTile(label: 'Federal Tax', value: r'$10,800'),
            ResultTile(label: 'State Tax', value: r'$3,600'),
          ],
        ),
      ));
      await tester.pump();
      expect(find.text('Deductions'), findsOneWidget);
      expect(find.text('Federal Tax'), findsOneWidget);
    });

    testWidgets('renders pay period section', (tester) async {
      await tester.pumpWidget(_host(
        const SectionCard(
          title: 'Pay Periods',
          children: [
            ResultTile(label: 'Monthly', value: r'$4,341'),
            ResultTile(label: 'Bi-weekly', value: r'$2,004'),
            ResultTile(label: 'Weekly', value: r'$1,002'),
          ],
        ),
      ));
      await tester.pump();
      expect(find.text('Pay Periods'), findsOneWidget);
      expect(find.text('Monthly'), findsOneWidget);
      expect(find.text('Bi-weekly'), findsOneWidget);
    });
  });

  group('CalcwiseEmptyState', () {
    testWidgets('renders icon and title', (tester) async {
      await tester.pumpWidget(_host(
        const CalcwiseEmptyState(
          icon: Icons.savings_rounded,
          title: 'No history yet',
          body: 'Your saved salary calculations appear here.',
        ),
      ));
      await tester.pump();
      expect(find.byIcon(Icons.savings_rounded), findsOneWidget);
      expect(find.text('No history yet'), findsOneWidget);
      expect(find.text('Your saved salary calculations appear here.'),
          findsOneWidget);
    });

    testWidgets('action button fires callback', (tester) async {
      bool tapped = false;
      await tester.pumpWidget(_host(
        CalcwiseEmptyState(
          icon: Icons.calculate_rounded,
          title: 'No results',
          actionLabel: 'Calculate salary',
          onAction: () => tapped = true,
        ),
      ));
      await tester.pump();
      await tester.tap(find.text('Calculate salary'));
      expect(tapped, isTrue);
    });

    testWidgets('renders without action when not provided', (tester) async {
      await tester.pumpWidget(_host(
        const CalcwiseEmptyState(
          icon: Icons.savings_rounded,
          title: 'No data',
        ),
      ));
      await tester.pump();
      expect(find.byType(ElevatedButton), findsNothing);
    });
  });
}
