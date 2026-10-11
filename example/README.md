# Integration example

This app configures a session on demand, loads the server-selected current offering, refreshes customer information, invokes mobile recovery, and previews the remote paywall. It makes no SDK network request before a button is pressed. It does not grant consumables or claim a completed purchase.

```sh
flutter pub get
flutter run --dart-define=INAPPIFY_PUBLIC_APP_KEY=YOUR_PUBLIC_APP_KEY
```

For Android Bazaar or Myket, add `--dart-define=INAPPIFY_MARKET=bazar` or `myket` and `--dart-define=INAPPIFY_MARKET_KEY=YOUR_STORE_RSA_PUBLIC_KEY`. Resolve the application account before configuring; optionally supply `--dart-define=INAPPIFY_APP_USER_ID=YOUR_PUBLIC_USER_ID`. These are public client configuration values; never put backend private credentials in Dart defines.

The example Android activity extends `FlutterFragmentActivity` for store UI. Its host build uses JDK17/AGP9.1.1/Gradle9.3.1/SDK37, and its Flutter3.47.1 defaults keep the Kotlin/new-DSL compatibility flags. The example uses the current Flutter deployment floors (Android24/iOS15); the plugin's native library/podspec floors are lower and are not Flutter support claims.

Web requires the separately loaded JavaScript provider described in [Web setup](../doc/WEB.md). Configuring Web here starts anonymously. An authenticated host needs its backend's Identity Ticket flow. A Web build alone does not load that provider or validate live checkout.

The SDK paywall preview renders its remote UI; purchase buttons currently require the host's own integration. See [API reference](../doc/API_REFERENCE.md), [paywalls and targeting](../doc/PAYWALLS_AND_TARGETING.md), and [store recovery and fulfillment](../doc/STORES_AND_RECOVERY.md).

Build without installing or making a payment:

```sh
flutter test
flutter build apk --debug --target-platform=android-arm64
flutter build web
flutter build ios --simulator --debug
```

The iOS command requires macOS/Xcode/CocoaPods. SDK mobile state stays owned by the selected backend; the sample displays sanitized operation codes and does not log credentials or receipts.
