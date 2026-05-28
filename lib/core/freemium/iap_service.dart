import 'package:flutter/foundation.dart' show ValueNotifier;
import 'package:calcwise_core/calcwise_core.dart';
import '../flavor_config.dart';
import 'freemium_service.dart';

export 'package:calcwise_core/services/iap_service.dart' show iapErrorNotifier;

class IAPService {
  IAPService._();
  static final instance = IAPService._();

  static const productId = 'premium_upgrade';

  // TODO(play-console): Create 'premium_lifetime_uk' as a non-consumable
  // one-time product in Play Console before releasing the UK flavor.
  static const _lifetimeProductIdUK = 'premium_lifetime_uk';

  late final CalcwiseIAP _iap;

  /// Lifetime IAP — UK flavor only. Null on CA/US.
  CalcwiseIAP? _iapLifetime;

  ValueNotifier<String?> get localizedPrice => _iap.localizedPrice;

  /// Localized lifetime price — null until store responds or on non-UK flavors.
  ValueNotifier<String?> get localizedLifetimePrice =>
      _iapLifetime?.localizedPrice ?? ValueNotifier(null);

  Future<void> initialize() async {
    _iap = CalcwiseIAP(
      productId: productId,
      freemium: freemiumService,
      analytics: CalcwiseAnalytics(appName: 'salaryapp'),
      onPurchaseCompleted: () => CalcwiseReviewService.instance.requestReview(),
    );
    await _iap.initialize();
    PaywallHard.registerPrice(_iap.localizedPrice);

    // Initialize lifetime IAP only for the UK flavor.
    if (FlavorConfig.isUK) {
      _iapLifetime = CalcwiseIAP(
        productId: _lifetimeProductIdUK,
        freemium: freemiumService,
        analytics: CalcwiseAnalytics(appName: 'salaryapp'),
        onPurchaseCompleted: () =>
            CalcwiseReviewService.instance.requestReview(),
      );
      await _iapLifetime!.initialize();
    }
  }

  Future<void> buy() => _iap.buy();

  /// Purchase the Lifetime tier (UK only).
  /// Falls back to the standard product if lifetime IAP is not available.
  Future<void> buyLifetime() => _iapLifetime?.buy() ?? _iap.buy();

  Future<void> restore() async {
    await _iap.restore();
    await _iapLifetime?.restore();
  }

  void dispose() {
    _iap.dispose();
    _iapLifetime?.dispose();
  }
}
