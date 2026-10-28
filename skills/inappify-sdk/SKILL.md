---
name: inappify-sdk
description: "Integrate, migrate, or troubleshoot Inappify SDK sessions, offerings, attributes, discounts, entitlements, purchases, payment returns, consumable delivery, and recovery. Use for Flutter inappify_sdk 0.2.7 on Android/iOS/Web, Kotlin v0.2.7, and @inappifylabs/web-sdk 0.2.0, including Myket manually renewed timed subscriptions. Also integrate PWA host backends with server-to-server identity tickets, subscriber APIs, offerings, promotional grants, and assigned discount codes. Distinguishes platform support, cache policies, identity authentication, and uncertain purchase handling."
license: Apache-2.0
---

# Inappify SDK

Help a developer integrate the SDK through its public API or connect a trusted
host backend through the documented server-to-server API. This skill is
versioned integration guidance, not an MCP server or a payment execution tool.
It needs no account credentials, live production access, or extra MCP connection.

## PWA host backend and server-to-server API

For host backend authentication, Identity Ticket issuance, server customer reads
or attributes, per-app offerings/overrides, promotional entitlements, or assigned
discount codes, read [server-to-server integration](references/server-to-server.md).
It documents exact routes, abilities, headers, payloads, responses, retry behavior,
and current backend limitations. For browser session/checkout code, also read
[Web integration](references/web.md). Server-only tasks do not require installing
or upgrading a client SDK; establish the deployed backend contract instead.

The production API origin is `https://api.inappify.com` (user-confirmed).
When asked for ticket issuance, provide the full URL:
`POST https://api.inappify.com/api/web/v1/server/identity-tickets`.
Use another origin only for an explicitly configured alternative environment.

Use the project secret only in the host backend. The browser receives a short-lived
ticket and uses the Public Web App Key and SDK-owned session. Promotional grants
can extend access again on retry, and server offering overrides currently do not
automatically control Web SDK offering selection. Do not infer guarantees from
endpoint names; use the reference's source-backed behavior.

## Establish the SDK contract first

1. Inspect the host's dependency declarations **and resolved versions**:
   `pubspec.yaml`/`pubspec.lock`, the Android SDK dependency, and the browser host's
   `package.json`/lockfile. Distinguish Flutter's version from its JS provider.
2. Identify the actual target: Flutter Android, Flutter iOS, Flutter Web/PWA, or
   direct JavaScript. Read [versions and platforms](references/platforms.md)
   before proposing platform-dependent behavior. Guard Web before using native
   platform checks; do not introduce `dart:io` into browser code.
3. Use this baseline for Flutter **0.2.7**, Kotlin **v0.2.7**, and Web
   **0.2.0**. Verify the host's resolved artifacts before recommending an
   upgrade. For another version, inspect that version's public source/types and
   report differences. Do not silently upgrade dependencies or assume a method's
   presence in the facade proves backend support.
4. Trace the host's existing session owner, account transitions, selected
   Package, pending-purchase journal, durable inventory, and return routing.
   Extend that integration; do not create a competing SDK session or cache.
5. Prefer `*Result` methods in Flutter wherever failure, an unknown result, or
   reconciliation matters. `isSuccess` describes the SDK operation, not a paid
   purchase or a completed inventory grant. Inspect `data`, `failure`, and
   `snapshot`; a successful nullable lookup can mean no result.

When repository prose conflicts with tagged public code, the resolved source and
backend implementation win. The references document known gaps in the 0.2.7 Web
adapter; do not implement speculative workarounds in its private internals.

## Android store packaging

For store rejection, billing permissions, Poolakey or channel builds, read
[Android store packaging](references/android-stores.md). Flutter/Kotlin 0.2.7
select native code, dependencies and permissions at build time using the Gradle
property `inappifyStore=myket|bazaar|direct|allStores` (`allStores` is the default).
The server API key selects runtime billing, not APK contents. `--dart-define`
and the host's `--flavor` alone do not set this property. Require the matching
runtime app key, and preserve pending purchases when changing channels.

