import 'package:inappify_sdk/models/enums/market.dart';
import 'package:inappify_sdk/src/billing/store_billing_gateway.dart';

InappifyStoreBillingGateway createStoreBillingGateway() {
  return _UnsupportedStoreBillingGateway();
}

/// Browser-safe fallback used when no marketplace SDK is available.
class _UnsupportedStoreBillingGateway implements InappifyStoreBillingGateway {
  @override
  Future<bool> initialize({
    required Market market,
    required String publicKey,
  }) async {
    return market == Market.none;
  }

  @override
  Future<InappifyStorePurchase?> purchase({
    required Market market,
    required String publicKey,
    required String productIdentifier,
    required String payload,
  }) async {
    return null;
  }
}
