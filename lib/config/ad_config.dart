// AdMob — publisher ca-app-pub-5379540026739666
// BEFORE RELEASE: replace XXXXXXXXXX with real unit IDs.
import 'package:flutter/foundation.dart';

class AdConfig {
  AdConfig._();
  static const bool adsEnabled = true;
  static const int calcThreshold = 8;
  static const int cooldownMinutes = 5;

  static String get bannerAndroid => kReleaseMode
      ? 'ca-app-pub-5379540026739666/XXXXXXXXXX'
      : 'ca-app-pub-3940256099942544/6300978111';
  static String get interstitialAndroid => kReleaseMode
      ? 'ca-app-pub-5379540026739666/XXXXXXXXXX'
      : 'ca-app-pub-3940256099942544/1033173712';
  static String get rewardedAndroid => kReleaseMode
      ? 'ca-app-pub-5379540026739666/XXXXXXXXXX'
      : 'ca-app-pub-3940256099942544/5224354917';

  // ── iOS Ad Unit IDs (opt-in — only wired when activate_ios.sh runs) ──────
  // TODO iOS: replace XXXXXXXXXX with real iOS unit IDs before App Store submission.
  static String get banneriOS => kReleaseMode
      ? 'ca-app-pub-5379540026739666/XXXXXXXXXX'
      : 'ca-app-pub-3940256099942544/2934735716';
  static String get interstitialiOS => kReleaseMode
      ? 'ca-app-pub-5379540026739666/XXXXXXXXXX'
      : 'ca-app-pub-3940256099942544/4411468910';
  static String get rewardediOS => kReleaseMode
      ? 'ca-app-pub-5379540026739666/XXXXXXXXXX'
      : 'ca-app-pub-3940256099942544/1712485313';
}
