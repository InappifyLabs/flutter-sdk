# API reference

The public entry point is the static `InappifySdk` facade. Its constructor creates
a compatibility handle; it does not create an independent session. Android owns
one native Kotlin client, iOS one Dart V2 client, and Web one JavaScript session.

## Imports and result contract

```dart
import 'package:inappify_sdk/inappify_sdk.dart';
import 'package:inappify_sdk/models/enums/market.dart';
import 'package:inappify_sdk/models/enums/purchase_status.dart';
import 'package:inappify_sdk/models/attribute.dart';
import 'package:inappify_sdk/models/customer_info.dart';
import 'package:inappify_sdk/models/offering_model.dart';
import 'package:inappify_sdk/models/package_model.dart';
import 'package:inappify_sdk/models/purchase_result.dart';
```

The entry-point library exports mobile workflow types, results/failures/snapshots,
Web authentication and checkout models, cancellation, session lifecycle and
`OfferingEvaluationContext`. Catalog/customer compatibility models and the
`Market`/`PurchaseStatus` enums use the explicit imports above. Additional models
can be imported from their files under `models/`; applications should not depend
on implementation libraries under `src/`.

`InappifySdkResult<T>` has `data: T?`, `snapshot: InappifySdkSnapshot?` and
`failure: InappifyFailure?`. `isSuccess` is true when `failure == null`. A successful
void operation has no data, and a successful current-offering query may have null
data. Do not assume every successful result contains a non-null model.

`InappifyFailure` contains `code`, sanitized `message`, `isRetryable` and
codec-safe `details`. Use the specific returned failure for concurrent operations.
`lastFailure` records the most recently completed facade operation, including null
for success; it is not a per-purchase error slot.

## Configuration and lifecycle

| Method | Return and behavior |
| --- | --- |
| `configureResult(...)` | `InappifySdkResult<void>`; configure the selected backend |
| `configure(...)` | bool projection of configure success |
| `configureGoV2(...)` | Typed mobile configuration convenience; same default protocol, no market arguments |
| `restoreCachedSessionResult(...)` | `InappifySdkResult<bool>`; exposed API, currently unsupported by production mobile clients and unavailable on Web |
| `loginResult(apiKey:, appUserIdentifier:)` | Typed mobile identity change; stable-ID login is unsupported on Web |
| `login(...)` | bool projection |
| `logoutResult(cancellation:)` | Typed backend lifecycle change |
| `logout(...)` | bool projection |
| `recover()` | Typed mobile recovery; reconciles pending lifecycle/attributes/purchases and resources |
| `setNetworkEnabled(bool)` | Typed mobile network gate; enabling it is not itself a recovery call |

`configure`/`configureResult`/`restoreCachedSessionResult` accept:

| Parameter | Meaning/default |
| --- | --- |
| `apiKey` | Required app public bootstrap key; Web uses the Public Web App Key |
| `appUserIdentifier` | Optional public mobile user ID; omission retains a persisted identity or creates an anonymous one |
| `market` | Optional Android local market configuration: `bazar`, `myket`, `none` |
| `marketKey` | Optional store RSA public key; required for local store adapters |
| `country` | Optional two-letter country; mobile default `IR` |
| `appVersion` | Optional host app version; mobile otherwise reads platform metadata |
| `mobileProtocol` | `InappifyMobileProtocol.goV2`, the sole mobile value/default |
| `enableSubscriptionRecoveryWithoutPayload` | true; Android Bazaar only, ignored on iOS/Web |

Mobile Configure/renewal use the public app key as Bearer, without inserting an
app-key field into request JSON. Authenticated V2 requests use the backend-owned
`sessionToken` as Bearer. Market keys configure the local store
adapter. Do not set compatibility credential getters or pass request overrides to
manage authentication. Web's credential model is described in [Web](WEB.md).

Identical concurrent configuration requests share an operation. Lifecycle and
semantic operations are serialized by the coordinator; later customer changes
cannot be overwritten by an older native revision. Configure on each startup.
Use validated session loading within configure, not the unsupported cache-only
restore API. See [getting started](GETTING_STARTED.md) and
[security/cache](SECURITY_AND_CACHE.md).

## Customer information and access

