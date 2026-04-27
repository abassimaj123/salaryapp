import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import '../config/ad_config.dart';
import '../core/freemium/freemium_service.dart';

class BannerAdWidget extends StatefulWidget {
  const BannerAdWidget({super.key});
  @override
  State<BannerAdWidget> createState() => _State();
}
class _State extends State<BannerAdWidget> {
  BannerAd? _ad;
  bool _loaded = false;
  @override
  void initState() { super.initState(); _load(); }
  void _load() {
    _ad = BannerAd(
      adUnitId: AdConfig.bannerAndroid, size: AdSize.banner,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (_) => setState(() => _loaded = true),
        onAdFailedToLoad: (_, __) { _ad?.dispose(); _ad = null; },
      ),
    )..load();
  }
  @override
  void dispose() { _ad?.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) {
    if (!AdConfig.adsEnabled) return const SizedBox.shrink();
    return ValueListenableBuilder<bool>(
      valueListenable: freemiumService.isPremiumNotifier,
      builder: (_, isPremium, __) {
        if (isPremium) return const SizedBox.shrink();
        return ValueListenableBuilder<bool>(
          valueListenable: freemiumService.isRewardedNotifier,
          builder: (_, isRewarded, __) {
            if (isRewarded) return const SizedBox.shrink();
            if (!_loaded || _ad == null) return const SizedBox(height: 50);
            return SizedBox(
              width: _ad!.size.width.toDouble(),
              height: _ad!.size.height.toDouble(),
              child: AdWidget(ad: _ad!),
            );
          },
        );
      },
    );
  }
}
