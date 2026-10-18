# Inappify Flutter SDK

Flutter SDK for Inappify sessions, offerings, entitlements and purchases.
The package name is `inappify_sdk`; the current release is **0.1.1**.

| Platform | Session and payment implementation |
| --- | --- |
| Android | [Inappify Kotlin SDK](https://github.com/InappifyLabs/kotlin-sdk), called through MethodChannel; Direct, Bazaar and Myket |
| iOS | Dart V2 client with the iOS storage/metadata companion; Direct payments |
| Web | Adapter for the separately loaded Inappify JavaScript SDK; browser authentication and checkout |

Bazaar and Myket are Android-only. Myket supports consumable and non-consumable
products; subscriptions use Bazaar. Missing Android or Web backends produce a
failure instead of silently creating a different payment session.

## Install

Use Flutter 3.44.0 or newer with Dart 3.12.0 or newer. Add the package dependency:

```yaml
dependencies:
  inappify_sdk: ^0.1.1
```

Run `flutter pub get` and rebuild the app. Android uses the exact native dependency
`com.github.InappifyLabs:kotlin-sdk:v0.1.1`. Follow
[Android setup](doc/ANDROID.md) for repositories, tools and the foreground Activity.
You do not need a separate Flutter billing package or a second native SDK instance.
The GitHub release remains available as an alternative Git dependency pinned to `v0.1.1`.

## Configure

This Android example receives the app's public bootstrap key, a stable host user
identifier and Bazaar's RSA public key from the host application:

```dart
import 'package:inappify_sdk/inappify_sdk.dart';
import 'package:inappify_sdk/models/enums/market.dart';

Future<bool> configureBazaar({
  required String publicAppKey,
  required String userId,
  required String bazaarRsaPublicKey,
}) async {
  final result = await InappifySdk.configureResult(
    apiKey: publicAppKey,
    appUserIdentifier: userId,
    market: Market.bazar,
    marketKey: bazaarRsaPublicKey,
    country: 'IR',
  );
  return result.isSuccess;
}
```

The `apiKey` parameter retains its public API name. Mobile V2 uses the public app
key as Bearer only for session bootstrap/renewal; it is not a request JSON field.
Authenticated requests use the session's
`sessionToken` as Bearer, managed by the owning SDK. Applications do not construct
or inject session tokens. Market keys are local store configuration.

Use `Market.myket` and Myket's RSA public key for Myket. For Direct mobile payment,
omit `market` and `marketKey`. The verified server session determines the payment
route, so changing a purchase parameter cannot switch stores.

Configure on each app startup for the current user. Android configuration schedules
recovery of pending work and eligible owned store items. See
[store recovery](doc/STORES_AND_RECOVERY.md) for deduplication, subscription renewal
and consumable delivery requirements. Configuration success is not a payment receipt.

## Select an offering and purchase

Use the server's current offering or placement, then pass identifiers from a
package in that offering. For a store purchase, supply the actual configured SKU
type; the catalog's package display type is not a product-type classifier.

```dart
import 'package:inappify_sdk/inappify_sdk.dart';
import 'package:inappify_sdk/models/purchase_result.dart';

Future<InappifySdkResult<PurchaseResult>> buySelectedProduct({
  required String productIdentifier,
  required String offeringIdentifier,
  required String packageIdentifier,
  required String attemptId,
  required InappifyProductType productType,
}) {
  return InappifySdk.purchaseResult(
    productIdentifier: productIdentifier,
    offeringIdentifier: offeringIdentifier,
    packageIdentifier: packageIdentifier,
    productType: productType,
    idempotencyKey: attemptId,
  );
}
```

Create a fresh attempt ID for each deliberate purchase and retain it for a retry of
that same attempt. Check the typed result. A consumable's `DELIVERY_REQUIRED`
requires a durable host grant followed by `confirmDelivery`; it is not a completed
grant. Direct payment can return a URL that the host opens after an allowlist check.
For access, use `checkEntitlementResult`, rather than treating a store return or URL
callback as authoritative.

## Documentation

- [Getting started](doc/GETTING_STARTED.md): configuration, identity and typed results.
- [API reference](doc/API_REFERENCE.md): public methods, models, defaults and limits.
- [Android](doc/ANDROID.md): native bridge and build setup.
- [Stores and recovery](doc/STORES_AND_RECOVERY.md): Bazaar, Myket and durable fulfillment.
- [iOS](doc/IOS.md): V2 Direct session and storage companion.
- [Web](doc/WEB.md): JavaScript prerequisite, Identity Tickets, OTP and browser checkout.
- [Paywalls and targeting](doc/PAYWALLS_AND_TARGETING.md): server selection and UI limitations.
- [Security and cache](doc/SECURITY_AND_CACHE.md): trust, persistence and diagnostics.
- [Releasing](doc/RELEASING.md): validation and publication.

The repository includes automated contract tests and compile/build checks.
Real store purchases, subscription renewals and backend deployment still require
integration testing against your own app and store accounts.

## License

The Flutter SDK is licensed under [Apache-2.0](LICENSE). The Android dependency
includes its own Apache-2.0 license and third-party notices in the Kotlin repository.