| Method | Return/default |
| --- | --- |
| `getCustomerInfoResult(forceRefresh: true, cancellation:)` | Typed customer model; mobile true maps to networkOnly, false to cacheFirst |
| `getCustomerInfo(...)` | CustomerInfo or null on failure |
| `customerInfoWithPolicy(policy)` | Typed mobile explicit-policy customer query |
| `checkEntitlementResult(identifier, forceRefresh: true, cancellation:)` | Typed bool; backend verifies current customer access |
| `checkEntitlement(...)` | true only for a successful true result |
| `isActiveEntitlement(name)` / `hasEntitlement(identifier)` | Synchronous compatibility check against the mirror and device wall time |
| `getEntitlement(identifier)` | Active mirrored entitlement or null using the same compatibility check |
| `isCustomerAnonymous(appUserIdentifier:)` | String helper; null or supported anonymous spelling is treated as anonymous |

Use `checkEntitlementResult` for access decisions: mobile verified data is checked
using backend trusted time. Compatibility helpers require `isActive == true`,
check parsed expiry against `DateTime.now()`, and reject malformed nonempty mobile
expiry. They are UI helpers and cannot authorize a new consumable grant.

`CustomerInfo` contains nullable `originalAppUserId`, `firstSeen`, `requestDate`,
`latestExpirationDate`, `hasUsedTrial`, `entitlements`, `transactions`, `attributes`.
`EntitlementModel` contains identifier, isActive/isSandbox, period/purchase/expiry,
ownership/type and `purchaseStoreRefHash`/`purchaseStoreTime`. Store time is epoch
milliseconds. Store reference hashes do not expose raw purchase tokens.
`TransactionModel` describes server transactions and is not a store receipt.

### Mobile fetch policy

| `InappifyFetchPolicy` | Behavior |
| --- | --- |
| `cacheOnly` | Return usable current resource or a cache-miss failure; no resource HTTP |
| `cacheFirst` | Return existing resource immediately and schedule background refresh; otherwise fetch |
| `networkFirst` | Fetch and fall back to retained current-session resource on failure when available |
| `networkOnly` | Fetch and surface the failure without resource fallback |

These policies apply to `customerInfoWithPolicy` and `offeringsWithPolicy` on
mobile. Cache is scoped to current app/customer/context. No fixed five-minute
freshness guarantee is imposed. Resource cache is not evidence of a fresh payment.

## Offerings and targeting

| Method | Return/default |
| --- | --- |
| `getOfferingsResult(forceRefresh: false, cancellation:)` | Typed catalog; mobile false is cacheFirst, true networkOnly |
| `getOfferings(...)` | OfferingsModel or null on failure |
| `offeringsWithPolicy(policy)` | Typed mobile catalog query |
| `getCurrentOfferingResult(placementIdentifier:, forceRefresh: false, context:, cancellation:)` | Typed offering; success may have null data |
| `getCurrentOffering(...)` | OfferingModel or null; failure and null selection collapse |
| `setTargetingContextResult(country:, appVersion:)` | Typed update of non-null fields and invalidation of mobile offerings |
| `setTargetingContext(...)` | bool projection |

Mobile current selection uses requested placement → server current → catalog
default, and does not apply downloaded rules or a caller's `context` override.
Mobile requests flush queued attributes, then send host app version, backend SDK
version, country and paywall schema/renderer versions. The synchronous model
methods can resolve existing data but do not issue HTTP or change the session.
See [paywalls and targeting](PAYWALLS_AND_TARGETING.md).

`OfferingsModel` contains offerings/rules, forceVersion/fetchedAt,
`currentOfferingIdentifier`, placements and usesServerTargeting. Production V2
responses retain server selection and omit local rule/force-update inputs.
`OfferingModel` contains identifier, isDefault, serverDescription, trialDays,
metadata, packages and paywall. `PackageModel` contains identifier, packageType,
description, entitlement, name, discountPercent and product.
`StoreProductModel` contains identifier/name, prices, dollarPrice and trialDays.
`PriceModel` exposes nullable IDs/currency, numeric amount/originalAmount/
discountAmount, integer price/originPrice and createdAt/updatedAt.

These fields may be absent. The catalog does not expose a typed store product
classification: `packageType` must not be cast to `InappifyProductType`.
Model `fromJson`/`toJson` methods transport data but are not signature verification.

## Attributes

| Method | Return/behavior |
| --- | --- |
| `queueAttributes(Map<String, String?>)` | Typed mobile void; persist changes and invalidate offerings |
| `flushAttributes()` | Typed mobile void; upload queued changes |
| `setAttributesResult(attributes:, cancellation:)` | Typed List<Attribute>; mobile queue+flush success returns an empty list |
| `setAttributes(...)` | bool projection |
| `updateAttributesResult(values:, cancellation:)` / `updateAttributes(...)` | Map-style setter / bool projection |
| `deleteAttributesResult(keys:, cancellation:)` / `deleteAttributes(...)` | Delete keys / bool projection |
| `syncAttributesResult(attributes:, idempotencyKey:, cancellation:)` | Typed synchronization of supplied values or compatibility mirror values |
| `syncAttributes(...)` | bool projection |
| `setReservedAttributeResult(attribute:, value:, cancellation:)` | Typed void reserved-key setter |
| `canSetReservedAttributeResult(key)` / `canSetReservedAttribute(key)` | Typed capability query / bool |

