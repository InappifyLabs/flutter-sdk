# Migration review and skill validation

## Replacing host integration code

Inspect the actual receiver before renaming a method. A host wrapper such as
`InappifyCustomerCatalogService.getCurrentOffering(refresh: ...)` can still have
its own argument even when the SDK doesn't. Trace what the wrapper invokes;
remove or adapt the host option only with its callers accounted for. Do not
announce that an SDK flag exists solely from a host wrapper signature.

| Legacy/new integration temptation | Correct treatment for Flutter 0.2.6 |
| --- | --- |
| `login` / `logout` | Public facade uses `logIn` / `logOut` and their typed variants; Web uses ticket/OTP, not plain ID login |
| Market/RSA/app version passed to ordinary configure | `configure(apiKey:, appUserIdentifier:)`; metadata/server supply native context |
| `getCurrentOffering(refresh: true)` / force/context | Ordinary read has only optional placement; supported mobile manual refresh uses combined sync |
| Public `recover` / per-launch host store sync | Recovery is internal on Android; keep manual sync/restore for explicit supported purposes |
| `syncPurchases` / `restorePurchases` | Current Flutter names `syncStorePurchases` / `restoreStorePurchases`; iOS is Direct reconciliation, not App Store restore |
| `validateDiscountCode` at facade | `getDiscountedPaymentLinks` / `...Result`; optional Web offering selector; direct JS still uses its own `validateDiscountCode` |
| Public queue/flush/sync/delete attribute methods | Use `setAttributes` Map, null/empty for deletion; SDK owns queue and sync |
| `checkEntitlement(forceRefresh: ...)` | Read CustomerInfo under intended supported policy, then active entitlements / synchronous helpers |
| Reconstructed purchase from IDs/display fields | Pass the actual catalog Package through `InappifyPurchaseParams` |
| Treat any success event/empty sync as resolving the last payment | Match original attempt and scope; unknown/unrelated outcomes retain pending host record |

Do not modify SDK private APIs, server contracts, caches, retry scheduling or
durable paid work during a host rename. Legacy JS options intentionally remain
valid in Web 0.2.0; the Flutter migration table is not a removal plan for JS.

## Validation of a host change

Use proportionate analyzer/compiler and focused tests with fakes. Exercise the
target backend contract, not only a fake universal facade:

- Startup with retained identity and known host-user transition; no cross-user
  snapshot, pending checkout or inventory leakage.
- Default offering, placement selection, exact ID absent, and empty packages.
- Cache-only versus network failure on each backend. Flutter Web 0.2.2 forwards
  all four policies; older 0.2.1 did not. Exercise the real published provider,
  pending-network cache-only, background refresh and account transition safety.
- One purchase tap, cancellation, timeout/offline, process restart, unknown
  attempt history, matching outcome, unrelated event, changed customer, repeated
  event. No second charge or erased unresolved journal from uncertainty.
- Direct redirect and return: preserve correlation, no grant from query status,
  authoritative status/access; iOS cannot use Web checkout APIs.
- Consumable grant commits once, confirm fails, restart/retry, duplicate delivery,
  account change and missing handler. Inventory must not be credited again.
- Myket timed subscription: matching SUBSCRIPTION catalog product uses IN_APP;
  committed server authorization precedes consumption, pending/old-backend responses
  preserve receipts, consume retry/restart never grants another term, and no host
  delivery handler runs. Recheck ordinary Myket consumables/lifetime access and
  existing Bazaar, Direct, and legacy V1 behavior when changing SDK/service code.
- Explicit Web discount offering different from default; omitted selector;
  blank/invalid selector with no fallback; discounted catalog remains separate.
- Combined sync Android/iOS: attributes before offerings, empty queue still
  fetches, failed admitted calls count, sixth call cache/no network or no-cache
  error, rolling-window recovery, user switch retains quota and isolates cache.

Do not send real OTPs, create paid transactions, or query private customer data
for routine verification. A live store/device matrix is a separate authorized
integration test. Report what was tested and what could not be verified.

## Decision scenarios for maintainers

Use these prompts to review a revised skill. Expected decisions are the rubric;
these are not assertions that an autonomous agent evaluation was executed.

