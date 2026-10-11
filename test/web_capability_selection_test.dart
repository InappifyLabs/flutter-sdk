import 'package:flutter_test/flutter_test.dart';
import 'package:inappify_sdk/inappify_sdk_platform_interface.dart';
import 'package:inappify_sdk/src/application/inappify_coordinator.dart';

void main() {
  late InappifySdkPlatform previousPlatform;

  setUp(() {
    previousPlatform = InappifySdkPlatform.instance;
  });

  tearDown(() {
    InappifySdkPlatform.instance = previousPlatform;
  });

  test('a partial Web surface is not selected as the session owner', () async {
    final partialOperations =
        Set<InappifyOperation>.of(InappifyOperation.values)
          ..remove(InappifyOperation.login)
          ..remove(InappifyOperation.getCheckoutStatus);
    final candidate = _CapabilityPlatform(
      capabilities: InappifyBackendCapabilities(
        backendKind: InappifyBackendKind.webJavaScript,
        protocolVersion: InappifyBackendCapabilities.currentProtocolVersion,
        ownsSession: true,
        supportedOperations: partialOperations,
      ),
    );
    final fallback = _CapabilityPlatform(
      capabilities: InappifyBackendCapabilities(
        backendKind: InappifyBackendKind.dart,
        protocolVersion: 1, ownsSession: true,
        supportedOperations: InappifyOperation.values.toSet(),
      ),
    );
    final coordinator = InappifyCoordinator(fallbackPlatform: fallback);
    InappifySdkPlatform.instance = candidate;
    addTearDown(coordinator.resetForTesting);

    final result = await coordinator.configure(
      const InappifyConfigureRequest(apiKey: 'public-web-key'),
    );

    expect(candidate.capabilities.supportsCompleteLifecycle, isFalse);
    expect(result.isSuccess, isTrue);
    expect(candidate.configureCount, 0);
    expect(fallback.configureCount, 1);
  });
}

class _CapabilityPlatform extends InappifySdkPlatform {
  _CapabilityPlatform({required this.capabilities});

  final InappifyBackendCapabilities capabilities;
  int configureCount = 0;

  @override
  Future<InappifyBackendCapabilities> getCapabilities() async => capabilities;

  @override
  Future<InappifySdkResult<void>> configure(
    InappifyConfigureRequest request,
  ) async {
    configureCount += 1;
    return InappifySdkResult<void>.success(
      snapshot: InappifySdkSnapshot(
        accessToken: null,
        apiKey: request.apiKey,
        storeInfo: capabilities.backendKind.name,
      ),
    );
  }
}
