// ── AdMob Configuration ───────────────────────────────────────────────────────
// Publisher: ca-app-pub-5379540026739666
// Production IDs injected at build via --dart-define-from-file=admob.json.
// Blank/unset prod values fall back to Google TEST IDs (never ship placeholders).
//   flutter build appbundle --release --dart-define-from-file=admob.json --flavor us
// App ID goes in android/local.properties (admob.salary.appId.{us,uk,ca}).
//
// Rules (enforced by AdService):
//   Banner        → permanent, Calculator screen bottom
//   Interstitial  → after every 5 calculations, min 5-min cooldown
//   Rewarded      → onRewarded callback
//   NO App Open Ad

import 'package:flutter/foundation.dart';

class AdConfig {
  AdConfig._();

  static const bool adsEnabled = true;

  // ── App IDs ──────────────────────────────────────────────────────────────────
  static const String androidAppId =
      'ca-app-pub-3940256099942544~3347511713'; // TEST
  static const String iosAppId =
      'ca-app-pub-3940256099942544~1458002511'; // TEST

  // ── Google official TEST ad unit IDs (debug + release fallback) ───────────────
  static const _testBannerAndroid = 'ca-app-pub-3940256099942544/6300978111';
  static const _testInterstitialAndroid = 'ca-app-pub-3940256099942544/1033173712';
  static const _testRewardedAndroid = 'ca-app-pub-3940256099942544/5224354917';
  static const _testBannerIOS = 'ca-app-pub-3940256099942544/2934735716';
  static const _testInterstitialIOS = 'ca-app-pub-3940256099942544/4411468910';
  static const _testRewardedIOS = 'ca-app-pub-3940256099942544/1712485313';

  // ── Production IDs injected via --dart-define-from-file=admob.json ─────────────
  static const _prodBannerAndroid = String.fromEnvironment('ADMOB_BANNER_ANDROID');
  static const _prodInterstitialAndroid = String.fromEnvironment('ADMOB_INTERSTITIAL_ANDROID');
  static const _prodRewardedAndroid = String.fromEnvironment('ADMOB_REWARDED_ANDROID');
  static const _prodBannerIOS = String.fromEnvironment('ADMOB_BANNER_IOS');
  static const _prodInterstitialIOS = String.fromEnvironment('ADMOB_INTERSTITIAL_IOS');
  static const _prodRewardedIOS = String.fromEnvironment('ADMOB_REWARDED_IOS');

  // ── Android Ad Unit IDs ───────────────────────────────────────────────────────
  static String get bannerAndroid => kReleaseMode && _prodBannerAndroid.isNotEmpty
      ? _prodBannerAndroid
      : _testBannerAndroid;
  static String get interstitialAndroid => kReleaseMode && _prodInterstitialAndroid.isNotEmpty
      ? _prodInterstitialAndroid
      : _testInterstitialAndroid;
  static String get rewardedAndroid => kReleaseMode && _prodRewardedAndroid.isNotEmpty
      ? _prodRewardedAndroid
      : _testRewardedAndroid;

  // ── iOS Ad Unit IDs ───────────────────────────────────────────────────────────
  static String get banneriOS => kReleaseMode && _prodBannerIOS.isNotEmpty
      ? _prodBannerIOS
      : _testBannerIOS;
  static String get interstitialiOS => kReleaseMode && _prodInterstitialIOS.isNotEmpty
      ? _prodInterstitialIOS
      : _testInterstitialIOS;
  static String get rewardediOS => kReleaseMode && _prodRewardedIOS.isNotEmpty
      ? _prodRewardedIOS
      : _testRewardedIOS;

  // ── Gate settings ─────────────────────────────────────────────────────────────
  static const int calcThreshold = 3; // interstitial every N calcs
  static const int cooldownMinutes = 5; // min between interstitials
}
