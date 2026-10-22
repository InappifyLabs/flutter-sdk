# Web 0.2.0 and Flutter Web 0.2.2

Read the [platform matrix](platforms.md) before sharing a mobile example with a
PWA. Direct JavaScript APIs and Flutter bridge coverage are not identical.

## Browser setup and session ownership

Use the **Public Web App Key**, an approved website origin and enabled Web
features. Never put a project/server key in the browser. The host build must
bundle `@inappifylabs/web-sdk@0.2.0`; a bare npm import is not a browser-ready
Flutter asset. Use the shipped `web/inappify_web_sdk_entry.mjs` as a bundler input
and load the resulting self-hosted provider before `flutter_bootstrap.js`.

The entry publishes the provider constructor/version/error detector at
`globalThis.__inappifyFlutterWebSdk`; the Flutter adapter creates/owns its sole
session. Do not create a second `InAppify.configure` instance in a Flutter host.
Missing provider returns an unavailable bridge, not a mobile fallback.
Configure prefetches offerings; a normal subsequent read can use that cache.
No Web SDK UI/paywall renderer, native store billing, or StoreKit is supplied.

Ordinary Flutter anonymous/retained startup is only:

```dart
Future<bool> startAnonymousWeb(String publicWebKey) async {
  final configured = await InappifySdk.configureResult(apiKey: publicWebKey);
  return configured.isSuccess;
}
```

This can restore a retained authenticated provider session; don't call it logout.
Do not pass a known authenticated user's ID to ordinary Web configure or call
`logInResult(String)` there. Browser identity must be proven with a ticket/OTP.

For a host user already authenticated by your application:

```dart
Future<bool> startAuthenticatedWeb({
  required String publicWebKey,
  required String hostUserId,
  required Future<String> Function() fetchFreshTicket,
}) async {
  final result = await InappifySdk.configureAuthenticatedWebSessionResult(
    apiKey: publicWebKey,
    expectedCustomerIdentifier: hostUserId,
    identityTicketProvider: fetchFreshTicket,
    country: 'IR',
    appVersion: '2.0.0', // the host app version, not the SDK version
  );
  return result.isSuccess;
}
```

The helper has optional country/appVersion/cancellation. Its provider callback
calls **your authenticated backend** for a fresh short-lived, single-use ticket.
Pass the expected user ID so an unrelated retained session cannot be accepted.
The SDK decides when recovery/exchange is needed; don't eagerly issue and cache
tickets for every startup, or exchange through two aliases for the same ticket.

Explicit login alternatives after configure:

```dart
Future<void> webAuthenticationExamples(String ticket, String phone) async {
  await InappifySdk.loginWithIdentityTicketResult(identityTicket: ticket);
  // exchangeIdentityTicketResult(...) is an alias: use only one per ticket.
  // Alternative authentication flow, only on explicit user interaction:
  final challenge = await InappifySdk.requestOtpResult(phone: phone);
  if (!challenge.isSuccess) return;
  // Render the returned challenge and later pass its ID + user-entered code to
  // verifyOtpResult(challengeId: ..., code: ...).
}
```

OTP may require `createOtpCaptchaResult()` then `requestOtpResult(phone: ...,
captchaKey: ..., captchaAnswer: ...)`. Render the service's challenge; never
bypass CAPTCHA or silently send SMS in validation/tests.

Use `sessionState`, `sessionStateChanges`, and snapshots for lifecycle. Temporary
network/storage unavailability is not automatic logout. `recoveryRequired`
requires the supported establishment path. Tokens remain inside the provider;
do not read or mirror them through legacy Dart compatibility fields.

## Flutter Web checkout and discounts

`purchaseResult(Package)` is supported and returns a projected `PurchaseResult`:
Paid → `DONE`, otherwise `NEEDTOPAY`, with checkout ID/status/action when supplied.
The adapter invokes JS purchase with `redirect: false`; Flutter host navigation
owns the next action. An SDK-successful checkout is not automatically paid.

For canonical checkout data, especially a discount code, use `createCheckout`:

```dart
Future<InappifySdkResult<InappifyCheckoutResult>> createDiscountedWebCheckout({
  required PackageModel validatedPackage,
  required String discountCode,
  required String savedAttemptId,
}) async {
  final offering = validatedPackage.offeringIdentifier;
  final package = validatedPackage.identifier;
  final product = validatedPackage.product?.identifier;
  if (offering == null || package == null || product == null) {
    throw ArgumentError('Use the complete package returned by the SDK.');
  }
  return InappifySdk.createCheckout(
    offeringIdentifier: offering,
    packageIdentifier: package,
    productIdentifier: product,
    discountCode: discountCode,
    idempotencyKey: savedAttemptId,
  );
}
```

