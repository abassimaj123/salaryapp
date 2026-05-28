import 'package:calcwise_core/calcwise_core.dart';

/// Firebase Analytics wrapper for SalaryApp.
/// Common events inherited from CalcwiseAnalytics.
/// SalaryApp-specific events (salary calc, paywall variants, tab switch) kept here.
class AnalyticsService extends CalcwiseAnalytics {
  AnalyticsService._() : super(appName: 'SalaryApp');
  static final AnalyticsService instance = AnalyticsService._();

  // ── Calculator (SalaryApp-specific) ──────────────────────────────────────

  Future<void> logCalculation({
    required double grossSalary,
    required double netSalary,
    required String frequency,
  }) =>
      log('salary_calculated', {
        'gross_salary': grossSalary.round(),
        'net_salary': netSalary.round(),
        'frequency': frequency,
      });

  Future<void> logSave() => log('calculation_saved');

  // ── App-specific events ───────────────────────────────────────────────────

  Future<void> logTabSwitch(int i) => log('tab_switched', {'tab_index': i});
  Future<void> logPaywallSoftShown() => log('paywall_soft_shown');
  Future<void> logPaywallHardShown() => log('paywall_hard_shown');
  Future<void> logPaywallBuyTapped() => log('paywall_buy_tapped');
  Future<void> logPurchaseSuccess() => log('iap_purchase_success');
  Future<void> logPurchaseError(String r) =>
      log('iap_purchase_error', {'reason': r});
  Future<void> logRewardedVideoWatched() => log('rewarded_video_watched');
  Future<void> logShareResult() => log('share_result');

  // ── Canonical taxonomy (MortgageUS reference) ────────────────────────────

  Future<void> logCalculationCompleted({Map<String, Object>? params}) =>
      log('calculation_completed', params);
  Future<void> logResultSaved() => log('result_saved');
  Future<void> logResultShared() => log('result_shared');
  Future<void> logPaywallViewed(String trigger) =>
      log('paywall_viewed', {'trigger': trigger});
  Future<void> logPaywallConverted(String source) =>
      log('paywall_converted', {'source': source});

  // ── Universal events (Phase 2) ────────────────────────────────────────────

  Future<void> logScreenView(String screenName) =>
      log('screen_view', {'screen_name': screenName});
  Future<void> logOnboardingComplete() => log('onboarding_complete');
  Future<void> logOnboardingSkipped() => log('onboarding_skipped');
  Future<void> logFirstCalculate() => log('first_calculate');
  Future<void> logDarkModeToggled(bool enabled) =>
      log('dark_mode_toggled', {'enabled': '$enabled'});
  Future<void> logLanguageChanged(String lang) =>
      log('language_changed', {'language': lang});
  Future<void> logShareTapped() => log('share_tapped');
  Future<void> logExportStarted() => log('export_started');
  Future<void> logUpgradeButtonTapped(String source) =>
      log('upgrade_tapped', {'source': source});
  Future<void> logFeatureGated(String feature) =>
      log('feature_gated', {'feature': feature});

  // ── SalaryApp domain events (Phase 2) ────────────────────────────────────

  Future<void> logProvinceSwitched(String province) =>
      log('province_switched', {'province': province});
  Future<void> logBonusCalculated() => log('bonus_calculated');
  Future<void> logJobOfferCompared() => log('job_offer_compared');
  Future<void> logRrspImpactCalculated() => log('rrsp_impact_calculated');
}

final analyticsService = AnalyticsService.instance;
