import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import 'package:calcwise_core/calcwise_core.dart'
    show
        themeModeService,
        PaywallSessionService,
        CalcwiseAdService,
        CalcwiseAdConfig,
        requestCalcwiseConsent,
        CalcwiseAdFooter,
        CalcwiseRewardAdSheet,
        PaywallTrigger,
        PaywallHard,
        PaywallSoft,
        AppDuration,
        iapErrorNotifier,
        showIapErrorSnackBar;
import 'package:shared_preferences/shared_preferences.dart';
import 'core/firebase/firebase_options.dart';
import 'core/analytics/analytics_service.dart';
import 'core/services/crashlytics_service.dart';
import 'core/freemium/freemium_service.dart';
import 'core/freemium/iap_service.dart';
import 'core/ads/ad_config.dart';
import 'core/flavor_config.dart';
import 'core/theme/app_theme.dart';
import 'l10n/strings_en.dart';
import 'l10n/strings_es.dart';
import 'l10n/strings_fr.dart';
import 'screens/splash_screen.dart';
import 'screens/calculator_screen.dart';
import 'screens/reports_screen.dart';
import 'screens/tools_screen.dart';
import 'screens/history_screen.dart';
import 'screens/settings_screen.dart';

final paywallSession = PaywallSessionService(appKey: 'salaryapp');

final adService = CalcwiseAdService(
  config: CalcwiseAdConfig(
    bannerAndroid: AdConfig.bannerAndroid,
    interstitialAndroid: AdConfig.interstitialAndroid,
    rewardedAndroid: AdConfig.rewardedAndroid,
    calcThreshold: AdConfig.calcThreshold,
    cooldownMinutes: AdConfig.cooldownMinutes,
  ),
  freemium: freemiumService,
  analytics: analyticsService,
);

// ─── Global language notifier ─────────────────────────────────────────────────
// For US: true = Spanish  |  For CA: true = French  |  For UK: ignored
final ValueNotifier<bool> isSpanishNotifier = ValueNotifier<bool>(false);

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  await CrashlyticsService.init();
  await analyticsService.initialize();
  await analyticsService.logAppOpen();
  await freemiumService.initialize();
  await paywallSession.initialize();
  await IAPService.instance.initialize();
  await requestCalcwiseConsent();
  await MobileAds.instance.initialize();
  if (AdConfig.adsEnabled) await adService.initialize();
  await themeModeService.initialize();

  // Auto-detect preferred alternate language at startup
  // Saved preference takes priority; falls back to system locale.
  {
    final locales = PlatformDispatcher.instance.locales;
    final systemLang = locales.isNotEmpty ? locales.first.languageCode : 'en';
    final prefs = await SharedPreferences.getInstance();
    final savedLang = prefs.getString('language');
    if (FlavorConfig.isCA) {
      isSpanishNotifier.value = (savedLang ?? systemLang) == 'fr';
    } else if (FlavorConfig.isUS) {
      isSpanishNotifier.value = (savedLang ?? systemLang) == 'es';
    }
    // UK: isSpanishNotifier stays false — no alternate language
  }

  SystemChrome.setPreferredOrientations(
      [DeviceOrientation.portraitUp, DeviceOrientation.portraitDown]);

  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    systemNavigationBarColor: Color(0xFF0D0B1E),
    systemNavigationBarIconBrightness: Brightness.light,
  ));

  CalcwiseAdFooter.configure(
    adService: adService,
    freemium: freemiumService,
    isSpanishNotifier: isSpanishNotifier,
    onGetPremium: () => IAPService.instance.buy(),
  );
  CalcwiseRewardAdSheet.configure(
    adService: adService,
    freemium: freemiumService,
    isSpanishNotifier: isSpanishNotifier,
  );
  runApp(const SalaryApp());
}

