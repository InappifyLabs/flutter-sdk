## 0.2.7

- Pin Android to Kotlin v0.2.7: distinguish Myket preparation from payment dispatch, avoid blocking the UI during billing preparation, and prevent late payment screens after timeout or close. Resolve only proven pre-dispatch failures; keep uncertain dispatched and older attempts for reconciliation.
- Reconcile pending Android purchases after ten minutes while the configured app is foreground and connected. Reuse existing receipt/status verification and retry unresolved work without launching another payment. Elapsed time and empty inventory never imply cancellation or failed payment.
- Check eligible Bazaar/Myket package trials through the existing purchase route before opening paid billing. Require the matching backend DONE/NEEDSTORE contract and native_purchase_attempts.is_trial_check migration before upgrading clients.
- Include the updated integration skill, including host journals scoped by product. Host application changes must be applied separately. Preserve store-specific packaging, fulfillment, and iOS/Web behavior.

## 0.2.6

- Pin Android to Kotlin v0.2.6.
- Add build-time `myket`, `bazaar`, `direct`, and `allStores` packaging. Include Poolakey only in Bazaar/allStores and Myket code, resources and manifest components only in Myket/allStores.
- Keep runtime API-key selection, purchase verification, pending operations and recovery unchanged; excluded stores fail with `UNSUPPORTED_MARKET`.
- Publish Gradle Module Metadata with all release variants; document migration, CI settings and the channel-specific manifest workaround.

## 0.2.5

- Pin Android to Kotlin v0.2.4: compact Myket purchase metadata prevents size-related payment-screen failures while retaining full recovery and server purchase bindings. Older receipts remain recoverable.
- Expose safe Myket callback codes and exception/stage categories through native history; reject oversized new contexts before billing. Preserve existing uncertain attempts and exactly-once fulfillment.
- Include the updated integration skill. Bazaar, Direct, iOS/Web behavior and the channel protocol remain unchanged.

## 0.2.4

- Pin Android to Kotlin v0.2.3 for server-authoritative Myket product types and recovery of older, already-granted purchases without a duplicate entitlement or inventory grant.
- Preserve subscription consumption after committed access, consumable consumption after confirmed delivery, and permanent-product ownership without consumption. Keep Bazaar, Direct, iOS/Web behavior and native protocol v1 unchanged.
- Update the official integration skill with legacy receipt recovery, required server evidence and safe failure diagnostics. Deploy the matching commerce backend and publish Kotlin v0.2.3 before this Flutter release.

## 0.2.3

- Update Android to Kotlin v0.2.2 for Myket manually renewed timed subscriptions, using consumable Myket SKUs mapped to Inappify SUBSCRIPTION products.
- Keep Flutter purchase/recovery APIs and native protocol v1 unchanged. Deploy the matching V2 commerce backend first; Bazaar, normal consumables, lifetime products, iOS/Web and Direct flows retain their existing behavior.

## 0.2.2

- Connect Flutter Web `syncAttributesAndOfferingsIfNeeded` to the existing Web
  provider instance. Delegate its five-admission rolling minute limit, including
  failures and same-session cache fallback; retain partial customer refreshes
  when the following offerings request fails.
- Forward all four CustomerInfo fetch policies to JavaScript, explicitly default
  to `CACHED_OR_FETCHED`, and send cancellation options in the second argument.
  Web cache-only reads no longer wait behind an in-flight network operation.
- Mirror provider background updates with ordered snapshots; reject superseded
  customer responses and clear prior-account mirrors at identity replacement.
- Preserve provider error codes and allowlisted numeric rate-limit timing without
  copying raw error details. Require Web provider 0.2.0 or newer and probe the
  actual combined-sync method before advertising support.
- Add fake-bridge and Chrome acceptance tests against the published Web 0.2.0
  provider; update integration docs and the official agent skill. Keep Android
  pinned to Kotlin v0.2.1 with existing purchase, cache and recovery behavior.

## 0.2.1

- Add optional `offeringIdentifier` to both public discount-link methods for Web
  placement offerings. Preserve current-offering behavior when omitted and reject
  blank selectors or mismatched returned offerings without catalog changes.
  Android/iOS keep their existing code-only discount requests and responses.

