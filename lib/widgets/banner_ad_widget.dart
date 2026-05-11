import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import '../config/ad_config.dart';
import '../core/freemium/freemium_service.dart';
import '../core/analytics/analytics_service.dart';

class BannerAdWidget extends StatefulWidget {
  const BannerAdWidget({super.key});
  @override
  State<BannerAdWidget> createState() => _State();
}
class _State extends State<BannerAdWidget> {
  BannerAd? _ad;
  bool _loaded = false;
  bool _retried = false;
  @override
  void initState() { super.initState(); _load(); }
  void _load() {
    _ad = BannerAd(
      adUnitId: AdConfig.bannerAndroid, size: AdSize.banner,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (_) { if (mounted) setState(() => _loaded = true); },
        onAdFailedToLoad: (ad, error) {
          ad.dispose();
          if (!mounted) return;
          setState(() { _ad = null; _loaded = false; });
          AnalyticsService.instance.logBannerFailed();
          if (!_retried) {
            _retried = true;
            Future.delayed(const Duration(seconds: 3), () {
              if (mounted) _load();
            });
          }
        },
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
        if (!_loaded || _ad == null) return SizedBox(height: 50);
        return SizedBox(
          width: _ad!.size.width.toDouble(),
          height: _ad!.size.height.toDouble(),
          child: AdWidget(ad: _ad!),
        );
      },
    );
  }
}
