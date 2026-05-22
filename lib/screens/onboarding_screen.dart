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
              'After tax and deductions — your real paycheque, calculated instantly.',
          pills: ['After Tax', 'Hourly Rate', 'Canadian Market'],
          titleFr: 'Calculez votre\nsalaire net',
          subtitleFr:
              'Après impôts et déductions — votre vrai chèque de paie, calculé instantanément.',
          pillsFr: ['Après impôts', 'Taux horaire', 'Marché canadien'],
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
      ];
    }

    if (FlavorConfig.isUK) {
      return const [
        OnboardingPage(
          icon: Icons.payments_rounded,
          title: 'Know What You\nActually Take Home',
          subtitle:
              'After income tax and National Insurance — your real take-home pay.',
          pills: ['After Tax', 'Hourly Rate', 'UK Market'],
        ),
        OnboardingPage(
          icon: Icons.account_balance_rounded,
          title: 'UK Tax,\nSimplified',
          subtitle:
              'Income Tax and NI calculated for your salary — instantly.',
          pills: ['Income Tax', 'National Insurance', 'Net Pay'],
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
    ];
  }
}
