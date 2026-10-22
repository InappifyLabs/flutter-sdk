# Purchase, recovery, and consumable delivery

Load this file before changing purchase/retry buttons, payment returns, pending
attempt records, inventory grants, or restore UI. Check [platforms](platforms.md)
first: Android outcomes/history, iOS Direct, and Web checkout are distinct flows.

## Start one logical purchase

1. Configure the intended app/customer. Obtain the selected offering through the
   SDK and retain its original Package. Do not silently fall back to a different
   offering when an explicitly selected ID is absent.
2. Persist a host attempt record before purchase when restart-safe correlation is
   required: attempt key, app/customer, source/market where known, product,
   offering/package, and pending state. Preserve any existing host journal.
3. Call `purchaseResult(InappifyPurchaseParams(packageToPurchase: package,
   idempotencyKey: savedKey))` once for that logical attempt. Prevent duplicate
   taps while it is in progress. Do not invent a new key on network timeout.
4. Inspect both typed failure and `PurchaseResult`: a successful SDK call may
   require browser payment, verification, delivery, or consumption. Do not grant
   merely because `isSuccess` is true or `data` is non-null.
5. Route fulfillment by product and workflow. Read verified CustomerInfo for
   subscription/non-consumable access. Grant consumables only through a verified
   delivery and a durable host inventory transaction.

`paywallId`/`paywallRevision` are optional paired presentation context, not client
price overrides. The server remains authoritative for amount, discount, product
membership, receipt verification and ownership.

## Android: native purchase and attempt correlation

For Bazaar/Myket the Flutter host Activity must extend `FlutterFragmentActivity`;
the plugin supplies the foreground Activity to Kotlin. Preserve the existing
package name and host integrations when changing `MainActivity`. No Activity is
passed from Dart. A detached/background engine cannot launch store UI.

Subscribe early to `InappifySdk.purchaseUpdates`. The stream contains
`InappifyPurchaseAttempt` with `attemptId`, product/offering/market,
`status` (`pending`, `succeeded`, `failed`), optional `purchase`, and `failure`.
The original idempotency key identifies the attempt. Events may repeat or be
missed while the app is closed; use native history after configure as well.

```dart
Future<void> inspectAndroidAttempt(String savedAttemptId) async {
  final lookup = await InappifySdk.getPurchaseAttempt(savedAttemptId);
  if (!lookup.isSuccess) return; // retain host record; inspect failure
  final attempt = lookup.data;
  if (attempt == null) return; // unknown, not failed
  if (attempt.attemptId != savedAttemptId) return;
  switch (attempt.status) {
    case InappifyPurchaseAttemptStatus.pending:
      break; // still unresolved; no second payment
    case InappifyPurchaseAttemptStatus.succeeded:
      // Correlate to the saved context, then read access / delivery workflow.
      // This history entry is not current entitlement authority.
      break;
    case InappifyPurchaseAttemptStatus.failed:
      // A matching terminal failure can be shown to the user.
      // Any new purchase remains an explicit new user action.
      break;
  }
}

Future<void> inspectAndroidHistory() async {
  await InappifySdk.getPurchaseAttempts();
}
```

History is encrypted and scoped to the current app/customer/market; lookups make
no network or store request. It survives process recreation, with bounded
retention (256 latest terminal results and up to 256 pending attempts). It is not
an unlimited transaction ledger. Missing data is never proof of no charge.

The event envelope also exposes `purchaseAttempt` and uses the attempt ID as
`requestId` for these purchase/recovery outcomes. Match the logical attempt **and
its saved context**, never just the SKU or newest event. Ignore unrelated
successes; don't clear another user's unresolved record after login/logout.

Android Direct purchases also retain the original bound attempt through new
backend payment/status support and native recovery. Old payments without that
binding keep their legacy behavior; don't infer the association by product.
Do not add backend routes or deploy/migrate servers as part of host integration.
Confirm compatible services when diagnosing missing Direct correlation.

## Automatic versus manual recovery

| Operation | Developer responsibility |
| --- | --- |
| Internal Android recovery | Already runs after configure/logIn and on foreground/reconnect when pending or 5 min elapsed; error backoff at least 30 s. Do not add a duplicate host loop. |
| `syncStorePurchases()` | User retry/reconciliation of interrupted operations and owned store inventory when needed; inspect matching results/history, not only an empty list. |
| `restoreStorePurchases()` | User-initiated restoration of eligible subscriptions/non-consumables; inspect restored/already-processed/failed counts. |
| `syncPendingConsumables()` | Reconcile verified deliveries and pending consumption/checkpoints; does not itself invent host inventory. With an Android handler it can invoke fulfillment. |
| `confirmDelivery(int deliveryId)` | Manual assertion that the matching durable host grant has committed. |

