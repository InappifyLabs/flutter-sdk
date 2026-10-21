import 'package:flutter_test/flutter_test.dart';
import 'package:inappify_sdk/inappify_sdk.dart';
import 'package:inappify_sdk/inappify_sdk_platform_interface.dart';

class _Platform extends InappifySdkPlatform {
  final requests = <InappifyConfigureRequest>[];

  @override
  Future<InappifyBackendCapabilities> getCapabilities() async =>
      InappifyBackendCapabilities(
        backendKind: InappifyBackendKind.methodChannel,
        protocolVersion: 1,
        ownsSession: true,
        supportedOperations: InappifyOperation.values.toSet(),
      );

  @override
  Stream<InappifyPlatformEvent> get events => const Stream.empty();

  @override
  Future<InappifySdkResult<void>> configure(
    InappifyConfigureRequest request,
  ) async {
    requests.add(request);
    return InappifySdkResult.success(snapshot: const InappifySdkSnapshot());
  }

  @override
  Future<InappifySdkResult<bool>> restoreCachedSession(
    InappifyConfigureRequest request,
  ) async {
    requests.add(request);
    return InappifySdkResult.success(
      data: true,
      snapshot: const InappifySdkSnapshot(),
    );
  }
}

void main() {
  test(
    'configure accepts only app key and optional customer; recovery stays enabled',
    () async {
      final original = InappifySdkPlatform.instance;
      final platform = _Platform();
      InappifySdkPlatform.instance = platform;
      try {
        expect(await InappifySdk.configure(apiKey: 'fixture-key'), isTrue);
        expect(
          (await InappifySdk.configureResult(
            apiKey: 'fixture-key',
            appUserIdentifier: 'customer-1',
          )).isSuccess,
          isTrue,
        );
        expect(platform.requests.map((r) => r.appUserIdentifier), [
          null,
          'customer-1',
        ]);
        expect(
          platform.requests.every(
            (r) => r.enableSubscriptionRecoveryWithoutPayload,
          ),
          isTrue,
        );
        expect(
          platform.requests.every(
            (r) =>
                r.market == null &&
                r.marketKey == null &&
                r.country == null &&
                r.appVersion == null,
          ),
          isTrue,
        );
      } finally {
        InappifySdkPlatform.instance = original;
      }
    },
  );
}