- Implement iOS `syncAttributesAndOfferingsIfNeeded` through the existing Go V2
  attribute/offerings queue, persistence and events, with Android's five-call
  rolling minute quota and current-session cache fallback.

- Include correlated Direct payment/recovery outcomes from the Android backend;
  subscription/lifetime payment and consumable delivery share the original attempt ID.
- Forward correlated Android purchase/recovery outcomes through typed
  `purchaseUpdates` / `event.purchaseAttempt` and native encrypted history queries
  `getPurchaseAttempt` / `getPurchaseAttempts`. Preserve protocol-v1 event/response
  compatibility, existing purchase/sync results and native cache ownership.

## 0.2.0

- Add global RevenueCat-style log levels and custom log handlers, available before
  Configure. Default to DEBUG during development and INFO in release. Preserve
  filtered HTTP traces and keep secrets/bodies out of standard logs at all levels.
  Logging failures do not alter purchase results, cache, retries or recovery.

- Rename the public purchase helpers to `syncStorePurchases()` and
  `restoreStorePurchases()`. Remove public `recover()` and its native channel
  entry point; keep automatic native/iOS recovery, scheduling, purchase logic,
  Direct delivery behavior and persisted cache unchanged.

- Align Flutter and the Android bridge with the Kotlin public API: configure with
  app key/optional customer, logIn/logOut, Map attributes, Package purchases,
  placement/current/exact Offering selection and discounted payment links.
- Forward all four CustomerInfo fetch policies, defaulting to cachedOrFetched.
  Add read-only entitlements.all/active using the native trusted clock.
- Forward syncAttributesAndOfferingsIfNeeded to Kotlin, including its five-call
  rolling minute limit and existing cache/automatic refresh behavior.
- Add bidirectional consumable delivery handlers and marked payment-return
  forwarding, including new Android intents. Engine detach/failure never
  acknowledges uncertain host delivery.
- Remove obsolete public aliases, manual attribute queue controls, targeting
  overrides, force-refresh flags and checkEntitlement. Preserve native purchase,
  verification, recovery and persistent cache/journal formats.
- Align the native dependency and Dart/iOS package metadata at 0.2.0.
- Support a prebuilt local native AAR with its dependency metadata in the example
  when the Flutter and Kotlin repositories use different Gradle toolchains.

## 0.1.1

- Remove `apiKey` from mobile `login`, `loginResult`, and `InappifyLoginRequest`.
  Existing Flutter calls must drop this named argument; Configure still requires
  the public app key. Login and renewal use the configured session and options.
- Pin Android to Kotlin SDK `v0.1.1` and use its keyless login constructor.
- Align the Flutter package, Dart/iOS runtime and CocoaPods metadata at `0.1.1`.

## 0.1.0

- Publish the first stable release from the 0.1.0 beta series.
- License the Flutter SDK under Apache-2.0 and prepare pub.dev installation documentation.
- Pin Android to `com.github.InappifyLabs:kotlin-sdk:v0.1.0`.
- Align the Flutter package, Dart/iOS mobile SDK and CocoaPods metadata at `0.1.0`.
- Preserve the existing public API, platform capabilities and payment behavior.
- Keep the independent JavaScript provider baseline at `@inappifylabs/web-sdk@0.1.0-beta.3`.

## 0.1.0-beta.0

- Establish the InappifyLabs Flutter SDK repository and beta release series.
- Android uses `com.github.InappifyLabs:kotlin-sdk:v0.1.0-beta.0` through the existing MethodChannel contract; native and Dart/iOS mobile SDK versions are `0.1.0-beta.0`.
- Keep the current purchase, verified customer state, store recovery and durable consumable delivery APIs. Bazaar and Myket remain Android-only; iOS uses Dart V2 for Direct purchases, and Web uses the separately loaded JavaScript provider.
- Correct Android capability advertisement for unsupported standalone cache restoration. Use `configureResult` to load and refresh persisted mobile state.
- Align the Android plugin with Flutter's Kotlin build integration, JDK 17 and Gradle 9.3.1. Minimum Flutter/Dart versions are 3.44.0/3.12.0.
- Replace historical guides with documentation of the current implementation and add a minimal integration example.
- Remove obsolete flavor dependency manifests/scripts and invalid analyzer annotations without changing runtime data formats or public models.
