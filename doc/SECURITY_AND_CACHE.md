# Security, cache and diagnostics

The SDK coordinates one backend owner for the application's Inappify session: the Kotlin SDK on Android, the Dart mobile V2 client plus Swift infrastructure on iOS, or the JavaScript provider on Web. Keep the host's active account aligned with that owner. Public snapshots are projections of backend state; changing compatibility fields in Dart does not change the native/provider session or authenticate a user.

## Credentials and service boundaries

Mobile Configure and renewal send the public app key as `Authorization: Bearer <publicAppKey>` to `https://service.inappify.com/app/v2/configure`. The JSON body contains app/customer metadata, not an API key or old access token. After verification, lifecycle and commerce requests send `Authorization: Bearer <sessionToken>`. The SDK owns renewal. A store's `purchase.token` is separate receipt evidence, never the HTTP session Bearer.

Mobile lifecycle uses `https://service.inappify.com/app/v2/`; commerce uses `https://api.inappify.com/app/v2/`. The public-key alias endpoint is an unauthenticated GET. The Web provider has its own `/api/web/v1` API and Public Web App Key contract. Use the correct platform key, and never embed backend server keys or Identity Ticket issuance secrets in Flutter.

Mobile transport restricts routes, requires HTTPS, disables redirects and bounds JSON to 1 MiB. A specific `401 / SESSION_EXPIRED` permits verified renewal and one replay. Arbitrary 401s and ambiguous payment failures are not a reason to create a new purchase. Ordinary TLS validation protects transport; bundled Ed25519 key pins authenticate application messages and are not certificate pins.

## Signed CustomerInfo

The mobile clients verify `verification.jws` with the pinned Ed25519 trust anchor. Checks include signature, algorithm, envelope type, key ID, issuer, audience, app/project scope, protocol version, customer subject, public app-user identity and validity. The signed CustomerInfo must match the response's CustomerInfo. Ordinary renewal/refresh stays bound to the current subject; a verified identity transition can replace it.

Downloaded `public-keys` entries may add aliases only when their key bytes match an existing trusted key. They cannot create trust in arbitrary response key material. Signature failures are typed failures; do not bypass them or copy an untrusted server key into the client.

This guarantee applies to CustomerInfo and signed scope. It does not sign every offering field, store-platform field, payment URL or commerce reply. Offerings and commerce responses use the HTTPS service plus their schema/workflow guards. On Web, verification, browser credentials and persistence remain the JavaScript provider's responsibility; Flutter does not run the mobile JWS verifier over provider payloads.

## Persistence and identity boundaries

| Platform | Production state owner | Persistence |
| --- | --- | --- |
| Android | Kotlin V2 client | AES-GCM encrypted state in the app's no-backup directory, keys protected by Android Keystore |
| iOS | Dart V2 client / Swift companion | Atomic bounded JSON value in non-synchronizing, device-only Keychain account `goV2` |
| Web | External JavaScript SDK | Provider-owned browser persistence; inspect `snapshot.persistenceMode` |

