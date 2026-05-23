import 'package:flutter/material.dart';
import 'package:calcwise_core/calcwise_core.dart';
import '../core/flavor_config.dart';
import '../main.dart' show paywallSession;

class OnboardingScreen extends StatelessWidget {
  const OnboardingScreen({super.key});

  @override
  Widget build(BuildContext context) => CalcwiseOnboarding(
        appKey: 'salaryapp',
        onDone: () async {
          Navigator.of(context).pushReplacementNamed('/home');
          await paywallSession.recordSession();
        },
        pages: _pages,
      );

  /// Flavor-specific onboarding pages. Each flavor shows only its own market.
  static List<OnboardingPage> get _pages {
    if (FlavorConfig.isCA) {
      return const [
        OnboardingPage(
          icon: Icons.payments_rounded,
          title: 'Know What You\nActually Take Home',
          subtitle:
              'CPP2, EI, provincial tax — your real paycheque in French or English.',
          pills: ['Français / English', 'CPP2 2025', 'QC Abatement', 'Hourly Rate'],
          titleFr: 'Calculez votre\nsalaire net',
          subtitleFr:
              'RPC2, AE, impôt provincial — votre vrai chèque de paie en français ou en anglais.',
          pillsFr: ['Français / English', 'RPC2 2025', 'Abattement QC', 'Taux horaire'],
        ),
        OnboardingPage(
          icon: Icons.map_rounded,
          title: 'Province-by-Province\nTax Breakdown',
          subtitle:
              'Select your province and see federal + provincial taxes broken down.',
          pills: ['10 Provinces', 'CPP & EI', 'QC Abatement'],
          titleFr: 'Impôts province\npar province',
          subtitleFr:
              'Sélectionnez votre province et voyez la décomposition fédérale + provinciale.',
          pillsFr: ['10 provinces', 'RPC et AE', 'Abattement QC'],
        ),
        OnboardingPage(
          icon: Icons.history_rounded,
          title: 'Save Your\nCalculations',
          subtitle:
              'Your salary history is saved automatically. Compare scenarios anytime.',
          pills: ['History', 'PDF Export', 'Compare'],
          titleFr: 'Sauvegardez vos\ncalculs',
          subtitleFr:
              'Vos calculs de salaire sont sauvegardés. Comparez vos scénarios en tout temps.',
          pillsFr: ['Historique', 'Export PDF', 'Comparer'],
        ),
      ];
    }

    if (FlavorConfig.isUK) {
      return const [
        OnboardingPage(
          icon: Icons.payments_rounded,
          title: 'Know What You\nActually Take Home',
          subtitle:
              'Scottish Income Tax, NI 2025 bands, salary sacrifice — all calculated for your pay.',
          pills: ['Scottish Tax', 'NI 2025', 'Salary Sacrifice', 'Student Loan'],
        ),
        OnboardingPage(
          icon: Icons.account_balance_rounded,
          title: 'UK Tax,\nSimplified',
          subtitle:
              'Income Tax and NI calculated for your salary — instantly.',
          pills: ['Income Tax', 'National Insurance', 'Net Pay'],
        ),
        OnboardingPage(
          icon: Icons.history_rounded,
          title: 'Save Your\nResults',
          subtitle:
              'Your salary calculations are saved automatically. Revisit and compare anytime.',
          pills: ['History', 'PDF Export', 'Share'],
        ),
      ];
    }

    // US (default)
    return const [
      OnboardingPage(
        icon: Icons.payments_rounded,
        title: 'Know What You\nActually Take Home',
        subtitle:
            'After-tax, after-FICA — your real paycheck, calculated instantly.',
        pills: ['After Tax', 'Hourly Rate', '50 States'],
        titleEs: 'Conoce tu\nsalario neto real',
        subtitleEs:
            'Después de impuestos y FICA — tu cheque real, calculado al instante.',
        pillsEs: ['Después de impuestos', 'Tasa por hora', '50 Estados'],
      ),
      OnboardingPage(
        icon: Icons.location_on_rounded,
        title: '50 States —\nPick Yours',
        subtitle:
            'State income tax varies widely. Select your state for an accurate breakdown.',
        pills: ['Federal Tax', 'FICA', 'State Tax'],
        titleEs: '50 estados —\nEl tuyo',
        subtitleEs:
            'El impuesto estatal varía mucho. Selecciona tu estado para un cálculo preciso.',
        pillsEs: ['Impuesto federal', 'FICA', 'Impuesto estatal'],
      ),
      OnboardingPage(
        icon: Icons.history_rounded,
        title: 'Save Your\nResults',
        subtitle:
            'Your salary calculations are saved automatically. Revisit and compare anytime.',
        pills: ['History', 'PDF Export', 'Share'],
        titleEs: 'Guarda tus\nresultados',
        subtitleEs:
            'Tus cálculos de salario se guardan automáticamente. Recupéralos y compara cuando quieras.',
        pillsEs: ['Historial', 'Exportar PDF', 'Compartir'],
      ),
    ];
  }
}