Required strings: product/offering/package identifier. Optional:
`discountCode`, `country`, `appVersion`, `idempotencyKey`, `cancellation` (null),
and legacy Web `isCrypto` (false). That compatibility Web parameter is not a
native `InappifyPurchaseParams` option. Do not introduce it into mobile purchase.

Validate via `getDiscountedPaymentLinksResult(code,
offeringIdentifier: selectedOffering.identifier)` for a placed offering. Omission
selects current. Explicit empty/invalid IDs do not fall back. Check both result
success and `data.isValid`; the returned discounted `offering` is separate from
the original catalog. Keep `code`, `isValid`, `errorCode`, `paymentLinks` and
offering data; don't project the response into a native-links-only object.
Use that validated offering's package context and code for checkout; never
replace the SDK's base catalog or calculate final amount in the app.

`createCheckout` returns server price, checkout expiry/status, and nextAction.
Persist `checkout.id` and the attempt/user context **before navigating**. A
redirect action is followed only under the host's destination/origin policy.
Flutter's typed Web model permits HTTP(S)/relative URLs; don't assume the mobile
`isPaymentUrlAllowed` helper exists on Web. Do not trust arbitrary return-query
URLs or a string containing an expected hostname.

```dart
Future<bool> verifyFlutterWebReturn(String savedCheckoutId) async {
  final result = await InappifySdk.handlePaymentReturnResult(
    checkoutId: savedCheckoutId,
    timeoutMs: 60000,
    intervalMs: 1500,
  );
  if (!result.isSuccess || result.data?.isPaid != true) return false;
  final info = await InappifySdk.getCustomerInfoResult();
  return info.isSuccess;
}
```

`getCheckoutStatus(checkoutId: id)` makes one query; `handlePaymentReturnResult`
polls (defaults 60000 ms/1500 ms). When checkoutId is omitted, the facade reads
`getPendingCheckoutIdResult()` / provider-backed pending session storage. Missing
ID is a failure. `getPendingCheckoutId()` is the nullable companion. Storage
failure is not proof no checkout exists. Keep host correlation when required.
Timeout/cancellation of observation does not undo the payment; reconcile the
same checkout. A paid checkout still isn't a consumable host inventory grant.

## Flutter 0.2.2 cache and sync contract

Flutter 0.2.2 requires provider 0.2.0+. It forwards combined sync to the same
provider instance: fresh customer information, then refreshed offerings. Web
setters already write to the server; do not invent an offline queue or upload
attributes again. The provider admits five calls per rolling sixty seconds,
counts failures, keeps the allowance across login/logout, and returns same-session
offerings above the limit. Without cache, inspect retryable failure
`details['serverCode'] == 'RATE_LIMITED_NO_CACHE'` and numeric `retryAfterMillis`.
An admitted network failure remains failure, with the last valid/partially
refreshed snapshot retained.

Both CustomerInfo public methods explicitly forward all four policies. Flutter
defaults to `cachedOrFetched` (`CACHED_OR_FETCHED`), while direct JS defaults to
`FETCH_CURRENT`. Cache-only does no HTTP and does not wait behind a pending network
read; absence is `CACHE_MISS`. Required fresh reads never fall back to stale
success. Background updates reach Flutter's mirror/events, with prior-account
and superseded responses rejected. Cancellation options are the second JS
argument. Do not add a second persistent CustomerInfo cache.

Historical Flutter 0.2.1 lacked combined sync and ignored policy forwarding on
Web. Inspect the resolved Flutter version before promising the corrected behavior.

## Remaining Flutter adapter gaps

- Flutter delivery handler, native consumable sync/confirm, store sync/restore,
  native attempt history and mobile URL/network controls are unavailable on Web.
  Direct JS delivery support does not make those Flutter methods available.
- Exact offering lookup **does work** through the shared catalog helper even
  without a distinct JS `getOffering` bridge call. Do not classify all inherited
  methods as unsupported solely from a capabilities enum.

## Direct JavaScript 0.2.0 API

These examples are for a **direct JS integration**, not additional calls beside
an active Flutter-owned session. Methods throw `InAppifyError`; they do not
return Flutter's `InappifySdkResult` or provide `*Result` variants.