Production mobile attributes are write-only. Custom keys match
`[A-Za-z][A-Za-z0-9_-]{0,39}`, values are null or at most 500 Unicode code points.
Null and empty remove a value; whitespace is a value. Invalid input fails instead
of being silently omitted. The durable queue holds at most 1000 distinct keys;
upload batches contain up to 50. A definitive HTTP422 quarantines the rejected
batch. The current mobile attribute endpoint does not send the optional request
idempotency key. No setter fetches a complete attribute list.

On mobile, prefer `flushAttributes()` for an already queued change. The facade's
`syncAttributesResult` builds a list from its `attributes` argument, falling back
to `customerInfo.attributes` or an empty list; this is not an attribute read API.
Web attribute semantics and reserved-key capabilities are backend-defined; see
[Web](WEB.md) instead of assuming mobile queue operations exist in a browser.

Reserved convenience methods all return bool and accept an optional cancellation:

| Method/argument | Production mobile backend key |
| --- | --- |
| `setEmail(email:)` | `$email` |
| `setDisplayName(displayName:)` / `setDisplayname(displayName:)` | `$displayName` |
| `setApnsToken(apnsToken:)` | `$apnsTokens` |
| `setFcmToken(fcmToken:)` | `$fcmTokens` |
| `setIdfa(idfa:)` | `$idfa` |
| `setIdfv(idfv:)` | `$idfv` |
| `setPhoneNumber(phoneNumber:)` | `$phoneNumber` |
| `setCampaign(campaign:)` | `$campaign` |
| `setKeyword(keyword:)` | `$keyword` |
| `setIp(ip:)` | `$ip` is exposed by the enum but unsupported by production mobile validation |

Capability checks take the exact backend key. Do not assume every enum value is
accepted by a backend.

## Purchases, delivery and recovery

`purchaseResult` returns `InappifySdkResult<PurchaseResult>`; `purchase` returns
data or null on failure/cancellation. Both require `productIdentifier` and
`offeringIdentifier`. Use values from the current catalog.

| Parameter | Supported mobile behavior |
| --- | --- |
| `packageIdentifier` | Optional matching Inappify package ID, not the Android package name |
| `productType` | Store enum consumable/nonConsumable/subscription; use the actual SKU classification |
| `idempotencyKey` | Optional safe `[A-Za-z0-9_.:-]{1,128}` attempt ID; facade creates one if omitted |
| `market` | Default none; server route remains authoritative; a matching store value cannot switch route |
| `isCrypto` | false; Direct-only option |
| `paywallId`, `paywallRevision` | Optional Direct attribution; positive values supplied together |
| `apiKey`, `marketKey`, `country`, `appVersion`, `dynamicPriceToken` | Unsupported mobile purchase overrides; omit |
| `discountCode`, `discount` | Unsupported mobile purchase overrides; omit/default zero |
| `isLostPurchase`, `lostPurchaseToken`, `lostPurchaseTime` | Not a public receipt-import API; omit/default false and use recovery |
| `cancellation` | Cooperative handle when the selected backend supports it |

Explicit subscription type is needed to start Bazaar subscription billing. Myket
rejects subscription. Omission chooses in-app billing without guessing consumable
versus non-consumable fulfillment. Android forwards the request to the native
SDK and supplies the foreground attached Activity for a new store purchase.

Create a fresh attempt ID for a deliberate new purchase; reuse it only for the
same logical attempt. Typed failures include that non-secret ID in `details`.
The local correlation key does not promise server idempotency for Direct checkout
creation; an uncertain Direct call can have committed. Reconcile before opening a
second checkout. Do not retry merely because the host did not receive DONE.

`PurchaseResult` contains nullable url/purchaseStatus, checkoutId/checkoutStatus/
nextActionType and `mobile: InappifyMobilePurchaseData?`. `PurchaseStatus` is DONE
or NEEDTOPAY. For store workflow, mobile data contains storePurchaseStatus,
deliveryId, verificationRequestId, alreadyProcessed, product/offering/package,
idempotencyKey and market. Raw store tokens, original receipts and signatures are
not public purchase-result fields.

