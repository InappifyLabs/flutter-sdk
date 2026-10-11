import 'package:flutter/foundation.dart';
import 'package:inappify_sdk/models/enums/market.dart';
import 'package:inappify_sdk/src/billing/store_billing_gateway.dart';

InappifyStoreBillingGateway createStoreBillingGateway() {
  return _MobileStoreBillingGateway();
}

/// Marketplace gateway for mobile Dart implementations.
///
/// iOS behavior is unchanged: NONE initializes successfully; Bazaar/Myket
/// were already unavailable here. Android marketplace purchases now belong
/// exclusively to the native SDK, including recovery, verification and consume.
class _MobileStoreBillingGateway implements InappifyStoreBillingGateway {
  @override
  Future<bool> initialize({
    required Market market,
    required String publicKey,
  }) async {
    if (market == Market.none) return true;
    if (market == Market.myket) {
      // Myket support is temporarily disabled.
      return false;
    }
    if (market != Market.bazar ||
        defaultTargetPlatform != TargetPlatform.android) {
      return false;
    }
    // Only Android reaches here. Never create a second Dart receipt owner.
    return false;
  }

  @override
  Future<InappifyStorePurchase?> purchase({
    required Market market,
    required String publicKey,
    required String productIdentifier,
    required String payload,
  }) async {
    if (market == Market.myket) {
      // Myket support is temporarily disabled.
      return null;
    }
    if (market != Market.bazar ||
        defaultTargetPlatform != TargetPlatform.android ||
        publicKey.isEmpty) {
      return null;
    }
    // Only Android reaches here; its MethodChannel SDK owns store purchases.
    return null;
  }
}
