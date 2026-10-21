# Stores, recovery, and consumable delivery

Bazaar and Myket purchases run only on Android and are delegated to the Kotlin SDK. Flutter does not call store inventory APIs itself. A receipt, store callback, cached snapshot, or return from a payment screen is not entitlement authority; Inappify verifies the evidence and the native SDK validates signed customer information.

| Market | Server configuration | Native session route | Supported products and inventory |
| --- | --- | --- | --- |
| Bazaar | `Bazar` | `Bazar` | Consumable, non-consumable, subscription; subscriptions and in-app inventory |
| Myket | `MyKet` | `MyKet` | Consumable and non-consumable; in-app inventory only |
| Direct | `DirectAndroid` | Platform-specific server direct route | Server checkout and delivery queue; no Bazaar/Myket UI |

Myket subscription purchases are unsupported and rejected before billing launch. Bazaar/Myket do not provide an iOS route in this plugin; iOS uses its existing Dart V2 direct implementation. There is no Google Play Billing or Apple StoreKit implementation in these store adapters.

## Store setup and purchase

Register the application package/signing identity and product SKUs in the chosen store. Configure the same application, offering, package, and product in Inappify; install the store application on the test device and sign in to an eligible store account. Store route and public RSA key are supplied by the verified server configuration. Use `FlutterFragmentActivity` for the Android host; both native stores require its activity-result registry. Native dependency, host activity, and manifest entries are described in [Android integration](ANDROID.md).

Pass the actual `PackageModel` from the selected Offering. It carries parent
Offering, package identifier, product identifier and server productType. A missing
native product classification is rejected; refresh the catalog instead of
inferring it from a price, name or package display type.

```dart
Future<InappifySdkResult<PurchaseResult>> purchaseStorePackage(
  PackageModel selectedPackage, {String? unresolvedAttemptId},
) => InappifySdk.purchaseResult(InappifyPurchaseParams(
  packageToPurchase: selectedPackage, idempotencyKey: unresolvedAttemptId));
```

Android supplies the attached Activity. Direct checkout and resuming a paid
attempt can proceed without store UI. The normal purchase API accepts no raw
receipt, market, billing key, discount amount, isCrypto or product-type override.

Omitting `idempotencyKey` creates a fresh logical attempt. Reuse a retained key only for the same unresolved attempt; typed failures carry its value in sanitized `details`. An uncertain outcome requires reconciliation before another payment. Product/offering/package/paywall attribution and receipt bindings prevent an existing key or receipt from being reassigned to a different purchase/customer.

The native SDK creates the store developer payload before billing, including the caller-supplied product category when present and scoped recovery/purchase bindings. It subsequently sends the original store receipt evidence to the V2 commerce service. Flutter neither hashes the store token nor rewrites a paid payload.

## Startup and foreground recovery

Configure after resolving the current application user on every application startup. Native configure schedules recovery for accepted online sessions and matching cached sessions; configure success does not await that background recovery. Flutter does not launch a separate inventory sync.

Android automatically recovers on foreground/reconnect when pending work exists
or five minutes have elapsed, backing off thirty seconds after errors. Recovery
is internal; no Flutter lifecycle call is required. For a manual purchase check:

```dart
final synced = await InappifySdk.syncStorePurchases();

// Call from a user-initiated Restore Purchases action.
final restored = await InappifySdk.restoreStorePurchases();
```

For a native Bazaar/Myket session, internal recovery resolves pending identity
transitions, refreshes CustomerInfo, resumes matching paid checkpoints, queries
owned inventory, reconciles delivery work, then refreshes Offerings. CustomerInfo
failure does not prevent the store attempt. Concurrent recovery requests share a
pass; there is no guaranteed recovery while the application is closed.

The renamed methods retain their existing results and behavior. On Android's
Direct route, they still reconcile the server consumable-delivery queue. The iOS
adapter retains its existing Direct delivery behavior and startup recovery; these
names do not add StoreKit support.

| Method | Purpose |
| --- | --- |
| `syncStorePurchases()` | Reconcile interrupted operations and owned inventory; refresh CustomerInfo after success |
| `restoreStorePurchases()` | Explicit restoration of subscriptions/known non-consumables; independent restored/already-processed/failed counts |
| `syncPendingConsumables()` | Return server-verified deliveries and reconcile pending consumption/checkpoints |
| `confirmDelivery(deliveryId)` | Acknowledge a committed durable host grant, then let native code consume/report |

Explicit restoration does not grant owned consumables as new inventory. Pending operations can still finish their original delivery flow. Cache-only reads and disabling HTTP do not prove that a payment was completed or eliminate pending paid work.

## Duplicate checks and renewals

Bazaar queries Poolakey `getSubscribedProducts`, then `getPurchasedProducts`. Myket queries its in-app inventory. Native code resumes matching paid checkpoints before applying an entitlement shortcut.

Automatic sync skips a newly discovered non-consumable/subscription only when freshly verified CustomerInfo contains both `purchaseStoreRefHash == SHA256(UTF8(purchaseToken))` as lowercase hexadecimal and `purchaseStoreTime == purchaseTime` as the exact millisecond value. `isActive` is not part of that comparison. Consumables and unknown in-app categories still require server verification. Explicit restore forwards eligible receipts instead of using this automatic shortcut.

A subscription with the same token but a new purchase time is a separate occurrence, with a scoped local renewal checkpoint when needed; the older paid operation is preserved. If the store returns both the same token and time for a renewal, this comparison cannot distinguish it. The backend/store must provide renewal validation and idempotency. Already-consumed receipts absent from inventory require a surviving paid checkpoint or server delivery record.