| `InappifyStorePurchaseStatus` | Meaning |
| --- | --- |
| processing | Verification unfinished; resume is SDK-owned |
| completed / restored / alreadyProcessed | Server-confirmed terminal store result |
| deliveryRequired | Verified consumable awaits durable host grant |
| consumeRequired | Grant acknowledged; store consumption unfinished |
| rejected | Definitively rejected; do not grant |

The enum retains uppercase wire values. A workflow state is not a guarantee that
`purchaseResult` returns success at that intermediate state. Terminal store success
maps to DONE; pending/delivery/consume/rejected states do not. Access comes from
verified CustomerInfo; consumable inventory requires durable delivery handling.

| Method | Typed mobile result |
| --- | --- |
| `syncPurchases()` | List<PurchaseResult>; reconcile pending/owned store work or Direct deliveries |
| `restorePurchases()` | InappifyRestoreResult; explicit restore with restored/alreadyProcessed/failed counts |
| `syncPendingConsumables()` | InappifyConsumableSyncResult with discoveredCount, completedCount, pendingDeliveries |
| `confirmDelivery(deliveryId)` | PurchaseResult; acknowledge a durable host grant, then native store consume when needed |
| `isPaymentUrlAllowed(url)` | bool; mobile backend allowlist check before the host opens Direct payment |

`InappifyRestoreResult.totalCount` sums all three counts; a successful aggregate
can still contain failed items. `InappifyConsumableDelivery` has positive
deliveryId, productIdentifier, optional transactionIdentifier and source direct,
bazaar or myket. Scope your durable unique grant key by app/customer/source and
deliveryId. Flutter does not expose the native Kotlin delivery-handler callback;
use pending-delivery sync plus explicit confirm. Never grant again after an
acknowledgement fails. See [stores/recovery](STORES_AND_RECOVERY.md).

## Discount codes and configuration

| Method | Result |
| --- | --- |
| `validateDiscountCodeResult(discountCode:, offeringIdentifier:, cancellation:)` | Typed ValidateDiscountCodeData |
| `validateDiscountCode(...)` | Data or null |
| `getConfigurationResult()` / `getConfiguration()` | Typed token-free InappifyConfiguration / data or null |

Mobile discount validation sends only `code`; its optional offering parameter is
not sent by the current endpoint. SDK success and `data.isValid` are separate.
The result includes optional errorCode, code/discount IDs, percent, message,
paymentLinks and offering. Each PurchaseLink contains offering and url. Validation
does not make mobile purchase discount overrides supported.

`InappifyConfiguration.values` preserves backend-provided codec-safe fields.
Android exposes mobileProtocol, hasForceUpdate (false), isLogoutPending and verified
session scope when available. This query is not a server endpoint discovery API.
Web may provide additional capabilities and checkout allowlists.

## Browser authentication and checkout

These methods are exposed by the facade for the JavaScript Web backend. Production
Android/iOS do not implement Identity Ticket/OTP or browser checkout-status APIs.

| Method | Result/default |
| --- | --- |
| `configureAuthenticatedWebSessionResult(apiKey:, identityTicketProvider:, expectedCustomerIdentifier:, country:, appVersion:, cancellation:)` | Typed void; create/restore Web transport session and obtain a fresh ticket when needed |
| `configureAuthenticatedWebSession(...)` | bool projection |
| `exchangeIdentityTicketResult(identityTicket:, cancellation:)` | Typed InappifyAuthenticationResult |
| `exchangeIdentityTicket(...)` | Authentication data or null |
| `loginWithIdentityTicketResult(...)` / `loginWithIdentityTicket(...)` | Aliases; exchange a ticket through exactly one method |
| `createOtpCaptchaResult(cancellation:)` / `createOtpCaptcha(...)` | Typed InappifyCaptchaChallenge / data or null |
| `requestOtpResult(phone:, captchaKey:, captchaAnswer:, cancellation:)` / `requestOtp(...)` | Typed InappifyOtpChallenge / data or null |
| `verifyOtpResult(challengeId:, code:, cancellation:)` / `verifyOtp(...)` | Typed authentication data / data or null |
| `createCheckout(productIdentifier:, offeringIdentifier:, packageIdentifier:, discountCode:, country:, appVersion:, idempotencyKey:, isCrypto: false, cancellation:)` | Typed InappifyCheckoutResult; does not navigate |
| `getCheckoutStatus(checkoutId:, cancellation:)` | Typed one-shot checkout state |
| `getPendingCheckoutIdResult()` / `getPendingCheckoutId()` | Typed String / string or null; success may have null data |
| `handlePaymentReturnResult(checkoutId:, timeoutMs: 60000, intervalMs: 1500, cancellation:)` | Typed authoritative checkout polling |
| `handlePaymentReturn(...)` | Checkout data or null |

