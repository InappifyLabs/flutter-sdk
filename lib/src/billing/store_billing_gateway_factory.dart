import 'package:inappify_sdk/src/billing/store_billing_gateway.dart';
import 'package:inappify_sdk/src/billing/store_billing_gateway_stub.dart'
    if (dart.library.io) 'package:inappify_sdk/src/billing/store_billing_gateway_mobile.dart'
    as implementation;

/// Creates the billing implementation supported by the current Dart runtime.
InappifyStoreBillingGateway createStoreBillingGateway() {
  return implementation.createStoreBillingGateway();
}
