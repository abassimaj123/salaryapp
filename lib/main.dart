import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'package:calcwise_core/calcwise_core.dart'
    show
        themeModeService,
        PaywallSessionService,
        CalcwiseAdService,
        CalcwiseAdConfig,
        requestCalcwiseConsent,
        CalcwiseAdFooter,
        CalcwiseRewardAdSheet,
        CalcwiseAppBarActions,
        PaywallTrigger,
        PaywallSoft,
        AppDuration,
        iapErrorNotifier,
        iapRestoreResultNotifier,
        showIapErrorSnackBar,
        showPremiumWelcomeSnackBar,
        SmartHistoryService,
        CalcwiseTabReveal,
        CalcwiseTax,
        calcwiseTaxRemoteFetch,
        CalcwiseRemoteConfig;
import 'core/db/salary_database_adapter.dart';
import 'widgets/paywall_hard.dart';
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

final paywallSession = PaywallSessionService(
  appKey: 'salaryapp',
  hasFullAccess: () => freemiumService.hasFullAccess,
);

/// SmartHistory ring-buffer + Save Scenario service.
/// Free: 5 auto-saves (FIFO) + 3 pinned | Premium: 20 auto-saves + unlimited pinned.
final historyService = SmartHistoryService(
  db: SalaryDatabaseAdapter(),
  freemium: freemiumService,
);

final adService = CalcwiseAdService(
  config: CalcwiseAdConfig(
    bannerAndroid: AdConfig.bannerAndroid,
    interstitialAndroid: AdConfig.interstitialAndroid,
    rewardedAndroid: AdConfig.rewardedAndroid,
  ),
  freemium: freemiumService,
  analytics: analyticsService,
);

// ─── Global language notifier ─────────────────────────────────────────────────
// For US: true = Spanish  |  For CA: true = French  |  For UK: ignored
final ValueNotifier<bool> isSpanishNotifier = ValueNotifier<bool>(false);

/// Holds the last-calculated gross annual salary so secondary screens can pre-fill.
final ValueNotifier<double> salaryNotifier = ValueNotifier<double>(75000);

/// UK flavor only: whether student loan repayment is included in the calculation.
final ValueNotifier<bool> ukStudentLoanNotifier = ValueNotifier<bool>(false);

/// UK flavor only: whether Scottish income tax rates apply.
final ValueNotifier<bool> ukScotlandNotifier = ValueNotifier<bool>(false);

