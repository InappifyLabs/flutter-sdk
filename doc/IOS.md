# iOS integration

On iOS, Inappify runs its mobile V2 lifecycle and Direct payment flow in Dart. The Swift plugin supplies application metadata and Keychain persistence through `inappify_sdk`; it does not call the Kotlin SDK or implement an App Store billing client. Bazaar and Myket purchase, inventory and subscription recovery are Android-only.

The Flutter package and mobile behavior version are `0.1.1`. [Android](ANDROID.md) explains the separate Kotlin dependency.

## Application setup

The companion podspec declares iOS 12.0 and Swift 5; this is not a promise that current Flutter runs on iOS 12. Set the application's deployment target to the higher minimum required by Flutter and its dependencies. The example uses iOS 15.0 with Flutter 3.47.1, matching [Flutter's supported deployment platforms](https://docs.flutter.dev/reference/supported-platforms). Flutter installs this companion through CocoaPods; this plugin does not yet ship Swift Package Manager support. The application must supply:

- A nonempty bundle identifier.
- A nonempty `CFBundleShortVersionString`, at most 50 characters.
- A positive integer `CFBundleVersion`; a fractional or nonnumeric build number is rejected.

These values become `identifierValue`, `versionName` and `versionCode` in mobile Configure. The bundle identifier must match the application configured in Inappify.

```dart
import 'package:flutter/widgets.dart';
import 'package:inappify_sdk/inappify_sdk.dart';

Future<bool> initializeIosInappify(String publicAppKey, String userId) async {
  WidgetsFlutterBinding.ensureInitialized();
  final result = await InappifySdk.configureResult(
    apiKey: publicAppKey,
    appUserIdentifier: userId,
    country: 'IR',
  );
  return result.isSuccess;
}
```

Omit `appUserIdentifier` when accepting a retained identity or creating a new anonymous customer. Configure retains a matching saved identity when one exists, otherwise it creates an anonymous identifier; omission is not logout. Select the known application user explicitly when the host account changes. `loginResult` uses the mobile app-user identifier flow; `logoutResult` establishes the server's anonymous session after reconciling the logout. A public key and client-supplied user ID do not replace your application's backend authentication. Web Identity Tickets and OTP belong to the [Web integration](WEB.md).

The `market` / `marketKey` Configure arguments do not provide iOS marketplace support. For Direct purchase, use `Market.none` (the default), and the server session must have `storePlatform == 1`. The Android option `enableSubscriptionRecoveryWithoutPayload` has no effect on iOS and is not added to its Configure HTTP payload or saved options.

## Authentication and mobile endpoints

| Request | Origin | Authentication |
| --- | --- | --- |
| Configure and session renewal | `https://service.inappify.com/app/v2/configure` | Public app key as Bearer |
| Login, logout, CustomerInfo, offerings, attributes and discount validation | `https://service.inappify.com/app/v2/` | Current `sessionToken` as Bearer |
| Signing-key aliases | `https://service.inappify.com/app/v2/public-keys` | GET without Bearer |
| Direct purchases and consumable delivery | `https://api.inappify.com/app/v2/` | Current `sessionToken` as Bearer |

Configure JSON contains `appUserIdentifier`, `identifierValue`, `versionName`, `versionCode`, `sdkVersion` and `country`. The public app key is a bootstrap authentication-header exception; no `apiKey` or separate access token is inserted into mobile request JSON. Later requests use the session returned and verified by Configure. Do not read a token from the Flutter snapshot or assemble these HTTP requests yourself.

The transport uses POST for lifecycle and commerce operations, with the GET exception above. It allows only the known V2 routes, bounds JSON to 1 MiB and does not follow redirects. A specific `401 / SESSION_EXPIRED` can renew the session and replay once; an arbitrary authorization error does not automatically renew or retry a purchase. Retriable lifecycle calls use bounded attempts and server retry floors. Direct purchase and acknowledgement requests do not automatically replay ambiguous network failures.

## Direct purchases

Fetch offerings before purchasing. The requested product must belong to the requested offering; when supplied, `packageIdentifier` must match the package containing that product. The host opens a returned payment URL using its own browser/navigation integration.

```dart
import 'package:inappify_sdk/inappify_sdk.dart';

Future<String?> createIosPayment({
  required String offeringIdentifier,
  required String productIdentifier,
  required String packageIdentifier,
}) async {
  final offerings = await InappifySdk.getOfferingsResult(forceRefresh: true);
  if (!offerings.isSuccess) return null;

  final result = await InappifySdk.purchaseResult(
    offeringIdentifier: offeringIdentifier,
    productIdentifier: productIdentifier,
    packageIdentifier: packageIdentifier,
  );
  if (!result.isSuccess) return null;
  final url = result.data?.url;
  if (url == null) return null;
  final allowed = await InappifySdk.isPaymentUrlAllowed(url);
  return allowed.isSuccess && allowed.data == true ? url : null;
}
```

The Direct request is `POST https://api.inappify.com/app/v2/purchase`. Its JSON contains `productIdentifier`, `offeringIdentifier`, `isCrypto`, and optional paired `paywallId` / `paywallRevision`. The package identifies and validates the cached catalog selection but is not added to this Direct wire payload. The per-attempt `idempotencyKey` is currently local result/failure correlation on iOS; it is not sent in this request and does not promise server deduplication. Keep uncertain outcomes and reconcile them before creating another payment attempt.

Direct purchase returns `PurchaseStatus.NEEDTOPAY` with a URL or `PurchaseStatus.DONE`. Accepted payment URLs use HTTPS, exact host `pay.inappify.com`, no URL credentials, and port 443 or the default HTTPS port. The SDK rejects untrusted purchase and discount-link URLs. Purchase does not navigate automatically.

Per-purchase `apiKey`, `marketKey`, lost-purchase mode, dynamic-price token, country/app-version overrides, nonzero `discount` and `discountCode` are rejected by the iOS Direct flow. Set targeting through Configure / `setTargetingContextResult` before purchasing. Non-default marketplace purchase is rejected. `createCheckout`, `getCheckoutStatus` and `handlePaymentReturnResult` are the Web checkout APIs and are not implemented by the iOS adapter.

After the application's payment-return or foreground callback, use `recover()` and a fresh CustomerInfo request. A return URL or browser closure alone does not prove payment completion.

```dart
import 'package:inappify_sdk/inappify_sdk.dart';

Future<bool> reconcileIosPayment(String entitlementIdentifier) async {
  await InappifySdk.recover();
  final customer = await InappifySdk.getCustomerInfoResult(forceRefresh: true);
  if (!customer.isSuccess) return false;
  final entitlement = await InappifySdk.checkEntitlementResult(
    entitlementIdentifier,
    forceRefresh: false,
  );
  return entitlement.isSuccess && entitlement.data == true;
}
```

## Direct consumables

`syncPendingConsumables()` reads server-authoritative Direct deliveries from `POST /app/v2/consumable-deliveries/pending`. Grant each returned delivery once in durable host inventory, scoped by app, user, source and `deliveryId`. Only after the inventory transaction commits, call `confirmDelivery(deliveryId)`, which sends `POST /app/v2/consumable-deliveries/{deliveryId}/delivered`.

The Dart client saves the `hostDelivered` checkpoint before acknowledgement and can resume a pending acknowledgement during reconciliation. It does not grant your inventory. A failed acknowledgement must never cause a second host grant. Delivery responses must identify the same product, delivery and transaction and must have source `direct`.

`syncPurchases()` reconciles Direct pending deliveries. `restorePurchases()` also reads Direct pending delivery state; its `restoredCount` is zero and it can report already completed deliveries. Neither method queries StoreKit, Bazaar or Myket on iOS. There is no App Store receipt restore or marketplace automatic renewal query in this adapter.

## Persistence and recovery

Swift stores one bounded JSON state document in Keychain service `com.inappify.flutter.mobile.secure-state.v2`, account `goV2`. It is non-synchronizing and uses `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`. Whole-value updates are atomic; read/write failures are returned to Dart instead of silently falling back to preference storage. Configure binds saved state to the app key and bundle identifier, verifies the signed session/customer scope and then reconstructs public snapshots.

Configure loads the Keychain state itself. `restoreCachedSessionResult` is not implemented by this production adapter. A retained usable session can let Configure succeed and schedule background recovery; an expired/invalid session needs the normal verified network renewal path. Recovery resumes pending identity changes, flushes attributes, refreshes CustomerInfo and offerings, and reconciles Direct pending deliveries. Call it after reconnecting or foregrounding as well as at payment return; the package does not install an application lifecycle observer for you.

Cached CustomerInfo may be retained after the signed envelope expires. Entitlement expiration is projected against the trusted time floor learned from signed server data. Choose an explicit offline access policy; a retained snapshot is not a guarantee of fresh server authorization. [Security and cache](SECURITY_AND_CACHE.md) describes fetch policies, signing and diagnostics.

## Implementation references

- [Dart lifecycle and Direct commerce](../lib/src/platform/mobile/go_v2_platform.dart)
- [HTTPS transport, storage and metadata interface](../lib/src/platform/mobile/go_v2_infrastructure.dart)
- [Signed CustomerInfo verification](../lib/src/platform/mobile/go_v2_protocol.dart)
- [Swift metadata and Keychain companion](../ios/Classes/InappifySdkPlugin.swift), [podspec](../ios/inappify_sdk.podspec)
- [Public Flutter facade](../lib/inappify_sdk.dart)
