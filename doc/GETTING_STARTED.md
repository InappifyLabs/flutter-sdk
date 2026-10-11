# Getting started

## Install and choose the platform

The package keeps its import name `inappify_sdk`. Add the package dependency:

```yaml
dependencies:
  inappify_sdk: ^0.1.0
```

The declared tool minimum is Flutter 3.44.0 / Dart 3.12.0. Android requires JDK 17.
The plugin declares native Android minSdk 21 and an iOS podspec minimum of 12.0;
your chosen Flutter version and other dependencies can require higher deployment
versions. The example and CI use Flutter 3.47.1, whose supported deployment minimums
are Android API 24 and iOS 15.0; see [Flutter's supported platforms](https://docs.flutter.dev/reference/supported-platforms).
Android and iOS are mobile V2 clients. Web requires a compatible JavaScript SDK
before configuration.

| Integration | Setup guide |
| --- | --- |
| Android Direct/Bazaar/Myket | [Android](ANDROID.md) and [stores/recovery](STORES_AND_RECOVERY.md) |
| iOS Direct | [iOS](IOS.md) |
| Browser/PWA | [Web](WEB.md) |

After adding the plugin, run `flutter pub get` and perform a full app rebuild.
A hot reload cannot install the Android plugin or replace its native dependency.

## Configure once for the current identity

Initialize Flutter bindings before invoking platform methods. This complete
mobile helper returns a typed configuration result; the host supplies real keys
and a stable account identifier. On a first launch, omitting `userId` creates an
anonymous mobile customer. On later launches, omission can retain the persisted
identity, including a logged-in user; use logout explicitly when the host signs out.

```dart
import 'package:flutter/widgets.dart';
import 'package:inappify_sdk/inappify_sdk.dart';
import 'package:inappify_sdk/models/enums/market.dart';

Future<InappifySdkResult<void>> startMobileSession({
  required String publicAppKey,
  String? userId,
  Market? store,
  String? storeRsaPublicKey,
}) async {
  WidgetsFlutterBinding.ensureInitialized();
  return InappifySdk.configureResult(
    apiKey: publicAppKey,
    appUserIdentifier: userId,
    market: store,
    marketKey: storeRsaPublicKey,
    country: 'IR',
    enableSubscriptionRecoveryWithoutPayload: true,
  );
}
```

Use `store: Market.bazar` or `Market.myket` only on Android, with that store's RSA
public key. iOS uses Direct and has no Bazaar/Myket route. The server returns the
mobile store platform for the verified session; local market configuration must
match it. For Web, configure with a Public Web App Key and authenticate through a
fresh Identity Ticket or OTP instead of `appUserIdentifier`.

`apiKey` is the public API parameter name for the app's public bootstrap key.
Configure and session renewal use it as `Authorization: Bearer <publicAppKey>`;
it is not inserted into request JSON. The mobile V2 clients persist and
renew their own `sessionToken`, then use Bearer authentication for resource and
commerce calls. The application does not set `accessToekn`, provide a Bearer header
or pass an app key again in a purchase request.

`country` defaults to `IR`. An explicit country must be a valid two-letter code;
an explicit `appVersion` must be nonblank and at most 50 characters. When omitted,
the mobile backend reads the host version from platform metadata. This value is
your app's version, not the Inappify SDK version.

`mobileProtocol` has one supported value, `InappifyMobileProtocol.goV2`, and it is
the default. `configureGoV2` is a convenience alias for configuring that mobile
protocol; it does not accept market options. Use `configureResult` for a store.
Concurrent identical configuration calls share one operation; lifecycle
operations are serialized and the configured backend owns the session.

`enableSubscriptionRecoveryWithoutPayload` defaults to true and affects only
Android Bazaar subscriptions. It requires the server's subscription recovery
endpoint. Setting false preserves pending checkpoints while disabling discovery,
submission and polling for this specific recovery path. It is ignored on iOS/Web.

## Handle typed results

Every `*Result` method returns `InappifySdkResult<T>`. `isSuccess` means no semantic
failure; `data` can be null, including a successful current-offering query with
no selected offering. `snapshot` contains the latest backend state when supplied.

```dart
import 'package:inappify_sdk/inappify_sdk.dart';

Future<bool> refreshPremiumAccess() async {
  final result = await InappifySdk.checkEntitlementResult(
    'premium',
    forceRefresh: true,
  );
  if (!result.isSuccess) {
    return false;
  }
  return result.data == true;
}
```

Handle failure according to `failure.code`, `isRetryable` and sanitized details.
In particular, an unsuccessful or ambiguous payment must not trigger a new
purchase automatically. Preserve the attempt and use recovery. A successful
cached read does not prove a new charge finished.

The compatibility methods remain available: `configure`/`login`/setters return
bool; `purchase`, customer and offering getters return their data or null on
failure. Prefer typed results when you need to distinguish a failure from a
successful null result. `lastFailure` is process-wide and can be overwritten by
another operation, so it should not determine concurrent purchase handling.

## Account changes

Mobile applications use their existing public account identifier consistently.
Do not generate a new identifier on every launch or use credentials/email as the
identifier. Login and logout are explicit lifecycle operations:

```dart
import 'package:inappify_sdk/inappify_sdk.dart';

Future<InappifySdkResult<void>> switchMobileAccount({
  required String publicAppKey,
  required String userId,
}) => InappifySdk.loginResult(
  apiKey: publicAppKey,
  appUserIdentifier: userId,
);

Future<InappifySdkResult<void>> leaveMobileAccount() =>
    InappifySdk.logoutResult();
```

Use the configured app's key for mobile login. The backend invalidates stale
customer/offering state across identity changes. An incomplete transition can
require recovery; do not restore access from a saved previous-user mirror.
Anonymous identifiers and persistence are SDK-owned. `isCustomerAnonymous` is a
string helper, not authentication proof; use the authoritative result/snapshot.
Web's stable-ID `login` is unsupported: use the browser authentication flow in
[Web](WEB.md).

## Catalog and purchases

Fetch `getCurrentOfferingResult(placementIdentifier: ..., forceRefresh: true)` to
refresh the server's targeting decision. Each `OfferingModel` can contain
`PackageModel` entries, whose `product.identifier` is the SKU and `identifier` is
the Inappify package identifier. The package identifier is not the Android package
name. See [paywalls and targeting](PAYWALLS_AND_TARGETING.md) for a complete selection
example and [API reference](API_REFERENCE.md) for supported purchase fields.

Keep one active host purchase workflow. Use the product classification you
configured for that SKU; `packageType` is not a substitute. Bazaar supports
subscription/in-app queries; Myket supports in-app purchases only. A new store
purchase requires the app's foreground Android Activity; the plugin supplies it
through the standard Flutter Activity attachment.

On app startup, Android `configureResult` schedules native recovery. You can also
call `recover`, `syncPurchases` and explicit `restorePurchases`; do not build a
second Flutter billing inventory loop. The native SDK protects the receipt,
account binding and durable journal. Consumables still require durable host
fulfillment and acknowledgement, described in [stores/recovery](STORES_AND_RECOVERY.md).

## Observe updates and cache

`InappifySdk.events` emits backend updates, including snapshots when supplied.
The static `customerInfo`, `offerings` and `snapshot` getters mirror the latest
backend state. Dispose stream subscriptions when the observing UI/service ends.
The configured session's `sdkVersion` is available through both snapshot and the
static getter; Android reports native `0.1.0`, iOS reports the Dart client
version, and Web reports its JavaScript backend version.

Mobile cached session loading happens inside `configureResult`. The separately
exposed `restoreCachedSessionResult` is currently unsupported by production
Android/iOS and unavailable on Web; do not use it as the startup path. Explicit
resource policies are available through `customerInfoWithPolicy` and
`offeringsWithPolicy`. Read [security/cache](SECURITY_AND_CACHE.md) before choosing
an offline access policy.
