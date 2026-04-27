import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import 'core/firebase/firebase_options.dart';
import 'core/services/crashlytics_service.dart';
import 'core/freemium/freemium_service.dart';
import 'core/freemium/iap_service.dart';
import 'core/ads/ad_service.dart';
import 'core/flavor_config.dart';
import 'core/theme/app_theme.dart';
import 'l10n/strings_en.dart';
import 'l10n/strings_es.dart';
import 'l10n/strings_fr.dart';
import 'screens/splash_screen.dart';
import 'screens/calculator_screen.dart';
import 'screens/history_screen.dart';
import 'screens/settings_screen.dart';

// ─── Global language notifier ─────────────────────────────────────────────────
// For US: true = Spanish  |  For CA: true = French  |  For UK: ignored
final ValueNotifier<bool> altLanguageNotifier = ValueNotifier<bool>(false);

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform);

  await CrashlyticsService.init();
  await freemiumService.initialize();
  await IAPService.instance.initialize();
  await MobileAds.instance.initialize();
  await AdService.instance.initialize();

  // Auto-detect preferred alternate language at startup
  final locales = PlatformDispatcher.instance.locales;
  if (locales.isNotEmpty) {
    final locale = locales.first;
    if (FlavorConfig.isCA) {
      altLanguageNotifier.value =
          locale.languageCode == 'fr' && locale.countryCode == 'CA';
    } else if (FlavorConfig.isUS) {
      altLanguageNotifier.value = locale.languageCode == 'es';
    }
  }

  SystemChrome.setPreferredOrientations(
      [DeviceOrientation.portraitUp, DeviceOrientation.portraitDown]);

  runApp(const SalaryApp());
}

class SalaryApp extends StatelessWidget {
  const SalaryApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: AppStringsEN.appName,
      theme: AppTheme.theme,
      initialRoute: '/',
      routes: {
        '/': (_) => const SplashScreen(),
        '/home': (_) => const MainShell(),
      },
    );
  }
}

// ─── 3-tab shell ─────────────────────────────────────────────────────────────

class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _index = 0;

  static const _pages = <Widget>[
    CalculatorScreen(),
    HistoryScreen(),
    SettingsScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: altLanguageNotifier,
      builder: (context, useAlt, _) {
        final s = _strings(useAlt);
        return Scaffold(
          body: IndexedStack(index: _index, children: _pages),
          bottomNavigationBar: NavigationBar(
            selectedIndex: _index,
            onDestinationSelected: (i) => setState(() => _index = i),
            destinations: [
              NavigationDestination(
                icon: const Icon(Icons.calculate_outlined),
                selectedIcon: const Icon(Icons.calculate),
                label: s.calculator,
              ),
              NavigationDestination(
                icon: const Icon(Icons.history_outlined),
                selectedIcon: const Icon(Icons.history),
                label: s.history,
              ),
              NavigationDestination(
                icon: const Icon(Icons.settings_outlined),
                selectedIcon: const Icon(Icons.settings),
                label: s.settings,
              ),
            ],
          ),
        );
      },
    );
  }
}

// ─── String resolver helper ───────────────────────────────────────────────────

abstract class _S {
  String get calculator;
  String get history;
  String get settings;
}

class _SEN implements _S {
  @override String get calculator => AppStringsEN.calculator;
  @override String get history    => AppStringsEN.history;
  @override String get settings   => AppStringsEN.settings;
}

class _SES implements _S {
  @override String get calculator => AppStringsES.calculator;
  @override String get history    => AppStringsES.history;
  @override String get settings   => AppStringsES.settings;
}

class _SFR implements _S {
  @override String get calculator => AppStringsFR.calculator;
  @override String get history    => AppStringsFR.history;
  @override String get settings   => AppStringsFR.settings;
}

_S _strings(bool useAlt) {
  if (FlavorConfig.isUS && useAlt) return _SES();
  if (FlavorConfig.isCA && useAlt) return _SFR();
  return _SEN();
}
