# iOS integration

On iOS, Inappify runs its mobile V2 lifecycle and Direct payment flow in Dart. The Swift plugin supplies application metadata and Keychain persistence through `inappify_sdk`; it does not call the Kotlin SDK or implement an App Store billing client. Bazaar and Myket purchase, inventory and subscription recovery are Android-only.

The Flutter package and mobile behavior version are `0.2.2`. [Android](ANDROID.md) explains the separate Kotlin dependency.

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
  );
  return result.isSuccess;
}
```

Omit `appUserIdentifier` when accepting a retained identity or creating a new anonymous customer. Configure retains a matching saved identity when one exists, otherwise it creates an anonymous identifier; omission is not logout. Select the known application user explicitly when the host account changes. `loginResult` uses the mobile app-user identifier flow; `logoutResult` establishes the server's anonymous session after reconciling the logout. A public key and client-supplied user ID do not replace your application's backend authentication. Web Identity Tickets and OTP belong to the [Web integration](WEB.md).

Configure takes only the app key and optional user ID. The Direct session must have storePlatform == 1; Android-specific store settings are not public inputs.

## Authentication and mobile endpoints

| Request | Origin | Authentication |
| --- | --- | --- |
| Configure and session renewal | `https://service.inappify.com/app/v2/configure` | Public app key as Bearer |
| Login, logout, CustomerInfo, offerings, attributes and discount validation | `https://service.inappify.com/app/v2/` | Current `sessionToken` as Bearer |
| Signing-key aliases | `https://service.inappify.com/app/v2/public-keys` | GET without Bearer |
| Direct purchases and consumable delivery | `https://api.inappify.com/app/v2/` | Current `sessionToken` as Bearer |

Configure JSON contains `appUserIdentifier`, `identifierValue`, `versionName`, `versionCode`, `sdkVersion` and `country`. The public app key is a bootstrap authentication-header exception; no `apiKey` or separate access token is inserted into mobile request JSON. Later requests use the session returned and verified by Configure. Do not read a token from the Flutter snapshot or assemble these HTTP requests yourself.

The transport uses POST for lifecycle and commerce operations, with the GET exception above. It allows only the known V2 routes, bounds JSON to 1 MiB and does not follow redirects. A specific `401 / SESSION_EXPIRED` can renew the session and replay once; an arbitrary authorization error does not automatically renew or retry a purchase. Retriable lifecycle calls use bounded attempts and server retry floors. Direct purchase and acknowledgement requests do not automatically replay ambiguous network failures.

## Synchronizing attributes and offerings

```dart
final result = await InappifySdk.syncAttributesAndOfferingsIfNeeded();
if (result.isSuccess) {
  final current = result.data?.current;
  final upgrade = result.data?.getCurrentOfferingForPlacement('upgrade');
}
```

On iOS this operation uses the existing Dart Go V2 execution queue. It sends pending custom and reserved attributes first, then fetches fresh offerings even when the attribute queue is empty. The fetched model is saved through the existing storage/snapshot path and publishes a state-change event. Attribute or offerings failures return structured errors; pending attributes and quarantined validation failures follow the existing queue rules.

Each client admits at most five executions in a rolling 60-second window, matching Android. Failed admitted executions also count; Configure, login and logout do not reset this quota. Calls above the limit make no network requests and return the current session's cached offerings. Without that cache they return a retryable failure with `category: RATE_LIMIT`, `reason: RATE_LIMITED_NO_CACHE` and `retryAfterMillis` in `failure.details`. A previous customer's cache is never returned for a new or pending session. This quota uses elapsed time rather than the device's calendar clock.

## Direct purchases

Fetch offerings before purchasing. The requested product must belong to the requested offering; when supplied, `packageIdentifier` must match the package containing that product. The host opens a returned payment URL using its own browser/navigation integration.

```dart
import 'package:inappify_sdk/inappify_sdk.dart';

Future<String?> createIosPayment(PackageModel selectedPackage) async {
  final result = await InappifySdk.purchaseResult(
    InappifyPurchaseParams(packageToPurchase: selectedPackage));
  if (!result.isSuccess) return null;
  final url = result.data?.url;
  if (url == null) return null;
  final allowed = await InappifySdk.isPaymentUrlAllowed(url);
  return allowed.isSuccess && allowed.data == true ? url : null;
}
```

The Direct request is `POST https://api.inappify.com/app/v2/purchase`. Its JSON contains `productIdentifier`, `offeringIdentifier`, `isCrypto`, and optional paired `paywallId` / `paywallRevision`. The package identifies and validates the cached catalog selection but is not added to this Direct wire payload. The per-attempt `idempotencyKey` is currently local result/failure correlation on iOS; it is not sent in this request and does not promise server deduplication. Keep uncertain outcomes and reconcile them before creating another payment attempt.

Direct purchase returns `PurchaseStatus.NEEDTOPAY` with a URL or `PurchaseStatus.DONE`. Accepted payment URLs use HTTPS, exact host `pay.inappify.com`, no URL credentials, and port 443 or the default HTTPS port. The SDK rejects untrusted purchase and discount-link URLs. Purchase does not navigate automatically.

Per-purchase `apiKey`, `marketKey`, lost-purchase mode, dynamic-price token, country/app-version overrides, nonzero `discount` and `discountCode` are rejected by the iOS Direct flow. Public purchase inputs now come from Package; manual targeting context is not exposed. Non-default marketplace purchase is rejected. `createCheckout`, `getCheckoutStatus` and `handlePaymentReturnResult` are the Web checkout APIs and are not implemented by the iOS adapter.

After the application's payment-return or foreground callback, request fresh CustomerInfo and use `syncPendingConsumables()` when a manual Direct delivery check is needed. Internal startup recovery remains enabled; the iOS adapter does not install Android's foreground/connectivity observers. A return URL or browser closure alone does not prove payment completion.

```dart
import 'package:inappify_sdk/inappify_sdk.dart';

Future<bool> reconcileIosPayment(String entitlementIdentifier) async {
  await InappifySdk.syncPendingConsumables();
  final customer = await InappifySdk.getCustomerInfoResult(fetchPolicy: InappifyCacheFetchPolicy.fetchCurrent);
  if (!customer.isSuccess) return false;
  return customer.data?.entitlements.active.containsKey(entitlementIdentifier) == true;
}
```

## Direct consumables

`syncPendingConsumables()` reads server-authoritative Direct deliveries from `POST /app/v2/consumable-deliveries/pending`. Grant each returned delivery once in durable host inventory, scoped by app, user, source and `deliveryId`. Only after the inventory transaction commits, call `confirmDelivery(deliveryId)`, which sends `POST /app/v2/consumable-deliveries/{deliveryId}/delivered`.

The Dart client saves the `hostDelivered` checkpoint before acknowledgement and can resume a pending acknowledgement during reconciliation. It does not grant your inventory. A failed acknowledgement must never cause a second host grant. Delivery responses must identify the same product, delivery and transaction and must have source `direct`.

`syncStorePurchases()` reconciles Direct pending deliveries. `restoreStorePurchases()` also reads Direct pending delivery state; its `restoredCount` is zero and it can report already completed deliveries. Neither method queries StoreKit, Bazaar or Myket on iOS. There is no App Store receipt restore or marketplace automatic renewal query in this adapter.

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

The 0.2.2 facade keeps the Dart Direct pipeline and persisted state unchanged.
Automatic consumable handler registration is unsupported on this iOS backend.
Use manual delivery/recovery where supported; Android lifecycle observers are
owned by Kotlin. Combined attribute/offerings sync is supported on both backends
with the same per-client quota.