Android encryption details and journal boundaries are documented in the [Kotlin security guide](https://github.com/InappifyLabs/kotlin-sdk/blob/v0.1.1/docs/SECURITY_AND_DIAGNOSTICS.md). iOS Keychain uses `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`; it does not silently substitute SharedPreferences if Keychain fails. The package's old preference helper is not the production mobile V2 session store. Neither at-rest protection nor browser storage makes a compromised application process trustworthy.

Mobile Configure binds saved state to app configuration and validates the stored signed customer/session scope before exposing it. Pending login/logout state hides the previous public customer until reconciliation. Commerce journals are account/endpoint bound; do not move a checkpoint to another account or clear it to force a second payment. Use Configure for the selected known user, then `loginResult` / `logoutResult` as the application identity changes.

`configureResult` loads matching persisted mobile state and can use a retained usable session while scheduling background recovery. The separate `restoreCachedSessionResult` is unsupported by the shipped production mobile clients and unavailable on Web. On Web, Configure asks the provider to establish/restore its session; authenticated startup uses [the Identity Ticket helper](WEB.md).

## Mobile fetch policies and offline access

Android and iOS expose `customerInfoWithPolicy` and `offeringsWithPolicy`:

| Policy | Behavior |
| --- | --- |
| `cacheOnly` | Return retained data; fail on cache miss without joining a network request |
| `cacheFirst` | Return retained data when available and allow a background refresh; otherwise request network |
| `networkFirst` | Try network, then retained same-customer cache if available |
| `networkOnly` | Require the network result |

`getCustomerInfoResult(forceRefresh: false)` and `getOfferingsResult(forceRefresh: false)` use `cacheFirst`; `true` uses `networkOnly`. There is no fixed five-minute freshness guarantee in these production mobile implementations. Concurrent compatible network requests can share work; a cache-only caller does not become a network caller merely because another request is in flight.

```dart
import 'package:inappify_sdk/inappify_sdk.dart';

Future<bool> readCachedEntitlement(String identifier) async {
  final customer = await InappifySdk.customerInfoWithPolicy(
    InappifyFetchPolicy.cacheOnly,
  );
  if (!customer.isSuccess) return false;
  return customer.data?.entitlements?.any(
        (entitlement) => entitlement.identifier == identifier &&
            entitlement.isActive == true,
      ) ??
      false;
}
```

Stored CustomerInfo remains signature/scope checked, but the clients may retain an expired signed envelope for offline use. Entitlement expiry is checked against a trusted time floor learned from signed request dates. Define the application's offline access policy explicitly; cache is not proof of current server authorization or a newly completed purchase. Read-only snapshots and returned model instances do not replace an authoritative refresh when freshness matters.

Call mobile `recover()` when foregrounding, reconnecting or returning from a Direct checkout. Android also reconciles selected marketplace inventory after Configure; iOS reconciles Direct delivery state and does not query stores. The Flutter package does not install a foreground observer for your application. `setNetworkEnabled(false)` prevents subsequent mobile SDK/commerce network use while preserving state; it is not a device firewall or marketplace disconnect API. Web uses its own session and checkout methods instead.

## Attributes and targeting

Mobile V2 attributes are write-only. Their values are removed from public verified CustomerInfo rather than exposed as readback. `queueAttributes` persists validated writes, and `flushAttributes` synchronizes them with the current session. Null or empty values request deletion; whitespace is a value. Invalid names/values fail rather than being silently accepted. Pending/rejected values may remain in account-bound recovery state.

Synchronize attributes and targeting context before fetching the targeted offering. Mobile `getCurrentOffering` resolves the server's placement selection, then `currentOffering`, then a default offering; it does not reevaluate old local rules. A cached offering can reflect older attributes/context. The Web adapter delegates selection and attribute operations to its provider.

Do not use attributes as storage for sessions, receipts, passwords or backend secrets. Treat identifiers, customer data and business events as sensitive even when they contain no credential.

## Uncertain purchase outcomes and durable delivery

A successful native store callback is receipt evidence. Payment/entitlement/delivery state becomes authoritative through the service workflow, not a local grant triggered by that callback or a redirect query string.

Prefer typed `*Result` methods and inspect `failure.code`, `isRetryable`, `details` and the returned snapshot. If `details['outcomeMayHaveCommitted'] == true`, retain correlation and use recovery/status/synchronization before starting another payment. Cancellation of a caller does not prove that a store payment or server mutation did not commit.

For mobile consumables, `syncPendingConsumables()` returns server-authoritative deliveries. The application must grant each delivery exactly once in durable inventory, with a uniqueness key bound to app/customer/source/delivery ID. Call `confirmDelivery` only after that transaction commits. A failed acknowledgement must not cause a second grant. The Flutter facade does not expose the native automatic delivery-handler registration API; applications use this manual durable fulfillment contract.

On iOS Direct purchase, the attempt identifier is local correlation and is not in the wire request; do not assume it provides server idempotency. Web checkout has its own provider-backed idempotency key and authoritative status query. [Android](ANDROID.md), [iOS](IOS.md) and [Web](WEB.md) document their distinct payment/recovery surfaces.

## Events and errors

`InappifySdk.events` exposes customer, offerings, authentication, purchase and supported lifecycle changes. Event snapshots update the process mirror; use operation results for the directly requested outcome. Native channels validate protocol version and correlation IDs. The channel protocol version `1` is an internal bridge envelope and does not mean a mobile V1 HTTP endpoint.

`sessionStateChanges` projects Web lifecycle events as `InappifySessionStateChange`, without tokens. A temporary failure preserves the last authoritative user mirror; `temporarilyUnavailable` is not logout. Malformed provider events are ignored without logging raw payloads. Web bridge errors retain stable code/status/request ID/name/kind; arbitrary JS error details do not cross into shared Flutter errors.

Compatibility methods return `false` or `null` on failure and update process-wide `lastFailure`. Concurrent operations can overwrite this shared field; typed result failures belong to their own operation. Error categories include configuration/auth/network/timeout/storage/store availability/cancellation/protocol/decoding and unsupported operation. Retry only where the operation's workflow and server state allow it; `isRetryable` is not permission to repeat a host inventory grant.

## Opt-in HTTP diagnostics

Subscribe before Configure to observe filtered mobile Inappify traffic. HTTP logging is not enabled merely because the host is a debug build:

```dart
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:inappify_sdk/inappify_sdk.dart';

StreamSubscription<InappifyHttpTrace> observeMobileHttp() {
  return InappifySdk.httpTraces.listen((trace) {
    debugPrint(
      '${trace.method} ${trace.endpoint} '
      'status=${trace.statusCode} durationMs=${trace.durationMillis} '
      'failure=${trace.failure}',
    );
  });
}
```

Cancel the returned subscription when diagnostics are no longer needed. A trace contains endpoint/method, filtered headers/bodies, status, request ID when supplied, duration and failure. Android forwards native filtered traces over its diagnostic EventChannel; iOS forwards filtered Dart transport traces. They redact Bearer/API/receipt credentials, signatures, customer/attribute identifiers and untrusted strings; malformed/oversize payloads are not a complete wire dump. Dart rejects traces marked `containsSensitiveData: true`.

Body filtering is intentionally aggressive, so metadata is usually the useful evidence. Review any explicit `requestBody`/`responseBody` export; sanitized does not make all business data suitable for unrestricted logs. A store inventory query or native purchase UI produces no Inappify HTTP trace itself. Diagnostics are asynchronous and may arrive after an operation's result; correlate request IDs instead of assuming console ordering.

Web does not emit mobile HTTP traces. Use its typed checkout/customer results, lifecycle events and provider-compatible browser diagnostics without exposing tokens or one-time tickets. The published release Kotlin dependency does not include its unsafe debug-only factory; making a Flutter APK debuggable cannot enable raw native wire logging.

## Implementation references

- [Session coordinator and event mirroring](../lib/src/application/inappify_coordinator.dart), [public facade](../lib/inappify_sdk.dart)
- [Channel validation](../lib/src/platform/channel/channel_codec.dart), [failure categories](../lib/src/platform/contracts/sdk_failure.dart)
- [iOS protocol/signing](../lib/src/platform/mobile/go_v2_protocol.dart), [iOS transport/filtering](../lib/src/platform/mobile/go_v2_infrastructure.dart)
- [Swift Keychain](../ios/Classes/InappifySdkPlugin.swift), [Web state/error handling](../lib/src/platform/web/web_inappify_platform.dart)