class SalaryApp extends StatelessWidget {
  const SalaryApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: themeModeService.notifier,
      builder: (_, themeMode, __) => MaterialApp(
        debugShowCheckedModeBanner: false,
        title: AppStringsEN.appName,
        theme: AppTheme.theme,
        darkTheme: AppTheme.dark,
        themeMode: themeMode,
        initialRoute: '/',
        // Custom route builder: fade transition eliminates the white flash
        // that the default slide animation exposes.
        onGenerateRoute: (settings) {
          final Widget page = switch (settings.name) {
            '/home' => const MainShell(),
            _ => const SplashScreen(),
          };
          return PageRouteBuilder(
            settings: settings,
            pageBuilder: (_, __, ___) => page,
            transitionsBuilder: (_, anim, __, child) =>
                FadeTransition(opacity: anim, child: child),
            transitionDuration: AppDuration.base,
            reverseTransitionDuration: const Duration(milliseconds: 200),
          );
        },
      ),
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
    ReportsScreen(),
    ToolsScreen(),
    HistoryScreen(),
  ];

  @override
  void initState() {
    super.initState();
    iapErrorNotifier.addListener(_onIapError);
  }

  @override
  void dispose() {
    iapErrorNotifier.removeListener(_onIapError);
    super.dispose();
  }

  void _onIapError() {
    final msg = iapErrorNotifier.value;
    if (msg == null || !mounted) return;
    showIapErrorSnackBar(context, msg);
    iapErrorNotifier.value = null;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle(
      systemNavigationBarColor: Theme.of(context).scaffoldBackgroundColor,
      systemNavigationBarIconBrightness:
          isDark ? Brightness.light : Brightness.dark,
    ));
    return ValueListenableBuilder<bool>(
      valueListenable: isSpanishNotifier,
      builder: (context, useAlt, _) {
        final s = _strings(useAlt);
        return Scaffold(
          body: IndexedStack(index: _index, children: _pages),
          bottomNavigationBar: NavigationBar(
            selectedIndex: _index,
            onDestinationSelected: (i) async {
              analyticsService.logTabSwitch(i);
              setState(() => _index = i);
              final trigger = await paywallSession.recordAction();
              if (!mounted) return;
              if (trigger == PaywallTrigger.hard) {
                analyticsService.logPaywallViewed('session_hard');
                PaywallHard.show(context);
              } else if (trigger == PaywallTrigger.soft) {
                analyticsService.logPaywallViewed('session_soft');
                PaywallSoft.show(context, featureTitle: 'Unlimited Saves');
              }
            },
            destinations: [
              NavigationDestination(
                icon: const Icon(Icons.calculate_rounded),
                selectedIcon: const Icon(Icons.calculate),
                label: s.calculator,
              ),
              NavigationDestination(
                icon: const Icon(Icons.bar_chart_rounded),
                selectedIcon: const Icon(Icons.bar_chart_rounded),
                label: useAlt ? 'Reportes' : 'Reports',
              ),
              NavigationDestination(
                icon: const Icon(Icons.build_rounded),
                selectedIcon: const Icon(Icons.build),
                label: useAlt ? 'Herramientas' : 'Tools',
              ),
              NavigationDestination(
                icon: const Icon(Icons.history_rounded),
                selectedIcon: const Icon(Icons.history),
                label: s.history,
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
  @override
  String get calculator => AppStringsEN.calculator;
  @override
  String get history => AppStringsEN.history;
  @override
  String get settings => AppStringsEN.settings;
}

class _SES implements _S {
  @override
  String get calculator => AppStringsES.calculator;
  @override
  String get history => AppStringsES.history;
  @override
  String get settings => AppStringsES.settings;
}

class _SFR implements _S {
  @override
  String get calculator => AppStringsFR.calculator;
  @override
  String get history => AppStringsFR.history;
  @override
  String get settings => AppStringsFR.settings;
}

_S _strings(bool useAlt) {
  if (FlavorConfig.isUS && useAlt) return _SES();
  if (FlavorConfig.isCA && useAlt) return _SFR();
  return _SEN();
}
