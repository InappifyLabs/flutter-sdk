# Flutter API reference — 0.2.1

`InappifySdk` uses a static shared session. Android forwards these methods to the
current Kotlin client; Flutter owns no second Android purchase/cache pipeline.
Convenience methods return bool/nullable models. Their `*Result` companions retain
`InappifySdkResult<T>` with `data`, `failure`, `snapshot`, and `isSuccess`.
Successful Offering lookups may contain null.

## Configure and identity

```dart
await InappifySdk.configure(apiKey: 'public_key');
await InappifySdk.configure(apiKey: 'public_key', appUserIdentifier: 'customer_123');
await InappifySdk.configureResult(apiKey: 'public_key');
await InappifySdk.configureResult(apiKey: 'public_key', appUserIdentifier: 'customer_123');
await InappifySdk.logIn('customer_123');
await InappifySdk.logInResult('customer_123');
await InappifySdk.logOut();
await InappifySdk.logOutResult();
```

Only `apiKey` is required. The server supplies Android market/RSA configuration;
Android supplies its host app version. No country, market, public billing key,
protocol selector or recovery opt-out is a public Configure argument.

## CustomerInfo and entitlement checks

```dart
final info = await InappifySdk.getCustomerInfo();
final onlyCache = await InappifySdk.getCustomerInfo(fetchPolicy: InappifyCacheFetchPolicy.cacheOnly);
final current = await InappifySdk.getCustomerInfo(fetchPolicy: InappifyCacheFetchPolicy.fetchCurrent);
final fresh = await InappifySdk.getCustomerInfo(fetchPolicy: InappifyCacheFetchPolicy.notStaleCachedOrCurrent);
final cached = await InappifySdk.getCustomerInfo(fetchPolicy: InappifyCacheFetchPolicy.cachedOrFetched);
final result = await InappifySdk.getCustomerInfoResult(); // same optional fetchPolicy
final premium = info?.entitlements.active['premium'];
final known = info?.entitlements.all['premium'];
final anyAccess = info?.entitlements.active.isNotEmpty == true;
final local = InappifySdk.hasEntitlement('premium');
final localAlias = InappifySdk.isActiveEntitlement('premium');
final localRight = InappifySdk.getEntitlement('premium');
```

| Android policy | Behavior |
| --- | --- |
| `cachedOrFetched` (default) | Return cache immediately; refresh stale cache in the background; fetch when absent |
| `cacheOnly` | Verified cache or an error; no network |
| `fetchCurrent` | Wait for server data; return fetch failure without stale fallback |
| `notStaleCachedOrCurrent` | Fresh cache, otherwise wait for the server; no stale fallback |

Android freshness is five minutes foreground / twenty-five hours background;
there is no polling timer. Purchase/recovery refreshes and verified cache remain
native-owned. Entitlement maps are read-only and use Kotlin's trusted clock across
the bridge. `hasEntitlement`/`getEntitlement` read the latest mirrored state.
There is no public `checkEntitlement` or boolean force-refresh argument.

## Android purchase outcome tracking

```dart
final subscription = InappifySdk.purchaseUpdates.listen((attempt) {
  // attemptId matches the original purchase's idempotencyKey.
  // Inspect attempt.status, attempt.purchase and attempt.failure.
});
// After configure, including after restarting the app:
final result = await InappifySdk.getPurchaseAttempt('saved-attempt-id');
if (result.isSuccess && result.data != null) {
  final attempt = result.data!; // pending / succeeded / failed
}
final history = await InappifySdk.getPurchaseAttempts();
await subscription.cancel();
```

Both methods return typed `InappifySdkResult` values and read the native encrypted
history without network/store calls or cache refresh. Successful null lookup data
means unknown, never failed. Lookup failures must not clear the saved host attempt.
History is scoped to the configured app/customer/market, survives process/client
recreation and retains 256 latest terminal results plus up to 256 pending attempts.
Purchase/recovery events expose the typed outcome in `event.purchaseAttempt` and
`event.data['purchaseAttempt']`; `event.requestId` equals `attemptId`. Handle
repeated events idempotently and query history after configure for missed events.
Old event keys/bodies remain supported. Older/other platform implementations may
return `unsupportedOperation` for these additive methods without breaking old APIs.

Store recovery and new Direct checkout retain the original logical attempt in
events/history. Kotlin sends the Direct attempt ID to Laravel, and existing
automatic recovery checks the bound payment after app restart. Subscription and
lifetime outcomes use confirmed payment status; consumables await the existing
delivery acknowledgement. Existing consumable sync/confirm method results keep
their `direct-delivery-<id>` identity. Legacy payments without an attempt binding
keep their existing behavior; no product-based association is inferred.
Neither recorded success nor an empty sync result substitutes for current
CustomerInfo or an idempotent, durable host consumable grant.

## Offerings

```dart
final all = await InappifySdk.getOfferings();
final selected = await InappifySdk.getCurrentOffering();
final home = await InappifySdk.getCurrentOffering(placementIdentifier: 'home');
final special = await InappifySdk.getOffering('special_offer');
final refreshed = await InappifySdk.syncAttributesAndOfferingsIfNeeded();
// Typed companions: getOfferingsResult(), getCurrentOfferingResult(...), getOfferingResult(id).
final currentModel = all?.current;
final exactModel = all?.getOffering('special_offer');
final homeModel = all?.getCurrentOfferingForPlacement('home');
```

Selection is placement -> server current -> project default. No public forceRefresh
or context input. Android combined sync flushes the existing attribute queue and
fetches fresh offerings. The Kotlin client permits five admitted calls per rolling
60 seconds. Extra calls return session cache, or RATE_LIMITED_NO_CACHE when absent;
failed admitted calls count. Identity changes do not reset the client quota.
Normal Offering reads retain native five-minute foreground refresh and thirty-second
error backoff. Combined sync is a native Android capability.

