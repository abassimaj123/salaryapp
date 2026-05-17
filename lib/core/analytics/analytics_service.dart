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
}

final analyticsService = AnalyticsService.instance;