```ts
import { InAppify, CacheFetchPolicy, DeliveryResult } from '@inappifylabs/web-sdk'
import type { ConsumableDelivery } from '@inappifylabs/web-sdk'

export async function configureBrowser(publicWebKey: string) {
  return InAppify.configure({
    apiKey: publicWebKey, country: 'IR', appVersion: '2.0.0',
  })
}

export async function browserReads(client: InAppify) {
  await client.getCustomerInfo() // FETCH_CURRENT by default
  await client.getCustomerInfo(CacheFetchPolicy.FETCH_CURRENT)
  await client.getCustomerInfo(CacheFetchPolicy.CACHE_ONLY)
  await client.getCustomerInfo(CacheFetchPolicy.NOT_STALE_CACHED_OR_CURRENT)
  await client.getCustomerInfo(CacheFetchPolicy.CACHED_OR_FETCHED)
  const catalog = await client.getOfferings()
  catalog.current
  catalog.getOffering('special_offer')
  catalog.getCurrentOfferingForPlacement('upgrade')
  await client.getCurrentOffering()
  await client.getCurrentOffering('upgrade')
  await client.getOffering('special_offer')
  await client.setAttributes({ language: 'fa', removed: null, also_removed: '' })
  await client.syncAttributesAndOfferingsIfNeeded()
  client.hasEntitlement('premium')
  client.isActiveEntitlement('premium')
  client.getEntitlement('premium')
}

export async function ticketLogin(client: InAppify, freshTicket: string) {
  await client.logIn({ identityTicket: freshTicket })
}

export async function otpLogin(client: InAppify, challengeId: string, code: string) {
  await client.logIn({ challengeId, code })
}

export async function buyPlacedOffering(
  client: InAppify, placement: string, code: string, savedAttemptId: string,
) {
  const selected = await client.getCurrentOffering(placement)
  if (!selected) return null
  const validation = await client.validateDiscountCode(code, selected.identifier)
  if (!validation.discount.isValid) return null
  const packageItem = validation.offering.packages[0]
  if (!packageItem) return null
  return client.purchase({
    package: packageItem, discountCode: code, idempotencyKey: savedAttemptId,
  }, { redirect: false })
}

export function registerBrowserDelivery(
  client: InAppify, grantOnce: (delivery: ConsumableDelivery) => Promise<void>,
) {
  return client.setConsumableDeliveryHandler(async delivery => {
    try {
      await grantOnce(delivery) // durable transaction; original customer/source
      return DeliveryResult.DELIVERED
    } catch {
      return DeliveryResult.RETRY_LATER
    }
  })
}

export async function synchronizeBrowserDelivery(client: InAppify) {
  return client.syncPendingConsumables()
}

export async function endBrowserSession(client: InAppify) {
  await client.logOut()
}
```

Direct JS configuration defaults: base URL `https://api.inappify.com/api/web/v1`,
timeout 15000 ms, offerings TTL 5 min, prefetch true, country IR, appVersion empty.
Use the host version when known; `SDK_VERSION` is supplied by the provider build.
Access tokens stay in memory; refresh tokens use IndexedDB when available, with
memory fallback. Memory-only sessions don't promise survival after reload.
CustomerInfo snapshots are not persistently cached by this release.

Direct JS combined sync refreshes CustomerInfo then fresh offerings; attribute
setters already send writes, so there is no native-style offline attribute queue
to flush. It has five admitted calls per rolling 60 s; failures count, identity
changes do not reset quota, excess returns session offerings cache or
`RATE_LIMITED_NO_CACHE`. Do not synthesize quota resets.

Direct JS `OfferingsResult.all` and `CustomerInfo.entitlements` are **arrays**,
unlike Flutter's offering map helper and entitlement `active/all` maps. Prefer
`client.hasEntitlement` after the intended customer read; don't paste Dart map
access into JS. Placement resolver uses existing Web rules/fallbacks locally.

Direct JS `purchase` redirects by default; `{redirect: false}` returns nextAction
to host navigation. `createCheckout` never redirects. Save checkout identity and
call `getCheckoutStatus(id)` or `handlePaymentReturn(id, options)` after return.

Direct JS consumables: register the explicit-result handler above then call
`syncPendingConsumables(options?)`; only `DELIVERED` allows acknowledgement.
Without a handler it returns `pendingDeliveries`; manual code must grant durably
before `confirmDelivery(deliveryId)`. The registration returns an unregister
function. Never mix handler/manual owners or accept native-store consumption
actions in a Web Direct flow. Handle customer transitions around host async work.

## Legacy Web compatibility

Web 0.2.0 deliberately retains old aliases/options (`logout`, ticket/OTP aliases,
identifier-based purchase, `getCurrentOffering(options)`, `getOfferings` force
option, `checkEntitlement`, attribute helpers, inline consumable-handler overload).
Keep existing apps working. For new code use the semantic forms above. Do not
delete compatibility APIs or force native signatures onto the JS provider.
Explicit blank offering IDs must never be rewritten to an omitted parameter or
retried with default: Flutter rejects blank; direct JS forwards explicit strings
for server validation. Neither is permission to apply another offering's discount.