## Attributes

```dart
await InappifySdk.setAttributes({'tier': 'gold', 'deleted': null, 'also_deleted': ''});
await InappifySdk.setAttributesResult({'tier': 'gold'});
await InappifySdk.setEmail('person@example.com');
await InappifySdk.setDisplayName('Alex');
await InappifySdk.setPhoneNumber('09120000000');
await InappifySdk.setIp('1.2.3.4');
await InappifySdk.setApnsToken('token');
await InappifySdk.setFcmToken('token');
await InappifySdk.setIdfa('idfa');
await InappifySdk.setIdfv('idfv');
await InappifySdk.setCampaign('campaign');
await InappifySdk.setKeyword('keyword');
final allowed = await InappifySdk.canSetReservedAttribute(r'$ip');
await InappifySdk.setReservedAttributeResult(
  attribute: InappifyReservedAttribute.email, value: 'person@example.com');
```

Writes retain native validation, durable queue, batching, retry and quarantine.
Null/empty means deletion. Go V2 attributes are write-only. No public queue,
flush, standalone attribute-sync, deletion or manual targeting controls remain.

## Purchase, discount links and recovery

```dart
final params = InappifyPurchaseParams(packageToPurchase: selectedPackage);
final purchase = await InappifySdk.purchase(params);
final typedPurchase = await InappifySdk.purchaseResult(params);
final retryParams = InappifyPurchaseParams(packageToPurchase: selectedPackage,
  idempotencyKey: sameAttemptId, paywallId: 12, paywallRevision: 3);
final links = await InappifySdk.getDiscountedPaymentLinks('SALE');
final typedLinks = await InappifySdk.getDiscountedPaymentLinksResult('SALE');
// Web: validate for the offering selected for a placement.
final webLinks = await InappifySdk.getDiscountedPaymentLinks('SALE',
  offeringIdentifier: selectedOffering.identifier);
final typedWebLinks = await InappifySdk.getDiscountedPaymentLinksResult('SALE',
  offeringIdentifier: selectedOffering.identifier);
await InappifySdk.syncStorePurchases();
await InappifySdk.restoreStorePurchases();
await InappifySdk.syncPendingConsumables();
await InappifySdk.confirmDelivery(deliveryId);
await InappifySdk.setConsumableDeliveryHandler((delivery) async {
  await grantDurablyOnce(delivery); // host transaction unique by deliveryId and user/app
  return InappifyDeliveryResult.delivered;
});
await InappifySdk.setConsumableDeliveryHandler(null); // unregister
await InappifySdk.handleDeepLink('myapp://payment-return?...');
final allowedUrl = await InappifySdk.isPaymentUrlAllowed(paymentUrl);
await InappifySdk.setNetworkEnabled(false);
await InappifySdk.setNetworkEnabled(true);
```

The package supplies all purchase identifiers/classification. Android supplies its
Activity. No isCrypto, market/RSA, raw receipt or manual product-type arguments.

`offeringIdentifier` on the two discount methods is optional and selects the Web
offering only. Omission keeps the current Web offering. A supplied blank or invalid
identifier never falls back to another offering; validation does not replace the
current offering or cached catalog. The response remains `ValidateDiscountCodeData`,
including the discounted `offering`, `code`, `isValid`, `errorCode` and `paymentLinks`
when supplied by the provider. Android/iOS ignore this selector and retain their
existing code-only payment-link requests and responses.
Paywall ID/revision must be positive and supplied together. Retain a key only for
the same uncertain attempt. The existing Direct/store routes and results are preserved.

Register the Android delivery handler before configure. Return `delivered` only
after durable host fulfillment; return `retryLater` on failure. Kotlin owns the
acknowledgement and store consumption. Do not call confirmDelivery inside the
handler. Manual fulfillment remains available without a handler.

Android automatically recovers on configure/identity changes, foreground and
reconnect (pending work or five minutes elapsed), with thirty-second error backoff.
Marked return links enter the same native coordinator; ordinary links do not force
sync. Flutter forwards new Android intents without consuming host navigation.
The explicit `syncStorePurchases()` and `restoreStorePurchases()` methods remain parameter-free. Recovery is internal and automatic.

## Additional surfaces

`events`, `httpTraces`, `snapshot`, `customerInfo`, `offerings`, `lastFailure`,
`sessionStateChanges` and the existing read-only metadata getters remain available.
`getConfiguration()`/`getConfigurationResult()` expose token-free configuration.
Advanced mobile `customerInfoWithPolicy(InappifyFetchPolicy)` and
`offeringsWithPolicy(InappifyFetchPolicy)` remain, matching Kotlin's advanced API.
`isCustomerAnonymous(appUserIdentifier: value)` is a local identity helper.

Browser-specific Identity Ticket, OTP, checkout and return-polling functions retain
their existing contracts; see [Web](WEB.md). iOS retains its separate Direct
implementation; native combined sync and delivery handlers are Android-only.

Removed names: login/logout and their Result aliases, configureGoV2,
restoreCachedSessionResult, validateDiscountCode, checkEntitlement, updateAttributes,
deleteAttributes, queueAttributes, flushAttributes, syncAttributes,
setTargetingContext, and misspelled setDisplayname.

## Logging

```dart
await InappifySdk.setLogLevel(InappifyLogLevel.debug);
await InappifySdk.setLogHandler((level, message) { /* application logger */ });
await InappifySdk.setLogHandler(null); // restore the default console
```

Both methods return `Future<void>` and work before Configure. There is no
configure parameter. Levels are verbose/debug/info/warn/error; defaults are debug
in development and info in release/profile. This does not enable HTTP body logs,
network uploads or change purchase/cache/recovery behavior.
