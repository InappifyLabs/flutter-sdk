# Contributing

Use Flutter 3.44 or newer with Dart 3.12 or newer. The example and CI use Flutter 3.47.1. Android requires JDK 17 and the SDK/build tools required by `example/android`; iOS builds require macOS, Xcode and CocoaPods.

```sh
flutter pub get
flutter test
flutter analyze --no-fatal-infos
cd example
flutter pub get
flutter test
flutter build apk --debug --target-platform=android-arm64
flutter build web
```

The example contains no app credentials and makes no SDK request until a button is pressed. Do not add private keys, sessions, purchase receipts, host APKs, generated files or local build paths to this repository.

Android bridge tests use the example's Flutter/Gradle classpath:

```sh
cd example/android
./gradlew :inappify_sdk:testDebugUnitTest :inappify_sdk:assembleRelease
```

On macOS, compile the Swift infrastructure with `flutter build ios --simulator --debug` from `example`. No paid store transaction or device test is part of the automated checks.

Keep one authoritative session backend per platform. Android must delegate to the Kotlin SDK, iOS owns V2 lifecycle in Dart, and Web delegates to the JavaScript provider. Preserve channel envelopes, persisted-state scope and the durable delivery-before-acknowledgement rule. Add meaningful contract tests when changing these behaviors.

Review the [release procedure](doc/RELEASING.md) before changing version metadata or dependencies.
