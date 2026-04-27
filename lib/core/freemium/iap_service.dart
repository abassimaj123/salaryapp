import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'freemium_service.dart';

class IAPService {
  IAPService._();
  static final instance = IAPService._();

  /// Must match the product ID created in Google Play Console.
  static const productId = 'premium_upgrade';

  StreamSubscription<List<PurchaseDetails>>? _sub;

  Future<void> initialize() async {
    _sub = InAppPurchase.instance.purchaseStream.listen(_handlePurchases);
    try {
      await InAppPurchase.instance.restorePurchases();
    } catch (e) {
      debugPrint('IAP restore error: $e');
    }
  }

  /// Initiate the purchase flow. Call from a button tap.
  Future<void> buy() async {
    final available = await InAppPurchase.instance.isAvailable();
    if (!available) {
      debugPrint('IAP not available on this device');
      return;
    }
    final response =
        await InAppPurchase.instance.queryProductDetails({productId});
    if (response.productDetails.isEmpty) {
      debugPrint('IAP product not found: $productId — check Play Console');
      return;
    }
    final param =
        PurchaseParam(productDetails: response.productDetails.first);
    await InAppPurchase.instance.buyNonConsumable(purchaseParam: param);
  }

  /// Restore a previous purchase (required for Google Play policy).
  Future<void> restore() async {
    try {
      await InAppPurchase.instance.restorePurchases();
    } catch (e) {
      debugPrint('IAP restore error: $e');
    }
  }

  void _handlePurchases(List<PurchaseDetails> purchases) {
    for (final p in purchases) {
      if (p.productID == productId) {
        if (p.status == PurchaseStatus.purchased ||
            p.status == PurchaseStatus.restored) {
          freemiumService.activatePremium();
          debugPrint('Premium activated');
        } else if (p.status == PurchaseStatus.error) {
          debugPrint('IAP error: ${p.error}');
        }
        if (p.pendingCompletePurchase) {
          InAppPurchase.instance.completePurchase(p);
        }
      }
    }
  }

  void dispose() => _sub?.cancel();
}
