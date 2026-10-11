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
  test('public configure and cached restore preserve recovery defaults and opt-out', () async {
    final original = InappifySdkPlatform.instance;
    final platform = _Platform();
    InappifySdkPlatform.instance = platform;
    try {
      expect(await InappifySdk.configure(apiKey: 'fixture-key'), isTrue);
      expect(
        await InappifySdk.configure(
          apiKey: 'fixture-key',
          enableSubscriptionRecoveryWithoutPayload: false,
        ),
        isTrue,
      );
      expect(
        (await InappifySdk.configureResult(
          apiKey: 'fixture-key',
          enableSubscriptionRecoveryWithoutPayload: false,
        )).isSuccess,
        isTrue,
      );
      expect(
        (await InappifySdk.restoreCachedSessionResult(
          apiKey: 'fixture-key',
          enableSubscriptionRecoveryWithoutPayload: false,
        )).data,
        isTrue,
      );
      expect(
        (await InappifySdk.configureGoV2(
          apiKey: 'fixture-key',
          enableSubscriptionRecoveryWithoutPayload: false,
        )).isSuccess,
        isTrue,
      );
      expect(
        platform.requests.map(
          (request) => request.enableSubscriptionRecoveryWithoutPayload,
        ),
        [true, false, false, false, false],
      );
    } finally {
      InappifySdkPlatform.instance = original;
    }
  });
}