/// Set to tab index to programmatically switch tabs from any screen.
final tabSwitchNotifier = ValueNotifier<int>(-1);

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('en_US', null);
  await initializeDateFormatting('en_CA', null);
  await initializeDateFormatting('es_US', null);
  await initializeDateFormatting('fr_CA', null);

  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  unawaited(CalcwiseRemoteConfig.initialize());
  // Centralized tax tables: baked-in floor now, upgraded to the remote dataset
  // when available. Fails safe to baked/cached — never blocks startup.
  await CalcwiseTax.init(remoteFetcher: calcwiseTaxRemoteFetch);

  await CrashlyticsService.init();
  await analyticsService.initialize();
  await analyticsService.logAppOpen();
  await freemiumService.initialize();
  await paywallSession.initialize();
  await IAPService.instance.initialize();
  await requestCalcwiseConsent();
  await MobileAds.instance.initialize();
  if (kDebugMode) {
    await MobileAds.instance.updateRequestConfiguration(
      RequestConfiguration(testDeviceIds: ['FD16D4616C3A21C3ACE5E48F8DC9C1DC']),
    );
  }
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

  // Brightness-aware override is applied in MainShell.build(); set safe
  // defaults here so the splash doesn't show a wrong nav-bar color.
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
  ));

  AnalyticsService.instance.setUserPremium(freemiumService.hasFullAccess);

  CalcwiseAdFooter.configure(
    adService: adService,
    freemium: freemiumService,
    // CA: isSpanishNotifier means French — pass as isFrenchNotifier instead
    isSpanishNotifier: FlavorConfig.isUS ? isSpanishNotifier : null,
    isFrenchNotifier: FlavorConfig.isCA ? isSpanishNotifier : null,
    onGetPremium: () => IAPService.instance.buy(),
    analytics: AnalyticsService.instance,
  );
  CalcwiseRewardAdSheet.configure(
    adService: adService,
    freemium: freemiumService,
    isSpanishNotifier: FlavorConfig.isUS ? isSpanishNotifier : null,
    isFrenchNotifier: FlavorConfig.isCA ? isSpanishNotifier : null,
  );
  PaywallHard.setAnalytics(AnalyticsService.instance);
  PaywallSoft.setAnalytics(AnalyticsService.instance);
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
        navigatorObservers: [FirebaseAnalyticsObserver(analytics: FirebaseAnalytics.instance)],
        builder: (context, child) {
          if (!MediaQuery.of(context).disableAnimations) return child!;
          return Theme(
            data: Theme.of(context).copyWith(
              pageTransitionsTheme: const PageTransitionsTheme(
                builders: {
                  TargetPlatform.android: _NoAnimPageTransitionsBuilder(),
                  TargetPlatform.iOS: _NoAnimPageTransitionsBuilder(),
                },
              ),
            ),
            child: child!,
          );
        },
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
  bool _wasPremium = false;

  static const _pages = <Widget>[
    CalculatorScreen(),
    ReportsScreen(),
    ToolsScreen(),
    HistoryScreen(),
  ];

  @override
  void initState() {
    super.initState();
    _wasPremium = freemiumService.hasFullAccess;
    freemiumService.isPremiumNotifier.addListener(_onPremiumChange);
    tabSwitchNotifier.addListener(_onTabSwitch);
    iapErrorNotifier.addListener(_onIapError);
    iapRestoreResultNotifier.addListener(_onRestoreResult);
    WidgetsBinding.instance.addPostFrameCallback(
      (_) async => await paywallSession.recordSession(),
    );
  }

  @override
  void dispose() {
    freemiumService.isPremiumNotifier.removeListener(_onPremiumChange);
    tabSwitchNotifier.removeListener(_onTabSwitch);
    iapErrorNotifier.removeListener(_onIapError);
    iapRestoreResultNotifier.removeListener(_onRestoreResult);
    super.dispose();
  }

  void _onRestoreResult() {
    final result = iapRestoreResultNotifier.value;
    if (result == null || !mounted) return;
    final useAlt = isSpanishNotifier.value;
    final es = FlavorConfig.isUS && useAlt;
    final fr = FlavorConfig.isCA && useAlt;
    final msg = result == 'restored'
        ? (fr ? 'Premium restauré !' : (es ? '¡Premium restaurado!' : 'Premium restored!'))
        : (fr ? 'Aucun achat à restaurer.' : (es ? 'No hay compras para restaurar.' : 'No purchases to restore.'));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating),
    );
    iapRestoreResultNotifier.value = null;
  }

  void _onPremiumChange() {
    final now = freemiumService.hasFullAccess;
    if (now && !_wasPremium && mounted) {
      showPremiumWelcomeSnackBar(context, isSpanish: isSpanishNotifier.value);
      try { AnalyticsService.instance.logPaywallConverted('iap'); } catch (_) {}
    }
    _wasPremium = now;
    unawaited(AnalyticsService.instance.setUserPremium(now));
  }

  void _onIapError() {
    final msg = iapErrorNotifier.value;
    if (msg == null || !mounted) return;
    showIapErrorSnackBar(context, msg);
    iapErrorNotifier.value = null;
  }

  void _onTabSwitch() {
    final idx = tabSwitchNotifier.value;
    if (idx >= 0 && mounted) {
      setState(() => _index = idx);
      tabSwitchNotifier.value = -1;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle(
      systemNavigationBarColor: Theme.of(context).colorScheme.surface,
      systemNavigationBarIconBrightness:
          isDark ? Brightness.light : Brightness.dark,
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
    ));
    return ValueListenableBuilder<bool>(
      valueListenable: isSpanishNotifier,
      builder: (context, useAlt, _) {
        final s = _strings(useAlt);
        final es = FlavorConfig.isUS && useAlt;
        final fr = FlavorConfig.isCA && useAlt;
        final tabTitles = [
          fr ? 'Calculateur' : (es ? 'Calculadora' : 'Calculator'),
          fr ? 'Rapports' : (es ? 'Reportes' : 'Reports'),
          fr ? 'Outils' : (es ? 'Herramientas' : 'Tools'),
          fr ? 'Historique' : (es ? 'Historial' : 'History'),
        ];
        final tabIcons = [
          Icons.calculate_rounded,
          Icons.bar_chart_rounded,
          Icons.build_rounded,
          Icons.history_rounded,
        ];
        return Scaffold(
          appBar: AppBar(
            flexibleSpace: Container(
              decoration: BoxDecoration(gradient: AppTheme.primaryGradient),
            ),
            title: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(tabIcons[_index], color: Colors.white, size: 22),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    tabTitles[_index],
                    style: const TextStyle(color: Colors.white),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            iconTheme: const IconThemeData(color: Colors.white),
            actions: [
              CalcwiseAppBarActions(
                freemium: freemiumService,
                session: paywallSession,
                onSettings: () => Navigator.push(
                  context,
                  PageRouteBuilder(
                    pageBuilder: (_, __, ___) => const SettingsScreen(),
                    transitionsBuilder: (_, anim, __, child) =>
                        FadeTransition(opacity: anim, child: child),
                    transitionDuration: AppDuration.base,
                  ),
                ),
                onRewardAd: () => CalcwiseRewardAdSheet.show(context),
                onPremium: () {
                  PaywallHard.show(context,
                      isSpanish: es,
                      isFrench: fr,
                      priceLabel: IAPService.instance.localizedPrice.value,
                      onPurchase: IAPService.instance.buy);
                },
              ),
            ],
          ),
          body: Stack(
            fit: StackFit.expand,
            children: List.generate(
              _pages.length,
              (i) => IgnorePointer(
                ignoring: _index != i,
                child: CalcwiseTabReveal(active: _index == i, child: _pages[i]),
              ),
            ),
          ),
          bottomNavigationBar: NavigationBar(
            selectedIndex: _index,
            labelBehavior: NavigationDestinationLabelBehavior.onlyShowSelected,
            onDestinationSelected: (i) async {
              analyticsService.logTabSwitch(i);
              setState(() => _index = i);
              if (i == 0) return;
              adService.onAction();
              final trigger = await paywallSession.recordAction();
              if (!mounted) return;
              if (!(ModalRoute.of(context)?.isCurrent ?? false)) return;
              if (trigger == PaywallTrigger.hard) {
                analyticsService.logPaywallViewed('session_hard');
                PaywallHard.show(context,
                    isSpanish: es,
                    isFrench: fr,
                    priceLabel: IAPService.instance.localizedPrice.value,
                    onPurchase: IAPService.instance.buy);
              } else if (trigger == PaywallTrigger.soft) {
                analyticsService.logPaywallViewed('session_soft');
                PaywallSoft.show(context,
                    isSpanish: es,
                    isFrench: fr,
                    featureTitle: fr
                        ? 'Historique illimité'
                        : (es ? 'Historial ilimitado' : 'Unlimited History'));
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
                label: fr
                    ? 'Rapports'
                    : (es ? 'Reportes' : 'Reports'),
              ),
              NavigationDestination(
                icon: const Icon(Icons.build_rounded),
                selectedIcon: const Icon(Icons.build),
                label: fr
                    ? 'Outils'
                    : (es ? 'Herramientas' : 'Tools'),
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

class _NoAnimPageTransitionsBuilder extends PageTransitionsBuilder {
  const _NoAnimPageTransitionsBuilder();
  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) =>
      child;
}
