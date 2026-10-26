# Getting started — 0.2.4

Use the local path dependency while developing the coordinated native release:

```yaml
dependencies:
  inappify_sdk:
    path: ../FlutterSDK
```

After publication use `inappify_sdk: ^0.2.4`. The Android dependency is Kotlin
`v0.2.3`; see [Android build/local checkout setup](ANDROID.md). The package requires
the Flutter/Dart versions in pubspec.yaml and a compatible host Android toolchain.
Use FlutterFragmentActivity for Bazaar/Myket purchase UI.

```dart
import 'package:inappify_sdk/inappify_sdk.dart';

final configured = await InappifySdk.configureResult(
  apiKey: 'public_app_key', appUserIdentifier: 'customer_123');
if (!configured.isSuccess) {
  // Inspect configured.failure; do not open account-specific purchase UI yet.
  return;
}
final offering = await InappifySdk.getCurrentOffering();
final package = offering?.packages?.firstOrNull;
if (package != null) {
  final result = await InappifySdk.purchaseResult(
    InappifyPurchaseParams(packageToPurchase: package));
  // Handle Direct NEEDTOPAY URL / store workflow through the typed result.
}
final customer = await InappifySdk.getCustomerInfo();
final premium = customer?.entitlements.active.containsKey('premium') == true;
```

Omit appUserIdentifier for a retained/anonymous mobile identity. Change identity
with logIn(id)/logOut(). Market and RSA key come from the verified server session;
app version comes from Android metadata. Configure once per startup, and let
Kotlin prefetch offerings and reconcile pending work automatically.

For consumables, register a delivery handler before configure and commit a unique,
durable inventory grant before returning delivered. [Delivery/recovery guide](STORES_AND_RECOVERY.md).
For all signatures, defaults and removed names see [API reference](API_REFERENCE.md).
Web keeps its authenticated ticket/OTP flow: [Web guide](WEB.md).