| Prompt | Required decision |
| --- | --- |
| "Add purchases to Flutter Android 0.2.6; app uses FlutterActivity." | Preserve host integrations, require FlutterFragmentActivity for store UI, use Package and Result; no Dart Activity argument. |
| "Refresh targeting on iOS; no attributes changed." | Combined sync is supported; fresh offerings still fetched subject to 5/60 quota; no duplicate flush. |
| "JS 0.2.0 is loaded; call combined sync from Flutter Web 0.2.6." | Use the supported facade and existing provider, subject to its 5/60 quota; no second JS session. Older Flutter 0.2.1 lacked this bridge. |
| "Use cacheOnly offline on Flutter Web 0.2.6." | Forward cacheOnly: no HTTP or wait for pending HTTP; return CACHE_MISS if absent. Older Flutter 0.2.1 ignored the policy. |
| "Login this PWA by customer ID." | Use backend ticket/authenticated helper or OTP; no client-created ticket/server secret. |
| "After Android restart lookup returns successful null; retry payment now." | Unknown; retain attempt/context, reconcile matching native result; no automatic new charge. |
| "Retry iOS Direct using the same key guarantees no duplicate." | Reject guarantee: local correlation only; reconcile before another payment. |
| "Confirm coins immediately on DELIVERY_REQUIRED." | Grant durably once first; then handler delivered OR manual confirmation; no double grant. |
| "Myket is installed but Flutter 0.2.2 rejects subscriptions." | Explain the older-version gate; recommend the coordinated Flutter 0.2.6/Kotlin v0.2.6 and compatible backend, matching consumable Myket SKU with Inappify SUBSCRIPTION and package duration. Do not relabel the catalog or promise automatic renewal. |
| "Consume a Myket subscription immediately after the store callback." | No host consume: await verified server grant and native consumption authorization; SDK handles consumption/retry without a host inventory delivery. |
| "An old Myket receipt is already processed but local type differs." | Use the coordinated 0.2.6/v0.2.6 recovery contract and matching backend; retain the journal, require matching scope and committed server type/delivery evidence, and never grant/extend twice. |
| "Consume every Myket receipt to unblock another purchase." | Never consume recorded NON_CONSUMABLE purchases. Subscription consumption requires committed access; consumables require confirmed delivery. Do not infer either from HTTP 200 or alreadyProcessed alone. |
| "Change Bazaar and Direct to follow the Myket cleanup rule." | Keep their existing fulfillment and recovery contracts; this change is Myket-specific. |
| "Old backend omitted requiresConsumption; clear pending work and buy again." | Preserve the original receipt/attempt, deploy compatible backend and reconcile; no second charge or client-forged authorization. |
| "Restore iOS App Store subscription using restoreStorePurchases." | No StoreKit in this backend; Direct-delivery reconciliation only. |
| "Discount upgrade placement, default offering is different." | Pass selected offering ID; no default fallback; use returned priced offering/code in Web checkout. |
| "Remove old JS forceRefresh, logout, ID-based purchase." | Retain compatibility; prefer new semantic forms only for new integration code. |
| "Reset storage after network error and configure every foreground." | Preserve session/journal/cache; no resets, no competing Android recovery loop. |

## Updating the official skill

Keep `SKILL.md` short and load reference files by task. For each SDK release:

1. Pin released versions/source tags in `platforms.md`; retain known commit IDs.
2. Inspect facade signatures, coordinator gates, inherited defaults, advertised
   operations **and implementations**. An enum alone proves neither support nor
   absence; exact offering lookup is a shared inherited implementation.
3. Check purchase/delivery models and backend request payloads before claiming
   idempotency or recovery behavior, especially iOS versus Android Direct.
4. Reconcile README/docs with source; don't copy obsolete snippets into the skill.
5. Type-check Dart/TS examples against the pinned packages without making network
   mutations. Review scenario decisions above; report actual evaluation scope.
6. Run the skill-creator validator when available, check local reference links,
   and review changes for secrets/private paths. Never rewrite past version
   claims just to say "latest".

This skill has no production-access dependency and no installation side effects.
Keep publishing, backend deployment and credential handling outside its ordinary
integration workflow.
