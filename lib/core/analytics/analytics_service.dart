import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:flutter/foundation.dart';

class AnalyticsService {
  AnalyticsService._();
  static final instance = AnalyticsService._();
  FirebaseAnalytics? _analytics;

  Future<void> initialize() async {
    try {
      _analytics = FirebaseAnalytics.instance;
    } catch (e) {
      debugPrint('Analytics init: $e');
    }
  }


  // ── Error & limit tracking ──────────────────────────────────────────────
  Future<void> logRewardedAdFailed() => _log('rewarded_ad_failed');
  Future<void> logRewardedDailyLimit() => _log('rewarded_daily_limit_reached');
  Future<void> logPurchaseFailed() => _log('purchase_failed');
  Future<void> logBannerFailed() => _log('banner_ad_failed');

  Future<void> _log(String name, [Map<String, Object>? params]) async {
    try {
      final merged = {'app_name': 'SalaryApp', ...?params};
      await _analytics?.logEvent(name: name, parameters: merged);
    } catch (e) {
      debugPrint('Analytics $name: $e');
    }
  }

  Future<void> logAppOpen() => _log('app_open');

  Future<void> logCalculation({
    required double grossSalary,
    required double netSalary,
    required String frequency,
  }) =>
      _log('salary_calculated', {
        'gross_salary': grossSalary.round(),
        'net_salary': netSalary.round(),
        'frequency': frequency,
      });

  Future<void> logSave() => _log('calculation_saved');

  Future<void> logPdfExported() => _log('pdf_exported');
  Future<void> logPaywallSoftShown() => _log('paywall_soft_shown');
  Future<void> logPaywallHardShown() => _log('paywall_hard_shown');
  Future<void> logPaywallBuyTapped() => _log('paywall_buy_tapped');
  Future<void> logPaywallDismissed() => _log('paywall_dismissed');
  Future<void> logPurchaseStarted() => _log('iap_purchase_started');
  Future<void> logPurchaseSuccess() => _log('iap_purchase_success');
  Future<void> logPurchaseError(String r) =>
      _log('iap_purchase_error', {'reason': r});
  Future<void> logRewardedVideoWatched() => _log('rewarded_video_watched');
  Future<void> logShareResult() => _log('share_result');
  Future<void> logTabSwitch(int i) =>
      _log('tab_switched', {'tab_index': i});
  Future<void> logHistoryViewed() => _log('history_viewed');
}

final analyticsService = AnalyticsService.instance;
