---
name: inappify-sdk
description: "Integrate, migrate, or troubleshoot Inappify SDK sessions, offerings, attributes, discounts, entitlements, purchases, payment returns, consumable delivery, and recovery. Use for Flutter inappify_sdk 0.2.1 on Android/iOS/Web and @inappifylabs/web-sdk 0.2.0. Distinguishes platform support, cache policies, identity authentication, and uncertain purchase handling."
license: Apache-2.0
---

# Inappify SDK

Help a developer integrate the released SDK through its public API. This skill is
versioned integration guidance, not an MCP server or a payment execution tool.
It needs no account credentials, live production access, or extra MCP connection.

## Establish the contract first

1. Inspect the host's dependency declarations **and resolved versions**:
   `pubspec.yaml`/`pubspec.lock`, the Android SDK dependency, and the browser host's
   `package.json`/lockfile. Distinguish Flutter's version from its JS provider.
2. Identify the actual target: Flutter Android, Flutter iOS, Flutter Web/PWA, or
   direct JavaScript. Read [versions and platforms](references/platforms.md)
   before proposing platform-dependent behavior. Guard Web before using native
   platform checks; do not introduce `dart:io` into browser code.
3. Use this baseline only for Flutter **0.2.1**, Kotlin **v0.2.1**, and Web
   **0.2.0**. For another version, inspect that version's public source/types and
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
backend implementation win. The references document known gaps in the 0.2.1 Web
adapter; do not implement speculative workarounds in its private internals.

## Choose the method by intent

| Developer intent | Public method / route |
| --- | --- |
| Start or restore a mobile session | `configureResult(apiKey: ..., appUserIdentifier: ...)`; identifier optional |
| Switch mobile customer / end session | `logInResult(id)` / `logOutResult()` |
| Authenticate a host user on Flutter Web | `configureAuthenticatedWebSessionResult(...)` with a fresh backend ticket; alternatively ticket exchange or OTP |
| Display current / placed / exact offering | `getCurrentOfferingResult()`, `getCurrentOfferingResult(placementIdentifier: ...)`, `getOfferingResult(id)` |
| Read the catalog | `getOfferingsResult()`; use model helpers for existing data |
| Update customer properties | `setAttributesResult(Map<String, String?>)`; null/empty deletes; reserved setters use supported keys |
| Refresh after attribute-based targeting changes | Android/iOS `syncAttributesAndOfferingsIfNeeded()`; read the Web support limitation before suggesting it |
| Read access | `getCustomerInfoResult(fetchPolicy: ...)`, then `entitlements.active`; synchronous helpers read the current mirror |
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

## Non-negotiable integration rules

- Keep one backend owner. Use the Flutter facade; do not call MethodChannels,
  `src/` classes, Go/Laravel endpoints, or a second JS instance to bypass a
  missing Flutter operation. A new SDK capability requires an explicit SDK task.
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
- Do not consume subscription/non-consumable receipts or restore consumables as
  fresh inventory. `DELIVERY_REQUIRED`/`CONSUME_REQUIRED` are workflow states,
  not a completed host grant. Purchase history is not current entitlement authority.
- Trust server prices and verified CustomerInfo. Do not calculate a purchase
  discount locally, turn a network error into "invalid code", infer lifetime
  access merely from a null expiry, or promise offline revocation/clock-tamper
  protection beyond the installed SDK.
- Use public app keys on clients and the **Public Web App Key** in browsers.
  Never request, embed, print, or persist server secrets, raw session tokens,
  tickets, receipts or full customer payloads in diagnostics. Do not fabricate
  Identity Tickets in frontend code or replay a one-time ticket after uncertainty.
- Do not invent RevenueCat APIs because names look similar. In Flutter 0.2.1
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
