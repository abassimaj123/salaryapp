import 'package:flutter/material.dart';
import 'package:calcwise_core/calcwise_core.dart';
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
        pages: const [
          OnboardingPage(
            icon: Icons.payments_rounded,
            title: 'Know What You\nActually Take Home',
            subtitle:
                'After-tax, after-deductions — your real paycheck, calculated instantly.',
            pills: ['After Tax', 'Hourly Rate', '3 Countries'],
            titleFr: 'Calculez votre\nsalaire net',
            subtitleFr:
                'Après impôts et déductions — votre vrai chèque de paie, calculé instantanément.',
            pillsFr: ['Après impôts', 'Taux horaire', '3 Pays'],
            titleEs: 'Conoce tu\nsalario neto real',
            subtitleEs:
                'Después de impuestos y deducciones — tu cheque real, calculado al instante.',
            pillsEs: ['Después de impuestos', 'Tasa por hora', '3 Países'],
          ),
          OnboardingPage(
            icon: Icons.public_rounded,
            title: 'CA, UK, or US —\nYou Choose',
            subtitle:
                'Switch countries and see exactly how taxes change your bottom line.',
            pills: ['Canada', 'United Kingdom', 'United States'],
            titleFr: 'CA, UK ou US —\nVous choisissez',
            subtitleFr:
                'Changez de pays et voyez comment les impôts affectent votre revenu.',
            pillsFr: ['Canada', 'Royaume-Uni', 'États-Unis'],
            titleEs: 'CA, UK o US —\nTú eliges',
            subtitleEs:
                'Cambia de país y ve exactamente cómo los impuestos cambian tu ingreso.',
            pillsEs: ['Canadá', 'Reino Unido', 'Estados Unidos'],
          ),
        ],
      );
}