There is **no public `recover`**. Don't call sync/restore on every rebuild, launch,
or arbitrary deep link to imitate it. SDK-managed recovery keeps original paid
operations; restoring must not grant an owned consumable again.

Android initial/new intents already forward marked Inappify payment-return links.
Custom routing can call `handleDeepLink(url)` when appropriate. An arbitrary
deep link must not force recovery. Do not manufacture the marker or treat its
presence as proof of successful payment. Navigation is still host-owned.

## Direct payment on iOS

iOS uses Dart mobile V2 and Direct payments only. It has no StoreKit/Bazaar/Myket
inventory queries and no durable Android attempt-history API. Its purchase
idempotency key is local result/failure correlation in this release; it is **not
sent in its Direct purchase request**. Do not promise server deduplication or
resolve an uncertain attempt by blindly replaying purchase with that key.

Purchase can return `NEEDTOPAY` and a URL or `DONE`. Host navigation opens only a
validated payment destination. Mobile `isPaymentUrlAllowed(url)` recognizes the
Direct HTTPS destination policy (`pay.inappify.com`, no credentials, default/443
port); use its typed result instead of opening arbitrary server/user text.

```dart
Future<String?> allowedMobilePaymentUrl(String url) async {
  final checked = await InappifySdk.isPaymentUrlAllowed(url);
  return checked.isSuccess && checked.data == true ? url : null;
}

Future<bool> refreshIosAccess(String entitlementId) async {
  final result = await InappifySdk.getCustomerInfoResult(
    fetchPolicy: InappifyCacheFetchPolicy.fetchCurrent,
  );
  return result.isSuccess &&
      result.data?.entitlements.active.containsKey(entitlementId) == true;
}
```

Internal iOS startup recovery exists. The adapter does not install Android's
foreground/connectivity observers. On a relevant host payment-return/resume,
request fresh CustomerInfo and manually reconcile Direct deliveries when needed.
A failed refresh is not proof that a purchase failed. Do not call Web checkout
status/polling methods or a removed `recover` method on iOS.

The iOS methods named `syncStorePurchases`/`restoreStorePurchases` currently
reconcile Direct pending deliveries; restore reports zero restored store receipts.
Do not label that UI as App Store restoration. Automatic delivery-handler
registration is unsupported there; use the manual flow below.

## Durable consumable fulfillment

Choose **one** owner for a delivery: registered Android handler or manual native
sync/grant/confirm. Never let both paths independently credit the same delivery.
The durable grant must include a unique key scoped by app, original customer,
delivery source and delivery ID, with inventory and deduplication committed in
the same transaction. A memory set, widget flag, or SharedPreferences marker
separate from the inventory transaction is not a durable exactly-once grant.

The `grantOnce` callback in these examples is implemented by the host. It must
bind/check the intended customer inside its transaction and succeed without a
second credit when the same delivery was already granted. Quiesce delivery work
before account transitions; retain unresolved work under its original owner.

```dart
Future<InappifySdkResult<void>> registerAndroidDelivery(
  Future<void> Function(InappifyConsumableDelivery) grantOnce,
) {
  return InappifySdk.setConsumableDeliveryHandler((delivery) async {
    try {
      await grantOnce(delivery);
      return InappifyDeliveryResult.delivered;
    } catch (_) {
      return InappifyDeliveryResult.retryLater;
    }
  });
}
```

Register before configure on Android. The SDK acknowledges after the callback
returns `delivered`; **never call `confirmDelivery` inside that handler**. Missing
handler, callback error, retryLater or engine detach leave delivery pending.
Remove a handler with `setConsumableDeliveryHandler(null)` when appropriate.

Manual flow for iOS Direct or Android without a competing handler:

```dart
Future<void> fulfillNativeManually({
  required Future<void> Function(InappifyConsumableDelivery) grantOnce,
  required bool Function() stillSameCustomer,
}) async {
  final synchronized = await InappifySdk.syncPendingConsumables();
  if (!synchronized.isSuccess || !stillSameCustomer()) return;
  for (final delivery in synchronized.data?.pendingDeliveries ??
      <InappifyConsumableDelivery>[]) {
    if (!stillSameCustomer()) return;
    await grantOnce(delivery);
    if (!stillSameCustomer()) return;
    final acknowledged = await InappifySdk.confirmDelivery(delivery.deliveryId);
    if (!acknowledged.isSuccess) return; // retain committed grant, never re-credit
  }
}
```

Host identity checks complement, not replace, the inventory transaction's owner
check. Do not confirm another customer's delivery after an awaited callback.
Subscriptions and non-consumables must never be consumed as credits.

These native Dart recipes are unsupported on Flutter Web 0.2.2. Direct JS 0.2.0
has separate delivery APIs; see [Web](web.md). Do not call a second JS session
from Flutter to bypass its facade.
