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

### Ten-minute reconciliation and host purchase guards (0.2.7)

Android V2 schedules recovery for pending attempts after ten minutes, using the
existing serialized recovery coordinator. This applies to Myket, Bazaar and
Android Direct; each keeps its own verification/fulfillment contract. Recovery
can also run earlier on existing startup, lifecycle or explicit-sync triggers.
With unresolved work it schedules another check after ten minutes. The timer
runs only while the client is configured, foreground, online and network-enabled;
resume/reconnect restores scheduling. A stopped process cannot run the timer;
startup recovery reads retained evidence. No host polling loop is required.

The deadline never expires a receipt or converts PENDING to FAILED. Only matching
authoritative terminal results or proven pre-dispatch failure resolve an attempt.
Empty inventory, elapsed time, an unknown history lookup and a failed refresh
remain inconclusive. Confirmed cancellation permits a new explicit user action;
the SDK never automatically launches a replacement payment.

Host journals should isolate app/customer/protocol/product (and retain original
market/offering/package context). An uncertain product X must not globally block
product Y. A definite terminal failure of X can release X; a genuinely uncertain
X remains protected against a duplicate charge. Match the original attempt and
context before resolving its record; preserve other products and old evidence.
Keep unknown/corrupt legacy records conservative until their scope is established.
This host policy requires application changes separately from an SDK upgrade.

### Bazaar/Myket trial preflight (0.2.7)

The selected catalog package's trial days and cached customer eligibility guide
whether native billing first calls the existing authenticated purchase route.
The server is authoritative: DONE completes eligible trial activation without
paid UI; NEEDSTORE allows billing. Known ineligible customers/zero trial days
continue directly to billing; unknown metadata requires a server decision.
Uncertain trial checks retain their original key/package across restart and are
replayed before another charge. Do not call this endpoint directly from the host.
Deploy matching backend purchase behavior and the migration adding is_trial_check
to native_purchase_attempts before upgrading clients. This adds no host-facing
trial-only request flag and does not change iOS/Web payment flows.

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

## Myket product types and timed subscriptions

Kotlin v0.2.7 records MYKET_PURCHASE_PREPARING before billing setup and must
durably record MYKET_PURCHASE_DISPATCHED before launching the payment activity.
Blocking billing-support/buy-intent calls run off the UI thread; late responses
after timeout/close cannot launch UI. A proven pre-dispatch failure is terminal
with outcomeMayHaveCommitted=false. A history lookup after restart resolves
explicit interrupted preparation as MYKET_PURCHASE_NOT_STARTED and emits its
matching terminal update. This local reconciliation makes no network/store call.
Confirmed store cancellation is terminal. Dispatched/legacy unmarked uncertain
attempts remain pending. These Myket preparation rules do not alter Bazaar or
Direct billing callbacks. Never relabel an old unmarked attempt as preparation.

