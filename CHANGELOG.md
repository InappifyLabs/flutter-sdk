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
