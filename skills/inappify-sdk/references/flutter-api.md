# Flutter 0.2.1 public API recipes

Use `import 'package:inappify_sdk/inappify_sdk.dart';`. All calls below are static.
Examples are independent API demonstrations, not a script to execute every call
on startup. Gate operations by [platform support](platforms.md).

## Result handling

`InappifySdkResult<T>` has `isSuccess`, nullable `data`, nullable `failure`, and
nullable `snapshot`. Failure exposes `code`, `message`, `isRetryable`, and sanitized
`details`. Do not interpret retryable failure as permission to start a new payment.
Convenience methods return bool or nullable data and can hide the distinction
between failure and missing data. Use typed variants for commerce decisions.

## Mobile configuration and identity

```dart
Future<void> mobileSessionExamples(String apiKey, String customerId) async {
  await InappifySdk.configureResult(apiKey: apiKey);
  // Alternative startup when the host user is already known:
  await InappifySdk.configureResult(
    apiKey: apiKey, appUserIdentifier: customerId,
  );
  // Later account transitions, not part of every startup:
  await InappifySdk.logInResult(customerId);
  await InappifySdk.logOutResult();
}
```

Convenience companions: `configure(...)`, `logIn(id)`, `logOut()` return bool.
Only `apiKey` is required; optional identity defaults to null. Omission can reuse
the saved identity. Native metadata supplies app version; the server supplies
market/RSA. No public market, RSA, force-version or protocol arguments.
Let the SDK create anonymous identities; don't manufacture one in host code.
Web identity uses [the separate authenticated flow](web.md).

## Offerings and placement

```dart
Future<void> offeringExamples() async {
  final catalog = await InappifySdk.getOfferingsResult();
  await InappifySdk.getCurrentOfferingResult();
  await InappifySdk.getCurrentOfferingResult(placementIdentifier: 'upgrade');
  await InappifySdk.getOfferingResult('special_offer');
  // Helpers on a catalog already obtained; these helpers make no HTTP call:
  catalog.data?.current;
  catalog.data?.getOffering('special_offer');
  catalog.data?.getCurrentOfferingForPlacement('upgrade');
  catalog.data?.all['special_offer'];
}

Future<void> refreshMobileTargeting() async {
  final result = await InappifySdk.syncAttributesAndOfferingsIfNeeded();
  if (!result.isSuccess) return; // inspect failure; never bypass the limiter
  result.data?.getCurrentOfferingForPlacement('upgrade');
}
```

Companions `getOfferings()`, `getCurrentOffering(placementIdentifier: ...)`,
`getOffering(id)` return nullable models. Default placement is null. Combined
sync already returns a typed result; there is no additional `...Result` suffix.
No `refresh`, `forceRefresh`, or `context` in these facade calls.

On mobile selection is placement → server current → project default. Current can
vary by targeting; it is not synonymous with default. Exact ID lookup does not
fall back to another offering. Missing selection can be a successful null result.
For Web, let the provider evaluate its own targeting/placement resolver; do not
reimplement mobile selection in the app. Empty catalogs need configuration/error
diagnosis, not fabricated packages or a checkout with guessed identifiers.

## CustomerInfo and access

```dart
Future<void> customerExamples() async {
  final cached = await InappifySdk.getCustomerInfoResult();
  await InappifySdk.getCustomerInfoResult(
    fetchPolicy: InappifyCacheFetchPolicy.cachedOrFetched,
  );
  await InappifySdk.getCustomerInfoResult(
    fetchPolicy: InappifyCacheFetchPolicy.cacheOnly,
  );
  await InappifySdk.getCustomerInfoResult(
    fetchPolicy: InappifyCacheFetchPolicy.fetchCurrent,
  );
  await InappifySdk.getCustomerInfoResult(
    fetchPolicy: InappifyCacheFetchPolicy.notStaleCachedOrCurrent,
  );
  cached.data?.entitlements.active['premium'];
  cached.data?.entitlements.all['premium'];
  InappifySdk.hasEntitlement('premium');
  InappifySdk.isActiveEntitlement('premium');
  InappifySdk.getEntitlement('premium');
}
```

`getCustomerInfo(fetchPolicy: ...)` is the nullable companion. Mobile policies:

| Policy | Contract |
| --- | --- |
| `cachedOrFetched` (default) | Return cache, refresh stale cache in background; fetch if absent |
| `cacheOnly` | Cache or error, no network |
| `fetchCurrent` | Wait for server; no stale success fallback on failure |
| `notStaleCachedOrCurrent` | Fresh cache or wait for server; no stale fallback |

Flutter Web 0.2.1 does **not** forward these modes; it calls the JS provider's
default network fetch. Do not promise offline `cacheOnly` there. Direct JS has
four working policies with different enum spelling and default; see [Web](web.md).

