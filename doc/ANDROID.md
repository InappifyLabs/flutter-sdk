# Android integration

On Android, Flutter calls the published Kotlin SDK through `MethodChannel`. The native client owns configuration, the session token, signature checks, encrypted cache, store billing, verification, and recovery. Dart mirrors token-free customer/offering/workflow state; it does not perform a second Bazaar/Myket purchase or inventory synchronization.

The plugin uses this exact dependency:

```kotlin
implementation("com.github.InappifyLabs:kotlin-sdk:v0.1.0")
```

Its runtime SDK version is `0.1.0`; `v` is the Git tag prefix and is not sent as the SDK version. Do not add the old Android artifact alongside this dependency. The native package names remain `com.inappify.sdk`, and the Flutter plugin namespace remains `com.inappify.inappify_sdk`.

## Build requirements and repositories

The package requires Flutter 3.44/Dart 3.12 or newer, JDK 17 for compilation, and Android SDK platform 37. The native library minimum is API 21; use the higher Android deployment minimum required by your Flutter version and dependencies (API 24 for the example using Flutter 3.47.1). Its Android build declares Gradle 9.3.1, Android Gradle Plugin 9.1.1, and Kotlin 2.4.0. The plugin uses `kotlin.compilerOptions` and does not explicitly apply `kotlin-android`, following Flutter's built-in Kotlin plugin migration. Built-in Kotlin enabled in an AGP 9 host requires Flutter 3.47 or newer; Flutter 3.44–3.46 hosts must keep `android.builtInKotlin=false` with supported Kotlin plugin configuration. A Flutter application's own Gradle settings/wrapper govern its application build; keep those tools compatible with each other and with the Flutter SDK used by the host. See [Flutter's official migration guide](https://docs.flutter.dev/release/breaking-changes/migrate-to-built-in-kotlin/for-plugin-authors).

The native SDK and Poolakey are downloaded from JitPack. Add JitPack to the **host application's** Android dependency repositories (normally `android/build.gradle(.kts)` or centralized `settings.gradle(.kts)`). The plugin's own repository declaration does not propagate to the app's runtime dependency resolution. Keep Google Maven and Maven Central as well. A repository policy that rejects the plugin's project repository declarations must be adjusted by the host. Set the host app's `compileSdk` to at least 37; its Flutter default can be lower.

```kotlin
// Add this repository in the host's existing Android repository configuration.
maven { url = uri("https://jitpack.io") }
```

Use [the installation guide](GETTING_STARTED.md) for the Flutter package dependency. The native SDK includes Poolakey and a namespaced Myket billing implementation; the host does not need another billing plugin, manually copied AIDL classes, or store-specific SDK flavors.

## Configure after resolving the application account

Call configuration once per application startup after determining the current account. Await its typed result before showing account-specific purchasing UI.

```dart
import 'package:inappify_sdk/inappify_sdk.dart';
import 'package:inappify_sdk/models/enums/market.dart';

Future<InappifySdkResult<void>> configureAndroidBazaar({
  required String inappifyApiKey,
  required String appUserId,
  required String bazaarPublicBillingKey,
}) {
  return InappifySdk.configureResult(
    apiKey: inappifyApiKey,
    appUserIdentifier: appUserId,
    market: Market.bazar,
    marketKey: bazaarPublicBillingKey,
    enableSubscriptionRecoveryWithoutPayload: true,
  );
}
```

`apiKey` initializes or renews the native session. Store/commerce requests authenticate with `Authorization: Bearer <current sessionToken>`; the API key and a legacy customer token are not sent in commerce bodies. `marketKey` is the store application's public RSA billing key, not a private key or session token. The server session's `storePlatform` determines the actual purchase route, and its store metadata may supply the public billing key.

Omitting `appUserIdentifier` can reuse the persisted native identity, including a signed-in customer. It is not an instruction to log out. Resolve your own application's identity before configuration, and use explicit login/logout for account transitions. Pending native paid operations remain bound to their original app/customer/store context.

Configuration can reuse a matching verified native cache and schedules recovery in the background. A successful configure result does not mean that all recovery or purchase verification has completed. The plugin does not create a periodic worker or automatically invoke recovery on every app resume. Call `InappifySdk.recover()` from your host lifecycle when foregrounding or restoring connectivity; see [store recovery](STORES_AND_RECOVERY.md).

`restoreCachedSessionResult` remains a source-compatible optional API, but the production Android V2 client does not implement explicit cache restoration. Android does not advertise that capability and returns `unsupportedOperation`. Use `configureResult` and the supported fetch policies instead. There is no silent Dart/network fallback for this optional method.

## Foreground purchase UI

For Bazaar/Myket, use `FlutterFragmentActivity` as your host activity. Native billing requires both AndroidX `ActivityResultRegistryOwner` and `LifecycleOwner`; the ordinary `FlutterActivity` does not supply the required activity-result registry. Update your application's existing `MainActivity.kt`, preserving its package and other host integrations:

```kotlin
package com.example.app

import io.flutter.embedding.android.FlutterFragmentActivity

class MainActivity : FlutterFragmentActivity()
```

Use a currently attached, foreground activity. The plugin implements `ActivityAware`, passes the current activity to native purchase, and clears it on detach/configuration changes. Native store UI performs its own activity/state validation; an unsupported host yields `UI_HOST_NOT_SUPPORTED`. Background engines or an engine without a foreground activity cannot safely launch a store checkout.

The plugin holds one native session shared by attached Flutter engines and serializes semantic operations. A concurrent purchase is rejected with a retryable failure carrying `nativeCode: PURCHASE_IN_PROGRESS`. Engine detach removes that engine's event listeners; the native client closes when the final owner detaches. Neither detach nor configuration changes implicitly logs the user out or deletes persisted journals.

A canceled Flutter waiter is not proof that a paid store attempt was canceled. On an uncertain result, retain the original purchase correlation/idempotency key and reconcile native pending work before allowing another payment.

## Manifest merging

The plugin's own manifest declares `INTERNET` and preserves its existing `READ_EXTERNAL_STORAGE`/`WRITE_EXTERNAL_STORAGE` declarations. The bridge does not request storage permissions at runtime or access host files. Native cache/journal storage is private to the application.

The native SDK and Poolakey supply the store entries through manifest merging:

| Store | Required merged entries |
| --- | --- |
| Bazaar | `com.farsitel.bazaar.permission.PAY_THROUGH_BAZAAR`, package query `com.farsitel.bazaar`, Poolakey billing receiver |
| Myket | `ir.mservices.market.BILLING`, package query `ir.mservices.market`, service query `ir.mservices.market.InAppBillingService.BIND`, namespaced billing receiver and proxy activity |

Both stores' entries can coexist in one APK. These billing permissions are manifest declarations, not runtime permission dialogs. The SDK has no required host manifest placeholder. Keep manifest merging enabled and check the final application's merged manifest if the selected store cannot be discovered or opened. Store installation/account, registered application package, product SKU, and signing identity must match the store setup.

## Channel and capability contract

Applications should use `InappifySdk` rather than invoking channel methods directly. The transport uses `inappify_sdk`, structured envelopes with a protocol number and request ID, and structured results with `ok`, `data`, `snapshot`, and sanitized failure metadata. Channel protocol version `1` and the event channel suffix `/v1` describe the local Flutter transport; they are not HTTP V1 routes. The network client uses `/app/v2/`.

The handshake selects one backend for the whole session. Android supports the following native operation groups:

| Dart operation | Native action |
| --- | --- |
| `configureResult`, `loginResult`, `logoutResult` | V2 session configuration and identity transitions |
| `purchaseResult` | Native server-selected checkout/store billing and durable verification |
| `getCustomerInfoResult`, `getOfferingsResult` | Native cached/network resource fetches |
| `customerInfoWithPolicy`, `offeringsWithPolicy` | Native `cacheOnly`, `cacheFirst`, `networkFirst`, or `networkOnly` fetch |
| `setTargetingContextResult`, `getCurrentOfferingResult`, `checkEntitlementResult` | Native context update, server-selected offering projection, verified entitlement lookup |
| Attribute methods, `queueAttributes`, `flushAttributes` | Native write queue and synchronization |
| `syncPurchases`, `restorePurchases`, `recover` | Native owned inventory and paid-operation reconciliation |
| `syncPendingConsumables`, `confirmDelivery` | Verified delivery queue, durable host acknowledgement, consumption/reporting |
| `setNetworkEnabled`, `isPaymentUrlAllowed`, `getConfiguration` | Native network gate, checkout URL allowlist, token-free configuration |

Identity Ticket/OTP, `createCheckout`, checkout polling, and browser payment-return methods are not available through this Android bridge. The existing native direct purchase flow can return a server checkout URL, which the host navigates to; do not substitute unsupported browser APIs for Android purchase.

Customer/offerings/authentication events are forwarded on `inappify_sdk/events/v1`. Opt-in filtered HTTP diagnostics are forwarded on `inappify_sdk/http/v2` while listened to. The codec does not expose the native session token to Dart and rejects raw sensitive diagnostics. See [security and diagnostics](SECURITY_AND_CACHE.md) for logging and failure handling.

## Source and validation references

- [Native session ownership](../android/src/main/kotlin/com/inappify/inappify_sdk/InappifyClientHolder.kt), [Activity/channel lifecycle](../android/src/main/kotlin/com/inappify/inappify_sdk/InappifySdkPlugin.kt).
- [Native delegation and strict payload parsing](../android/src/main/kotlin/com/inappify/inappify_sdk/InappifyNativeBridge.kt), [channel capabilities](../android/src/main/kotlin/com/inappify/inappify_sdk/InappifyChannelContract.kt), [result/event encoding](../android/src/main/kotlin/com/inappify/inappify_sdk/InappifyNativeCodec.kt).
- [Published Kotlin SDK](https://github.com/InappifyLabs/kotlin-sdk/tree/v0.1.0), [native store integration](https://github.com/InappifyLabs/kotlin-sdk/blob/v0.1.0/docs/STORES.md).

Automated tests validate delegation, payload types, identity/session ownership, correlation IDs, capability behavior, and result encoding. Android build checks validate the actual public native artifact. These checks do not certify a live purchase, renewal, backend deployment, or device lifecycle.