For a bound subscription receipt, missing/null/blank `productType` can be inferred from the genuine subscription query. Unknown in-app receipts cannot distinguish consumable versus non-consumable locally. Contradictory explicit types and malformed payloads are rejected. Legacy receipts without valid app/customer binding are not automatically relabeled to the currently configured account.

## Bazaar subscriptions without a payload

Bazaar payloadless-subscription recovery remains enabled by the native SDK;
there is no public Flutter Configure toggle. It uses the existing server-linked
subscription recovery path and never invents a new customer/package binding.

The native client sends this evidence to `POST https://api.inappify.com/app/v2/store/subscriptions/recover` using the current session token as Bearer authentication. The request contains `productIdentifier` and the original `purchase` evidence. It does not choose a replacement offering/customer/package or send an API key in the body. The backend must independently verify the store receipt and resolve its previously established owner and product linkage.

Set the configure flag to `false` when that backend capability is unavailable. This stops discovery/registration/polling of the optional payloadless operation, preserves existing checkpoints, and leaves ordinary bound-receipt recovery active. Re-enabling the flag resumes its retained work. A backend without the route is an integration failure; the SDK does not downgrade to an unbound purchase grant.

The current native journal can contain `RECOVER_SUBSCRIPTION`. A client that cannot decode that operation is not a supported downgrade target. Changing a repository, artifact, or version does not rename the persisted native session/journal namespaces or transfer another user's receipts.

## V2 commerce contract

The default commerce root is `https://api.inappify.com/app/v2/`. All routes in this table are native-owned `POST` operations and use the current matching session's Bearer token. No legacy customer token/API key is placed in store request bodies.

| Relative route | Body |
| --- | --- |
| `store/purchases` | Product/offering, `operation` (`purchase` or `restore`), original `purchase` receipt evidence |
| `store/subscriptions/recover` | Product identifier and original receipt evidence; no offering/operation fields |
| `store/verifications/{verificationRequestId}/status` | `{}` |
| `store/deliveries/{deliveryId}/delivered` | `{}` |
| `store/deliveries/{deliveryId}/consume-result` | Consumption result and optional error code |

The native coordinator persists paid evidence before registration and checkpoints registration, verification, delivery, acknowledgement, consumption, and reporting. Network errors, authorization failure, and unresolved verification preserve pending work. The coordinator owns bounded retries and resume; the host must not blindly retry a new purchase after a network timeout.

## Grant consumables durably, then confirm

`PurchaseResult.mobile` exposes workflow state such as `deliveryRequired`; this is distinct from final legacy purchase success. `syncPendingConsumables` returns server-authoritative deliveries with delivery ID, product, and source. Flutter exposes the native delivery handler as well as the existing manual fulfillment methods. Register the handler before configure; return delivered only after the durable grant commits, or retryLater on failure. Do not call confirmDelivery inside the handler.

```dart
import 'package:inappify_sdk/inappify_sdk.dart';

Future<void> fulfillPendingConsumables(
  Future<void> Function(InappifyConsumableDelivery delivery) grantOnce,
) async {
  final synchronized = await InappifySdk.syncPendingConsumables();
  if (!synchronized.isSuccess) return;
  for (final delivery in synchronized.data!.pendingDeliveries) {
    // This callback must commit a durable, idempotent inventory transaction.
    await grantOnce(delivery);
    final acknowledged = await InappifySdk.confirmDelivery(delivery.deliveryId);
    if (!acknowledged.isSuccess) {
      // Retain the committed grant; a later retry must not grant it again.
      return;
    }
  }
}
```

Implement `grantOnce` with a durable uniqueness key scoped by application, current customer, delivery source, and delivery ID, and guard asynchronous work against account changes. Commit inventory before confirming. A failed confirmation must not cause a second grant. Native code persists acknowledgement, notifies Inappify, consumes only consumable receipts, then persists/reports the result. It never consumes subscriptions/non-consumables or chooses the host's credit amounts.

## Limits and real-device testing

Bazaar's query adapter collects callback pages until a two-second idle window and deduplicates by token. Arbitrarily delayed pages are not guaranteed to be included. Myket has no subscription query in this SDK, serializes billing helper operations, and bounds them with a 120-second timeout; the coordinator separately bounds store consumption to 30 seconds.

Build/bridge tests validate code and protocol integration; they are not proof of live store renewal, backend ownership linkage, or fulfillment. Test the final store-specific APK with its registered package/signing identity, store account, canceled payment, interrupted verification, account changes, explicit restore, and durable consumable delivery. The host is responsible for triggering foreground recovery and committing inventory transactions.

See [native recovery details](https://github.com/InappifyLabs/kotlin-sdk/blob/v0.2.0/docs/RECOVERY_AND_CACHE.md), [Flutter API](API_REFERENCE.md), and [Android integration](ANDROID.md).

## Automatic native delivery callback

```dart
await InappifySdk.setConsumableDeliveryHandler((delivery) async {
  await grantDurablyOnce(delivery); // unique deliveryId within the app/customer
  return InappifyDeliveryResult.delivered;
});
await InappifySdk.configure(apiKey: 'public_app_key');
// After a fresh consumable purchase, request immediate delivery if needed:
await InappifySdk.syncPendingConsumables();
```

Kotlin acknowledges only explicit delivered results and keeps its existing store
consumption sequence. Host errors, missing handlers and engine detach remain
pending. Callback retries can repeat: inventory uniqueness must be durable.
Without a handler, manually grant a returned pending delivery and then call
confirmDelivery(deliveryId). Do not mix competing automatic and manual grant paths.

Only marked InAppify return URLs trigger forced native recovery. Android initial
and new intents are forwarded automatically; custom routing can also call
handleDeepLink(url). Flutter navigation remains host-owned.
