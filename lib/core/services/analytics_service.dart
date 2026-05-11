import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:flutter/foundation.dart';

/// Centralized Firebase Analytics wrapper for SalaryApp.
class AnalyticsService {
  AnalyticsService._();
  static final AnalyticsService instance = AnalyticsService._();

  final _fa = FirebaseAnalytics.instance;

  // ── Lifecycle ─────────────────────────────────────────────────────────────

  Future<void> logAppOpen() => _log('app_open');

  // ── Navigation ────────────────────────────────────────────────────────────

  Future<void> logTabChanged(String tabName) => _log('tab_changed', {
    'tab': tabName, // calculator|breakdown|compare|tools
  });

  // ── Calculator ────────────────────────────────────────────────────────────

  Future<void> logCalculation({
    required double grossSalary,
    required String period, // hourly|weekly|biweekly|monthly|annual
    required String country,
  }) => _log('calculate', {
    'salary_bucket': _salaryBucket(grossSalary),
    'period': period,
    'country': country,
  });

  // ── Paywall ───────────────────────────────────────────────────────────────

  Future<void> logPaywallShown(String type) => _log('paywall_shown', {
    'type': type, // soft | hard
  });

  Future<void> logPurchaseStarted() => _log('purchase_started');

  Future<void> logPurchaseCompleted() async {
    await _log('purchase_completed');
    await _fa.logEvent(name: 'purchase', parameters: {
      'currency': 'USD',
      'value':    3.99,
      'items':    'premium_salary_app',
    });
  }

  Future<void> logPurchaseRestored() => _log('purchase_restored');
  Future<void> logPurchaseFailed()   => _log('purchase_failed');

  Future<void> logRewardedAdWatched() => _log('rewarded_ad_watched');

  // ── Features ─────────────────────────────────────────────────────────────

  Future<void> logPdfExported()         => _log('pdf_exported');
  Future<void> logComparisonUsed()      => _log('comparison_used');
  Future<void> logRaiseCalculated()     => _log('raise_calculated');
  Future<void> logOvertimeCalculated()  => _log('overtime_calculated');
  Future<void> logHistorySaved()        => _log('history_saved');

  // ── User property ─────────────────────────────────────────────────────────

  Future<void> setUserPremium(bool isPremium) =>
      _fa.setUserProperty(name: 'is_premium', value: isPremium ? 'true' : 'false');

  // ── Error & limit tracking ────────────────────────────────────────────────

  Future<void> logRewardedAdFailed()   => _log('rewarded_ad_failed');
  Future<void> logPaywallDismissed()   => _log('paywall_dismissed');
  Future<void> logBannerFailed()       => _log('banner_ad_failed');

  // ── Internals ─────────────────────────────────────────────────────────────

  Future<void> _log(String name, [Map<String, Object>? params]) async {
    final merged = <String, Object>{'app_name': 'SalaryApp', ...?params};
    if (kDebugMode) {
      debugPrint('[Analytics] $name $merged');
      return;
    }
    await _fa.logEvent(name: name, parameters: merged);
  }

  String _salaryBucket(double annual) {
    if (annual < 30000)  return '<30k';
    if (annual < 60000)  return '30-60k';
    if (annual < 100000) return '60-100k';
    if (annual < 150000) return '100-150k';
    return '>150k';
  }
}