## Choose the method by intent

| Developer intent | Public method / route |
| --- | --- |
| Start or restore a mobile session | `configureResult(apiKey: ..., appUserIdentifier: ...)`; identifier optional |
| Switch mobile customer / end session | `logInResult(id)` / `logOutResult()` |
| Authenticate a host user on Flutter Web | `configureAuthenticatedWebSessionResult(...)` with a fresh backend ticket; alternatively ticket exchange or OTP |
| Display current / placed / exact offering | `getCurrentOfferingResult()`, `getCurrentOfferingResult(placementIdentifier: ...)`, `getOfferingResult(id)` |
| Read the catalog | `getOfferingsResult()`; use model helpers for existing data |
| Update customer properties | `setAttributesResult(Map<String, String?>)`; null/empty deletes; reserved setters use supported keys |
| Refresh after attribute-based targeting changes | `syncAttributesAndOfferingsIfNeeded()` on Android/iOS/Web; Flutter Web 0.2.2–0.2.7 requires JS provider 0.2.0+ and its method capability |
| Read access | `getCustomerInfoResult(fetchPolicy: ...)` on Android/iOS/Web; default `cachedOrFetched`, then `entitlements.active`; synchronous helpers read the current mirror |
| Purchase | `purchaseResult(InappifyPurchaseParams(packageToPurchase: selectedPackage, ...))` |
| Validate a discount | `getDiscountedPaymentLinksResult(code, offeringIdentifier: ...)`; explicit offering selects Web pricing only |
| Reconcile an uncertain Android attempt | `getPurchaseAttempt(savedId)`, `purchaseUpdates`, and user-initiated `syncStorePurchases()` when needed |
| Explicit Android store restore | `restoreStorePurchases()` from a user action |
| Deliver consumables | Android registered delivery handler **or** supported native manual sync/grant/confirm; use the platform-specific route |
| Verify Flutter Web payment return | `getCheckoutStatus(checkoutId: ...)` or `handlePaymentReturnResult(...)` |

Read [Flutter API and defaults](references/flutter-api.md) for signatures and
examples. Read [purchases and recovery](references/purchases.md) **before changing
purchase buttons, retries, attempt journals, returns, or fulfillment**. Read
[Web integration](references/web.md) for browser startup, Identity Ticket/OTP,
checkout, direct JS APIs, and adapter gaps. Read
[migration and validation](references/migration-and-validation.md) when replacing
legacy calls or reviewing generated integration code.

Android 0.2.7 schedules pending-purchase reconciliation after ten minutes while
foreground and connected; it defers to resume/reconnect when unavailable. This
is a recovery deadline, never an expiry or permission to charge again. Terminal
matching cancellation/failure can release that product; unknown outcomes retain
their evidence. Scope host purchase guards by app/customer/protocol/product so
one unresolved product does not block unrelated products. Updating the SDK does
not change an application's own journal or purchase-button policy. Read the
purchase reference for Myket preparation markers and trial/backend prerequisites.

For Flutter Web 0.2.2–0.2.7, forward all four CustomerInfo policies through the facade;
`cacheOnly` never waits for pending HTTP. Combined sync uses the existing JS
instance and its five-admission rolling 60-second quota; admitted failures count.
Inspect `failure.details['serverCode']` for `CACHE_MISS` or
`RATE_LIMITED_NO_CACHE`, with numeric `retryAfterMillis` for the latter. A retained
snapshot does not turn a failed fresh fetch into success. Flutter Web 0.2.1 lacked
combined sync and policy forwarding; do not apply the new contract to that version.

## Non-negotiable integration rules

