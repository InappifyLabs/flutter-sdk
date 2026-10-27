# Inappify Flutter SDK

Flutter SDK for Inappify sessions, offerings, entitlements and purchases.
The **0.2.6** API follows the current Kotlin SDK. Android delegates to
Kotlin through MethodChannel; Kotlin owns purchase, cache and automatic recovery.
iOS keeps its Dart Direct-payment backend; Web uses the separately loaded
JavaScript SDK. Store purchases and native delivery callbacks are Android-only.
Flutter Web requires `@inappifylabs/web-sdk` **0.2.0+**. It supports combined
attributes/offerings sync and all four CustomerInfo policies, defaulting explicitly
to `cachedOrFetched`. See the [Web setup and cache contract](doc/WEB.md).

Android store packaging for the **0.2.6** release is described in
[store-specific builds](doc/ANDROID_STORES.md). Set `inappifyStore=myket` or
`inappifyStore=bazaar` at build time; API keys alone do not remove permissions.

## Configure and identify the customer

```dart
import 'package:inappify_sdk/inappify_sdk.dart';

await InappifySdk.configure(apiKey: 'public_app_key');
// Or, on mobile:
await InappifySdk.configure(apiKey: 'public_app_key', appUserIdentifier: 'customer_123');
await InappifySdk.logIn('customer_123');
await InappifySdk.logOut();
await InappifySdk.setAttributes({'plan': 'gold', 'removed': null});
await InappifySdk.setEmail('person@example.com');
```

The verified server configuration supplies market and RSA key. Android reads
app metadata itself. Configure on startup; automatic prefetch/recovery belongs to
the native SDK. Web identity uses an Identity Ticket or OTP; see [Web](doc/WEB.md).

## Offerings, customer info and purchase

```dart
final offerings = await InappifySdk.getOfferings();
final offering = await InappifySdk.getCurrentOffering();
final placed = await InappifySdk.getCurrentOffering(placementIdentifier: 'home');
final special = await InappifySdk.getOffering('special_offer');
await InappifySdk.syncAttributesAndOfferingsIfNeeded();

final info = await InappifySdk.getCustomerInfo(); // cachedOrFetched
final current = await InappifySdk.getCustomerInfo(
  fetchPolicy: InappifyCacheFetchPolicy.fetchCurrent,
);
final hasPremium = current?.entitlements.active.containsKey('premium') == true;

if (offering?.packages?.isNotEmpty == true) {
  final result = await InappifySdk.purchaseResult(InappifyPurchaseParams(
    packageToPurchase: offering!.packages!.first,
  ));
  // Inspect result.data / result.failure. A Direct payment URL is host-owned.
}
```

The package supplies product/offering/package identifiers and product type;
Android supplies its Activity. Keep an explicit idempotency key only when retrying
the same logical purchase. Consumables require a durable grant; see
[delivery and recovery](doc/STORES_AND_RECOVERY.md).

Convenience operations retain nullable/bool results. Their `*Result` companions
preserve typed failures and snapshots. See the [complete reference](doc/API_REFERENCE.md).
The Android 0.2.6 release uses the coordinated native `v0.2.6` dependency;
[Android development setup](doc/ANDROID.md) supports the current local checkout.

## Documentation

- [Official agent skill](doc/AGENT_SKILL.md): versioned integration guidance, platform differences and purchase/recovery rules for coding agents.
- [Getting started](doc/GETTING_STARTED.md): configuration, identity and typed results.
- [API reference](doc/API_REFERENCE.md): public methods, models, defaults and limits.
- [Android](doc/ANDROID.md): native bridge and build setup.
- [Stores and recovery](doc/STORES_AND_RECOVERY.md): Bazaar, Myket and durable fulfillment.
- [iOS](doc/IOS.md): V2 Direct session and storage companion.
- [Web](doc/WEB.md): JavaScript prerequisite, Identity Tickets, OTP and browser checkout.
- [Paywalls and targeting](doc/PAYWALLS_AND_TARGETING.md): server selection and UI limitations.
- [Security and cache](doc/SECURITY_AND_CACHE.md): trust, persistence and diagnostics.
- [Releasing](doc/RELEASING.md): validation and publication.

Install the official integration skill into your consuming app's coding agent:

```sh
npx skills add InappifyLabs/flutter-sdk --skill inappify-sdk
```

Choose the target agent when prompted; see the [installation guide](doc/AGENT_SKILL.md)
for Codex, Claude Code, Cursor and manual installation.

The repository includes automated contract tests and compile/build checks.
Real store purchases, subscription renewals and backend deployment still require
integration testing against your own app and store accounts.

## License

The Flutter SDK is licensed under [Apache-2.0](LICENSE). The Android dependency
includes its own Apache-2.0 license and third-party notices in the Kotlin repository.

## SDK logging

Configure logging before Configure:

```dart
await InappifySdk.setLogLevel(InappifyLogLevel.debug);
await InappifySdk.setLogHandler((level, message) {
  // Route the filtered message to your application's logging system.
});
// Restore default console output:
await InappifySdk.setLogHandler(null);
```

Levels are verbose, debug, info, warn and error. Defaults are debug in development
and info in release/profile builds. Custom handlers replace default console
output; Android forwards Kotlin messages once and iOS uses the Dart logger.
Logging and consumable-delivery callbacks share a dispatcher without replacing
one another. No logs are uploaded automatically. HTTP trace listeners remain
separate and opt-in. On Web, this controls Flutter-wrapper messages, not the
host-owned JavaScript provider's logger.
