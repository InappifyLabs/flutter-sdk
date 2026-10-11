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