- Keep one SDK session owner. Use the Flutter facade; do not call MethodChannels,
  `src/` classes, Go/Laravel endpoints, or a second JS instance to bypass a
  missing Flutter operation. This does not prohibit the documented trusted host
  backend server-to-server integration above. A new SDK capability requires an
  explicit SDK task.
- Configure once per application session. Configure already owns startup
  prefetch/recovery. Do not pre-warm offerings in Android `Application.onCreate`,
  repeat configure from widget builds, or install duplicate Android recovery
  timers/foreground/connectivity loops.
- Preserve cache namespaces, signed data, identity scope, retry/backoff, queues,
  quarantine, journals, and payment logic. Do not clear SDK storage to fix a
  timeout, rewrite snapshots, or add a host entitlement cache as a migration fix.
- Use SDK/server anonymous identities. Omitted mobile identity can restore a
  retained signed-in customer; it is not logout. Do not relabel paid work to the
  newly logged-in user. Guard host async grants/UI against account changes.
- Keep the **original catalog Package** with product, package, type and parent
  offering context. Do not reconstruct it from a title, amount, product ID alone,
  discounted display row, or a guessed default offering.
- Preserve an uncertain purchase's original attempt key and context across
  restart. Timeout, offline state, cancellation of a waiter, an empty sync result,
  unknown lookup, identity change, or unrelated event must not clear that record
  or automatically launch a second payment. iOS does not have Android's durable
  attempt-history API or server-bound attempt guarantee.
- Payment URL/query parameters, app foreground, checkout creation, and an event
  without matching attempt evidence are not proof of payment. Obtain authoritative
  status/access through the supported platform flow.
- Grant consumables exactly once in durable host inventory, scoped by app,
  customer, source and delivery ID. Only then return `delivered` from a registered
  handler **or** call `confirmDelivery` in a manual flow. Never confirm inside the
  registered handler. A failed acknowledgement must not grant again.
- Never consume receipts from host code or restore consumables as fresh inventory.
  Bazaar subscription/non-consumable receipts remain unconsumed. Myket timed
  subscriptions use IN_APP receipts: Kotlin v0.2.7 follows the server's recorded
  purchase type, consuming subscriptions only after a committed entitlement grant
  and consumables only after confirmed delivery. Never consume NON_CONSUMABLE,
  including during legacy recovery. Already granted purchases must not extend
  access or deliver inventory again. Subscriptions do not use the host consumable
  handler. Read the Myket section in
  [purchases and recovery](references/purchases.md). `DELIVERY_REQUIRED`/
  `CONSUME_REQUIRED` are workflow states, not a completed host grant. Purchase
  history is not current entitlement authority.
- Trust server prices and verified CustomerInfo. Do not calculate a purchase
  discount locally, turn a network error into "invalid code", infer lifetime
  access merely from a null expiry, or promise offline revocation/clock-tamper
  protection beyond the installed SDK.
- Use public app keys on clients and the **Public Web App Key** in browsers.
  Never request, embed, print, or persist server secrets, raw session tokens,
  tickets, receipts or full customer payloads in diagnostics. Do not fabricate
  Identity Tickets in frontend code or replay a one-time ticket after uncertainty.
- Do not invent RevenueCat APIs because names look similar. In Flutter 0.2.7
  there is no public `recover`, `refreshOfferings`, `checkEntitlement`, standalone
  attribute queue/flush/sync, or `setTargetingContext`. No `refresh`/`forceRefresh`
  belongs on its `getCurrentOffering`.
- Do not publish packages, deploy backends, run production migrations, create
  real payments, send OTPs, or change dashboard configuration as an incidental
  integration step. Do those only when the user authorizes that work.

## Finish with evidence

Verify compilation/analyzer and focused host tests using fakes; exercise the
changed platform path. For store/device-only behavior, state what remains
unverified. A Dart or JS type check is not proof of a live purchase or fulfillment.
Report resolved SDK versions, platform-specific choices, preserved recovery/data
behavior, and any unsupported feature. Keep the explanation in the user's language.
