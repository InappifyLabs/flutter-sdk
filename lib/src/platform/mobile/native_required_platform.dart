import 'package:inappify_sdk/inappify_sdk_platform_interface.dart';

/// Android may not mix a missing/partial native owner with a Dart session.
/// This guard has no network, persistence or billing side effects.
class NativeRequiredPlatform extends InappifySdkPlatform {
  @override
  Future<InappifySdkResult<void>> configure(
    InappifyConfigureRequest request,
  ) async => InappifySdkResult.failure(
    const InappifyFailure(
      code: InappifyFailureCode.bridgeUnavailable,
      message:
          'The Android Inappify native plugin is missing or incompatible. Rebuild the application with a compatible native Inappify plugin.',
      details: {'operation': 'configure', 'nativeRequired': true},
    ),
    snapshot: const InappifySdkSnapshot(),
  );
}
