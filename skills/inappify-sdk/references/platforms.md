# Verified versions and platform support

## Release baseline

This release uses Flutter **0.2.4** with Kotlin **v0.2.3** and unchanged Web
provider **0.2.0**. The new native release adds server-authoritative Myket product
types and recovery of older receipts after confirmed fulfillment. Deploy the
matching commerce backend before upgrading clients. Inspect the host's resolved
dependency before applying the new recovery contract.

| Component | Version | Tagged source |
| --- | --- | --- |
| Flutter `inappify_sdk` | 0.2.4 | [flutter-sdk v0.2.4](https://github.com/InappifyLabs/flutter-sdk/tree/v0.2.4) |
| Android Kotlin dependency | v0.2.3 | [kotlin-sdk v0.2.3](https://github.com/InappifyLabs/kotlin-sdk/tree/v0.2.3), commit `e75d40a0b7b5b8664a08888ca473a585a2977888` |
| Browser provider `@inappifylabs/web-sdk` | 0.2.0 | [web-sdk v0.2.0](https://github.com/InappifyLabs/web-sdk/tree/v0.2.0), commit `1b59a018679be6f717feca7cc6f1ea27198f233f` |

This is a fixed compatibility baseline, not a claim to track the latest release.
Inspect resolved locks before applying it. Flutter does not bundle npm for Web;
the host must bundle/load its provider before Flutter starts. Do not substitute
an older beta merely because some repository Web prose still names it.

## Session ownership

| Target | Session owner | Payments and persistence |
| --- | --- | --- |
| Flutter Android | Kotlin through MethodChannel | Server-selected Direct, Bazaar or Myket; native encrypted session/cache/paid-operation journal |
| Flutter iOS | Dart `GoV2Platform`, Swift metadata/Keychain companion | Direct only; verified mobile state persisted in Keychain; no StoreKit |
| Flutter Web | One external JS provider through `WebInappifyPlatform` | Web checkout; JS owns credentials/IndexedDB; Flutter mirrors snapshots |
| Direct JavaScript | Instance returned by `InAppify.configure` | Independent Web API and its own public JS types |

Flutter static methods share one owner. Do not configure another instance to work
around platform support. The native HTTP V2 contract and Web `/api/web/v1`
contract are different; a local channel protocol version does not select HTTP V1.

## Flutter 0.2.4 support (unchanged public APIs)

"Unsupported" means do not build an integration around that operation on this
backend, even if a Dart signature or a newer JS method exists.

| Feature | Android | iOS | Flutter Web + JS 0.2.0 |
| --- | --- | --- | --- |
| `configureResult(apiKey:, appUserIdentifier:)` | Yes | Yes | Public Web key; stable authenticated user ID is rejected |
| `logInResult(String)` | Yes | Yes | Unsupported; use ticket/OTP |
| `logOutResult()` | Yes | Yes | Yes, provider replaces identity with anonymous session |
| Ticket / OTP / authenticated-Web startup helper | Unsupported | Unsupported | Yes |
| Offerings, placement, exact identifier lookup | Yes | Yes; exact lookup uses catalog helper | Yes; exact lookup uses catalog helper |
| `syncAttributesAndOfferingsIfNeeded()` | Yes, 5/60 s | Yes, 5/60 s | Yes, provider-owned 5/60 s; method capability checked |
| `getCustomerInfoResult(fetchPolicy:)` | Four policies | Four policies | Four policies forwarded explicitly; default `CACHED_OR_FETCHED` |
| Attributes + reserved attributes | Native queue | Dart durable queue | Immediate JS/server writes; Web allowlists apply |
| `purchaseResult(Package)` | Direct/Bazaar/Myket | Direct only | Web checkout projected to `PurchaseResult`; no automatic redirect |
| `getDiscountedPaymentLinksResult(code, offeringIdentifier:)` | Code-only links; selector unused | Code-only links; selector unused | Explicit selected offering pricing, or current offering when omitted |
| Durable attempt history + `purchaseUpdates` outcomes | Yes | Unsupported | Unsupported |
| `syncStorePurchases()` / `restoreStorePurchases()` | Owned inventory / explicit eligible store restore; Direct delivery reconciliation | Direct deliveries only; no store restore | Unsupported |
| `syncPendingConsumables()` / `confirmDelivery(id)` | Yes | Manual Direct flow | **Unsupported in Flutter**; direct JS has its own APIs |
| `setConsumableDeliveryHandler(handler)` | Yes | Unsupported; use manual flow | Unsupported in Flutter |
| `handleDeepLink(url)` | Marked native payment returns | Unsupported | Unsupported; use checkout-return methods |
| `createCheckout`, `getCheckoutStatus`, `handlePaymentReturnResult` | Unsupported | Unsupported | Yes |
| `customerInfoWithPolicy`, `offeringsWithPolicy`, `setNetworkEnabled`, `isPaymentUrlAllowed` | Yes | Yes | Unsupported |
| `canSetReservedAttributeResult(r'$ip')` | Go V2 supports `$ip` | Current validator rejects `$ip` | Not a Web reserved key |

Do not advertise end-to-end Flutter Web parity just because JS 0.2.0 has a method.
Do not add a second JS call path to fake parity: Flutter would miss snapshots,
events and ownership guarantees. Explain the gap and scope an explicit SDK change
if the user needs it.

Myket timed subscriptions first shipped in Flutter 0.2.3 / Kotlin v0.2.2. Recovery
that corrects an older local product type requires Flutter 0.2.4 / Kotlin v0.2.3
and the matching V2 commerce backend. They use consumable IN_APP SKUs with server-managed duration
and manual renewal, not native store subscriptions. Flutter 0.2.2 / Kotlin v0.2.1
reject that route with `MYKET_SUBSCRIPTIONS_UNSUPPORTED`; store installation or
login cannot enable it. See [Myket setup and fulfillment](purchases.md#myket-product-types-and-timed-subscriptions).
The local channel protocol v1 and legacy HTTP V1 are separate contracts; this
release does not migrate V1 callers or change Bazaar/Direct fulfillment.

## Cache and automatic work

| Area | Android | iOS | Web provider / Flutter bridge |
| --- | --- | --- | --- |
| CustomerInfo default | `cachedOrFetched` | `cachedOrFetched` | Flutter `CACHED_OR_FETCHED`; direct JS `FETCH_CURRENT` |
| CustomerInfo stale threshold | 5 min foreground / 25 h background | 5 min in this backend | Provider 5 min visible / 25 h hidden; Flutter forwards policy |
| Startup | Configure restores/verifies and schedules recovery/prefetch | Configure loads verified Keychain state and schedules internal recovery | Provider restores/creates session, loads customer and prefetches offerings |
| Foreground/reconnect recovery | SDK observers: pending work or 5 min; error backoff at least 30 s | No Android observers; host may refresh customer/manual Direct deliveries | Follow provider/session/checkout lifecycle; no native recovery API |
| CustomerInfo persistence | Native verified cache | Keychain state | Memory-only CustomerInfo; refresh-token persistence is a separate concern |

`cachedOrFetched` on mobile returns cache immediately and schedules stale refresh;
it does not mean a request completed before the caller receives data. There is no
general polling timer. Do not replace these policies with a host TTL/cache layer.

All three combined-sync implementations admit five executions per rolling
60 seconds. An admitted failure counts; login/logout/configure do not reset the
client quota. Over limit: no network, current-session offerings cache or
`RATE_LIMITED_NO_CACHE` with retry timing. Do not reset the SDK or change user to
evade this limit. iOS flushes pending custom/reserved attributes once before the
fresh offerings fetch; an empty attribute queue still permits that fetch.

## Authoritative source map

The Flutter links document the public API. For native recovery, inspect the
resolved Kotlin v0.2.3 source and matching deployed backend as well.

- [Public Flutter facade](https://github.com/InappifyLabs/flutter-sdk/blob/v0.2.4/lib/inappify_sdk.dart)
- [Coordinator and mobile-only gates](https://github.com/InappifyLabs/flutter-sdk/blob/v0.2.4/lib/src/application/inappify_coordinator.dart)
- [Web adapter and supported operations](https://github.com/InappifyLabs/flutter-sdk/blob/v0.2.4/lib/src/platform/web/web_inappify_platform.dart)
- [Default exact lookup / unsupported operations](https://github.com/InappifyLabs/flutter-sdk/blob/v0.2.4/lib/inappify_sdk_platform_interface.dart)
- [iOS Go V2 implementation](https://github.com/InappifyLabs/flutter-sdk/blob/v0.2.4/lib/src/platform/mobile/go_v2_platform.dart)
- [Android channel contract](https://github.com/InappifyLabs/flutter-sdk/blob/v0.2.4/android/src/main/kotlin/com/inappify/inappify_sdk/InappifyChannelContract.kt)
- [Direct JS implementation](https://github.com/InappifyLabs/web-sdk/blob/v0.2.0/src/client.ts)

Known documentation drift: older Flutter Web examples pass removed `country` and
`appVersion` to ordinary `configureResult`; some prose calls combined sync Android
only or mentions a public recover/configure flag that no longer exists. Use the
tagged signatures above. Web-specific authenticated startup and `createCheckout`
still have their own optional context inputs; do not add them to mobile configure.