`hasEntitlement`, `isActiveEntitlement`, `getEntitlement` read the latest mirrored
state synchronously; they do not request the server. Fetch fresh CustomerInfo
explicitly when needed and supported. Do not reimplement access from transaction
history or use a nullable expiration as proof of an active lifetime entitlement.
Subscriptions expire; a verified active non-consumable may be lifetime. Consumable
inventory belongs to the host's durable delivery ledger, not entitlement guesses.

## Attributes

```dart
Future<void> attributeExamples() async {
  await InappifySdk.setAttributesResult({
    'language': 'fa', 'removed': null, 'also_removed': '',
  });
  await InappifySdk.setEmail('person@example.com');
  await InappifySdk.setDisplayName('Alex');
  await InappifySdk.setPhoneNumber('09120000000');
  await InappifySdk.setCampaign('spring');
  await InappifySdk.setKeyword('upgrade');
  final allowed = await InappifySdk.canSetReservedAttributeResult(r'$email');
  if (allowed.isSuccess && allowed.data == true) {
    await InappifySdk.setReservedAttributeResult(
      attribute: InappifyReservedAttribute.email, value: '',
    );
  }
}
```

`setAttributes(Map<String, String?>)` returns bool. Native writes retain the
existing durable queue/retry/quarantine. Success is not a cross-platform promise
that every queued value has already reached the server. Don't expose queue,
flush, separate attribute sync, deletion, or manual targeting controls in new
host code. Use null/empty entries for deletion.

Other reserved helpers take one String: `setApnsToken`, `setFcmToken`, `setIdfa`,
`setIdfv`, `setIp`; the SDK doesn't imply permission to collect those identifiers.
Check `canSetReservedAttribute(key)` / typed companion and platform restrictions.
Web keys must be allowlisted; `$ip` is not supported there and iOS currently
rejects it. Do not bypass that validation or treat an attribute write as login.

## Purchase parameters

```dart
Future<void> purchaseExample(PackageModel selected, String savedAttemptId) async {
  final result = await InappifySdk.purchaseResult(InappifyPurchaseParams(
    packageToPurchase: selected,
    idempotencyKey: savedAttemptId,
  ));
  if (!result.isSuccess) return; // preserve the attempt on uncertainty
  final purchase = result.data;
  purchase?.mobile?.storePurchaseStatus;
  purchase?.mobile?.deliveryId;
  purchase?.checkoutId; // Web correlation, when present
}
```

`purchase(params)` is the nullable companion. `packageToPurchase` is required;
`idempotencyKey`, `paywallId` and `paywallRevision` default to null. If used,
paywall ID and revision are a matching pair. The SDK generates a key when omitted;
for host restart-safe correlation, persist a valid key **before** purchase
(1–128 characters from letters, digits, `_ . : -`) and reuse it only for that
same logical purchase. Read [purchase/recovery rules](purchases.md) first.

The original Package carries product/offering/package/type; the developer does
not pass an Android Activity. No native per-purchase API key, market/RSA,
`isCrypto`, arbitrary price/discount, or hand-written product-type override.

## Discount validation

```dart
Future<void> discountExamples(String code, String selectedOfferingId) async {
  await InappifySdk.getDiscountedPaymentLinksResult(code);
  final selected = await InappifySdk.getDiscountedPaymentLinksResult(
    code, offeringIdentifier: selectedOfferingId,
  );
  if (!selected.isSuccess || selected.data?.isValid != true) return;
  selected.data?.paymentLinks;
  selected.data?.offering;
  selected.data?.code;
  selected.data?.errorCode;
}
```

`getDiscountedPaymentLinks(code, offeringIdentifier: ...)` is nullable. Selector
defaults to null. Native Android/iOS keep code-only payment-link behavior; the
optional selector does not retarget those links. Web validates the explicit
offering or resolves current when omitted. Blank/invalid IDs must never silently
fall back. Discounted Web offering is separate from the base catalog.

Flutter's Package purchase params do not accept `discountCode`. When Web checkout
must carry that code, use the supported Web `createCheckout` signature in
[Web integration](web.md), using identifiers from the validated discounted
offering. Do not merely display a discount and assume payment will inherit it.

## Additional mobile controls

`customerInfoWithPolicy(policy)` and `offeringsWithPolicy(policy)` return typed
results for `InappifyFetchPolicy.cacheOnly`, `cacheFirst`, `networkFirst`,
`networkOnly`. This older generic policy enum is distinct from the four
CustomerInfo policies above. Prefer the semantic CustomerInfo API for new code;
do not infer cross-platform support from these signatures.

`setNetworkEnabled(bool)` gates mobile HTTP; it does not cancel paid work or
prove a purchase failed. `isPaymentUrlAllowed(String)` checks mobile Direct
destinations; Web uses its own navigation policy. `getConfiguration()` and
`getConfigurationResult()` expose non-secret backend configuration. `events`,
`snapshot`, and Web `sessionStateChanges` are observations, not writable state
or independent payment authority. Do not use legacy mutable facade setters.

For recovery, delivery, attempt history and payment returns, use the dedicated
recipes in [purchases](purchases.md) and [Web](web.md).