This Android path requires Flutter **0.2.7**, its pinned Kotlin **v0.2.7**, and a
compatible deployed V2 commerce backend. The [official Myket Java guide](https://myket.ir/kb/pages/java/)
documents consumable and non-consumable in-app purchases. Inappify implements
timed subscriptions on that in-app flow; do not promise Myket native subscriptions
or automatic renewal.

| Intended product | Inappify product type | Fulfillment |
| --- | --- | --- |
| Coins or repeatable inventory | `CONSUMABLE` | Verified delivery, durable host grant once, then SDK acknowledgement/consumption |
| Lifetime unlock | `NON_CONSUMABLE` | Server-granted access; do not consume the receipt |
| Time-limited access with manual renewal | `SUBSCRIPTION` | Consumable Myket SKU, server-managed entitlement duration, then SDK-owned consumption |

Use matching Myket/Inappify SKU identifiers, the configured Myket app/store route
and public RSA key, and the desired Offering package duration. Keep the original
catalog Package classified as `SUBSCRIPTION`; do not relabel it `CONSUMABLE` in
Flutter to bypass an older SDK error. Kotlin bills it as `IN_APP` while preserving
the subscription type and app/customer/purchase bindings in the payload.

Deploy the matching commerce backend before upgrading clients. After authoritative
verification and a committed entitlement grant, purchase/replay and asynchronous
verification-status responses must authorize consumption with
`requiresConsumption: true` and committed payment/event IDs. These are native/server
contract fields, not client-set purchase parameters. Missing authorization, pending
verification, or network/consume failure retains paid work for recovery; do not
clear the journal or start another charge as a workaround.

For Kotlin v0.2.7 recovery, the type recorded for the committed server purchase is
authoritative, even when an older pending operation says a different type. Do not
change catalog types or rebuild the Package to repair that operation. A later
catalog edit must not reinterpret an already committed permanent purchase.
The native coordinator validates `productType` (1 subscription, 2 consumable,
3 non-consumable), matching `source`/`productIdentifier`, payment/event IDs, and
consistent delivery state. Consumables additionally require `deliveryId` and
`alreadyDelivered`; a completed subscription requires `requiresConsumption: true`.
These checks are Myket-specific and must not change Bazaar or Direct semantics.

`alreadyProcessed: true` or HTTP 200 alone is not evidence that access/inventory
was delivered. With committed access, an older Myket subscription receipt can be
consumed without another grant or extension, even if that access has since expired.
For consumables, confirmed `alreadyDelivered` skips duplicate host delivery and
resumes only the remaining consumption work. Missing/mismatched evidence must
retain the receipt and pending operation for reconciliation.

Kotlin v0.2.7 / Flutter 0.2.7 compact Myket purchase metadata internally, preserving
the full recovery and server purchase bindings. Hosts must not build or rewrite
developer payloads. Older signed JSON receipts remain supported; Bazaar payloads
are unchanged. A conservative 256-byte UTF-8 budget applies only to Myket metadata,
not a documented universal store limit. `MYKET_PAYLOAD_TOO_LARGE` is rejected before
billing or a new native pending attempt, with `outcomeMayHaveCommitted=false`.
Use shorter offering/package identifiers or a short unique key for a genuinely new
attempt; never rewrite the key or context of an existing uncertain attempt.

If purchase fails before store UI, preserve the original attempt and inspect safe
`storeResponseCode`, `storeFailureStage` and `storeExceptionCategory` details.
Kotlin v0.2.7 retains these in durable attempt history. Stages distinguish `SETUP`,
`OPERATION_START` and `PURCHASE_CALLBACK`; exception categories are fixed labels,
not raw exception messages. An absent numeric code in older host/history logs does
not prove an exception: a logger may have discarded it. `PURCHASE_FAILED` alone
does not prove an unconsumed receipt, a wrong SKU, or a payload-size failure.
Diagnose the actual callback and inventory without tokens, signatures, keys,
developer payloads or raw receipt logs. An upgrade or empty inventory must not
automatically clear a host's uncertain attempt or launch another charge.

The native coordinator consumes and checkpoints this receipt without invoking the
host consumable delivery handler. Do not grant subscription time in that handler,
call `confirmDelivery` for it, or add a second Myket billing plugin. Read access and
expiry from verified CustomerInfo; consuming a receipt alone does not grant access.

Recovery and explicit restore can finish bound, unconsumed Myket subscription
receipts from IN_APP inventory. Replaying the same receipt must not extend access
again. An already-consumed receipt is absent from store inventory; refresh server
CustomerInfo and resume surviving paid checkpoints rather than promising inventory
restore will recreate it. Renewals are explicit new user purchases after any prior
uncertain attempt is resolved; the backend grants the configured term exactly once
for each verified purchase. Bazaar subscriptions and Direct flows retain their
existing behavior.

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
Subscriptions and non-consumables must never be delivered as host inventory credits.
Myket timed-subscription consumption is handled by the SDK as described above;
this host delivery recipe does not apply to it.

These native Dart recipes are unsupported on Flutter Web 0.2.7. Direct JS 0.2.0
has separate delivery APIs; see [Web](web.md). Do not call a second JS session
from Flutter to bypass its facade.
