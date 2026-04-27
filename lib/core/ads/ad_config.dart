// ── AdMob Configuration ───────────────────────────────────────────────────────
// Publisher: ca-app-pub-5379540026739666
// BEFORE RELEASE: Replace placeholder IDs with real AdMob IDs from console.
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

  // ── Android Ad Unit IDs ───────────────────────────────────────────────────────
  // Release: replace with real IDs for com.mortgageca.calculator
  static String get bannerAndroid => kReleaseMode
      ? 'ca-app-pub-5379540026739666/XXXXXXXXXX'
      : 'ca-app-pub-3940256099942544/6300978111';
  static String get interstitialAndroid => kReleaseMode
      ? 'ca-app-pub-5379540026739666/XXXXXXXXXX'
      : 'ca-app-pub-3940256099942544/1033173712';
  static String get rewardedAndroid => kReleaseMode
      ? 'ca-app-pub-5379540026739666/XXXXXXXXXX'
      : 'ca-app-pub-3940256099942544/5224354917';

  // ── iOS Ad Unit IDs ───────────────────────────────────────────────────────────
  static String get banneriOS => kReleaseMode
      ? 'ca-app-pub-5379540026739666/XXXXXXXXXX'
      : 'ca-app-pub-3940256099942544/2934735716';
  static String get interstitialiOS => kReleaseMode
      ? 'ca-app-pub-5379540026739666/XXXXXXXXXX'
      : 'ca-app-pub-3940256099942544/4411468910';
  static String get rewardediOS => kReleaseMode
      ? 'ca-app-pub-5379540026739666/XXXXXXXXXX'
      : 'ca-app-pub-3940256099942544/1712485313';

  // ── Gate settings ─────────────────────────────────────────────────────────────
  static const int calcThreshold = 5; // interstitial every N calcs
  static const int cooldownMinutes = 5; // min between interstitials
}
