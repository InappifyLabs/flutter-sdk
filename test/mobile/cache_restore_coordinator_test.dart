import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:inappify_sdk/inappify_sdk_platform_interface.dart';
import 'package:inappify_sdk/models/customer_info.dart';
import 'package:inappify_sdk/src/application/inappify_coordinator.dart';

class _Platform extends InappifySdkPlatform {
  bool hit = true;
  final calls = <String>[];
  final changes = StreamController<InappifyPlatformEvent>.broadcast(sync: true);
  final cache = InappifySdkSnapshot(
    apiKey: 'fixture-key',
    appId: 7,
    versionName: '2.1.0',
    versionCode: 21,
    country: 'IR',
    customerInfo: CustomerInfo(originalAppUserId: 'cached-user'),
    isConfigured: true,
  );
  @override
  Future<InappifyBackendCapabilities> getCapabilities() async =>
      InappifyBackendCapabilities(
        backendKind: InappifyBackendKind.dart,
        protocolVersion: 1,
        ownsSession: true,
        supportedOperations: InappifyOperation.values.toSet(),
      );
  @override
  Stream<InappifyPlatformEvent> get events => changes.stream;
  @override
  Future<InappifySdkResult<bool>> restoreCachedSession(
    InappifyConfigureRequest request,
  ) async {
    calls.add('restore');
    return InappifySdkResult.success(data: hit, snapshot: cache);
  }

  @override
  Future<InappifySdkResult<void>> configure(
    InappifyConfigureRequest request,
  ) async {
    calls.add('configure');
    final fresh = InappifySdkSnapshot(
      customerInfo: CustomerInfo(
        originalAppUserId: 'cached-user',
        hasUsedTrial: true,
      ),
    );
    changes.add(
      InappifyPlatformEvent(
        type: InappifyPlatformEventType.customerInfoChanged,
        snapshot: fresh,
      ),
    );
    return InappifySdkResult.success(snapshot: fresh);
  }
}

void main() {
  const request = InappifyConfigureRequest(
    apiKey: 'fixture-key',
    appUserIdentifier: 'cached-user',
  );
  test(
    'restore publishes cache without implicit configure then refresh emits changes',
    () async {
      final original = InappifySdkPlatform.instance;
      final platform = _Platform();
      InappifySdkPlatform.instance = platform;
      final coordinator = InappifyCoordinator(fallbackPlatform: platform);
      final events = <InappifyPlatformEvent>[];
      final subscription = coordinator.events.listen(events.add);
      try {
        expect((await coordinator.restoreCachedSession(request)).data, true);
        expect(platform.calls, ['restore']);
        expect(
          coordinator.state.customerInfo?.originalAppUserId,
          'cached-user',
        );
        expect(coordinator.state.versionCode, 21);
        await coordinator.configure(request);
        expect(platform.calls, ['restore', 'configure']);
        expect(coordinator.state.customerInfo?.hasUsedTrial, true);
        expect(events, isNotEmpty);
      } finally {
        await subscription.cancel();
        await coordinator.resetForTesting();
        await platform.changes.close();
        InappifySdkPlatform.instance = original;
      }
    },
  );

  test(
    'cache miss cannot mirror a foreign snapshot returned by an older adapter',
    () async {
      final original = InappifySdkPlatform.instance;
      final platform = _Platform()..hit = false;
      InappifySdkPlatform.instance = platform;
      final coordinator = InappifyCoordinator(fallbackPlatform: platform);
      try {
        expect((await coordinator.restoreCachedSession(request)).data, false);
        expect(coordinator.state.customerInfo, isNull);
        expect(platform.calls, ['restore']);
      } finally {
        await coordinator.resetForTesting();
        await platform.changes.close();
        InappifySdkPlatform.instance = original;
      }
    },
  );
}