Identity Tickets are short-lived, single-use credentials obtained by the host from
its trusted backend. Never persist or resend one. The authenticated configure
helper coalesces identical startup requests and reconciles ambiguous exchange
without reusing a ticket. Its mobile behavior is ordinary configure, so do not
call it as a mobile authentication substitute.

`InappifyCheckoutResult` contains checkout(id/status/expiry), nextAction(type/url)
and optional server price(originalAmount/discountAmount/finalAmount/currency).
`isPaid` matches the backend's paid state. The host owns redirect navigation and
payment-return handling. Omitted checkoutId uses the pending browser ID; absence
is an invalidConfiguration failure. Query-string payment success is not authoritative.
See [Web](WEB.md) for script setup, URLs, origin checks and the complete flow.

## Events, snapshots and compatibility fields

| Getter | Meaning |
| --- | --- |
| `events` | Ordered asynchronous InappifyPlatformEvent stream |
| `httpTraces` | Filtered opt-in mobile HTTP trace stream, active while listened to |
| `sessionStateChanges` | Token-free session lifecycle events projected from events |
| `snapshot` | Last mirrored backend snapshot |
| `customerInfo`, `offerings`, `storeInfo` | Last mirrored models/store metadata |
| `appId`, `country`, `vName`, `vCode`, `sdkVersion` | Backend/app metadata; vName is host app version |
| `sessionState`, `sessionPersistenceMode` | Reported lifecycle/persistence state |
| `faildToLoadOfferings`, `faildToLoadCustomerInfo` | Compatibility spellings for latest refresh failure flags |
| `lastFailure` | Last facade failure; prefer operation result |
| `accessToekn`, `apiKeyValue` | Compatibility spellings; no access/session token is exposed; Web may mirror its public app key |

Some compatibility getters retain setters. Changing these mirror fields does not
change the canonical native/Dart/browser session, upload attributes or renew a
Bearer token. Use SDK operations instead.

Snapshot contains customer/catalog, store/app/version/country, failure flags and
optional mobile revision/isConfigured/isAuthenticated/user/storePlatform/market/
mobileProtocol/isLogoutPending. Compatibility accessToken/apiKey fields are empty
in production mobile V2 snapshots; Web may mirror the public Web key but never
its access/refresh tokens. `storePlatform` preserves backend integers: 1 DirectIos, 2 DirectAndroid, 3 DirectWeb,
5 PlayStore, 6 AppStore, 10 Bazar, 11 MyKet and 12 SibApp. Exposing a backend
integer does not mean this Flutter package implements that store.
Web may omit mobile fields. Do not infer authentication from the existence of a
customer model; inspect lifecycle state and operation results.

Event types are stateChanged, customerInfoChanged, offeringsChanged,
authenticationChanged, sessionStateChanged and purchaseUpdated. Events can contain
requestId, snapshot and data. Not every backend emits every category; native
Kotlin currently emits state/customer/offering/authentication updates, so do not
wait for purchaseUpdated as the Android completion signal. Dispose subscriptions.

`InappifyHttpTrace` has method/endpoint, filtered request/response headers and
bodies, statusCode/requestId, durationMillis and failure. containsSensitiveData is
false; the Flutter contract rejects a raw trace. See
[security/cache](SECURITY_AND_CACHE.md) for practical logging guidance.

## Failures and cancellation

Failure codes are invalidConfiguration, notConfigured, unauthorized,
sessionTemporarilyUnavailable, sessionRecoveryRequired, identityMismatch, network,
requestCancelled, timeout, storeUnavailable, storageUnavailable, purchaseCancelled,
bridgeUnavailable, unsupportedOperation, protocolMismatch, malformedResponse and
unknown. Native finer-grained errors can be represented by `details.nativeCode` or
category/reason. Inspect supplied httpStatus/serverCode/retryAfterMillis/
outcomeMayHaveCommitted instead of treating every failure as a retryable charge.

`InappifyRequestCancellation` has `isCancelled`, `whenCancelled` and idempotent
`cancel()`. Web maps it to AbortSignal. Native and other adapters may ignore it
when they cannot safely cancel; cancelling a host wait is not cancellation of a
store charge or durable recovery checkpoint.

A missing/incompatible Android plugin returns bridgeUnavailable. An absent or
incompatible Web SDK cannot be replaced by a mobile Dart session. Unsupported
operations return typed failures or the compatibility null/false projection.
