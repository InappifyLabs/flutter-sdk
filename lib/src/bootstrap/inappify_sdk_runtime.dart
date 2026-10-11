import 'package:inappify_sdk/src/application/inappify_coordinator.dart';
import 'go_fallback_stub.dart' if (dart.library.io) 'go_fallback_mobile.dart';

/// Package composition root for the process-wide SDK runtime.
///
/// Concrete adapter construction is isolated from the public façade. Android
/// requires the native backend, iOS owns its session in the Dart V2 adapter,
/// and Web requires a compatible host-loaded JavaScript provider.
abstract final class InappifySdkRuntime {
  static final InappifyCoordinator coordinator = InappifyCoordinator(
    fallbackPlatform: createFallback(),
    goPlatformFactory: createGoFallback,
  );
}
