import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:inappify_sdk/inappify_sdk.dart';
import 'package:inappify_sdk/inappify_sdk_method_channel.dart';
import 'package:inappify_sdk/inappify_sdk_platform_interface.dart';
import 'package:inappify_sdk/models/customer_info.dart';
import 'package:inappify_sdk/models/entitlement_model.dart';
import 'package:inappify_sdk/src/application/inappify_coordinator.dart';

void main() {
  group('InappifySdkPlatform', () {
    test('uses MethodChannelInappifySdk as the default implementation', () {
      expect(InappifySdkPlatform.instance, isA<MethodChannelInappifySdk>());
    });

    test('new semantic methods are safely unsupported by default', () async {
      final platform = _MinimalPlatform();

      final result = await platform.logout();

      expect(result.isSuccess, isFalse);
      expect(result.failure?.code, InappifyFailureCode.unsupportedOperation);
      expect(result.failure?.details, <String, Object?>{'operation': 'logout'});
    });
  });

  group('InappifyCoordinator backend ownership', () {
    late InappifySdkPlatform originalPlatform;

    setUp(() {
      originalPlatform = InappifySdkPlatform.instance;
    });

    tearDown(() {
      InappifySdkPlatform.instance = originalPlatform;
    });

    test(
      'uses the fallback when the candidate cannot own a full session',
      () async {
        final candidate = _FakePlatform(
          capabilities: InappifyBackendCapabilities.unavailable(
            backendKind: InappifyBackendKind.methodChannel,
          ),
        );
        final fallback = _FakePlatform(capabilities: _completeCapabilities());
        final replacement = _FakePlatform(
          capabilities: _completeCapabilities(),
        );
        final coordinator = InappifyCoordinator(fallbackPlatform: fallback);
        _cleanUp(coordinator, <_FakePlatform>[
          candidate,
          fallback,
          replacement,
        ]);
        InappifySdkPlatform.instance = candidate;

        final configured = await coordinator.configure(
          const InappifyConfigureRequest(apiKey: 'api-key'),
        );
        InappifySdkPlatform.instance = replacement;
        final loggedIn = await coordinator.login(
          const InappifyLoginRequest(appUserIdentifier: 'customer-1'),
        );

        expect(configured.isSuccess, isTrue);
        expect(loggedIn.isSuccess, isTrue);
        expect(candidate.capabilityCalls, 1);
        expect(candidate.configureCalls, 0);
        expect(fallback.configureCalls, 1);
        expect(fallback.loginCalls, 1);
        expect(replacement.capabilityCalls, 0);
        expect(replacement.loginCalls, 0);
      },
    );

    test(
      'selects a candidate only when it supports the complete lifecycle',
      () async {
        final candidate = _FakePlatform(capabilities: _completeCapabilities());
        final fallback = _FakePlatform(capabilities: _completeCapabilities());
        final coordinator = InappifyCoordinator(fallbackPlatform: fallback);
        _cleanUp(coordinator, <_FakePlatform>[candidate, fallback]);
        InappifySdkPlatform.instance = candidate;

        final result = await coordinator.configure(
          const InappifyConfigureRequest(apiKey: 'api-key'),
        );

        expect(result.isSuccess, isTrue);
        expect(candidate.configureCalls, 1);
        expect(fallback.configureCalls, 0);
      },
    );

    test(
      'uses the fallback when a complete candidate cannot expose events',
      () async {
        final candidate = _FakePlatform(
          capabilities: _completeCapabilities(),
          throwWhenReadingEvents: true,
        );
        final fallback = _FakePlatform(capabilities: _completeCapabilities());
        final coordinator = InappifyCoordinator(fallbackPlatform: fallback);
        _cleanUp(coordinator, <_FakePlatform>[candidate, fallback]);
        InappifySdkPlatform.instance = candidate;

        final result = await coordinator.configure(
          const InappifyConfigureRequest(apiKey: 'api-key'),
        );

        expect(result.isSuccess, isTrue);
        expect(candidate.configureCalls, 0);
        expect(fallback.configureCalls, 1);
      },
    );

    test(
      'mirrors complete snapshots and synchronizes them before the next call',
      () async {
        final candidate = _FakePlatform(
          capabilities: _completeCapabilities(),
          configureHandler: (_) async => InappifySdkResult<void>.success(
            snapshot: const InappifySdkSnapshot(
              accessToken: 'token-1',
              apiKey: 'api-key',
              appId: 23,
              country: 'IR',
              versionName: '3.4.0',
              versionCode: 2034,
            ),
          ),
        );
        final fallback = _FakePlatform(capabilities: _completeCapabilities());
        final coordinator = InappifyCoordinator(fallbackPlatform: fallback);
        _cleanUp(coordinator, <_FakePlatform>[candidate, fallback]);
        InappifySdkPlatform.instance = candidate;

        await coordinator.configure(
          const InappifyConfigureRequest(apiKey: 'api-key'),
        );
        final loginResult = await coordinator.login(
          const InappifyLoginRequest(appUserIdentifier: 'customer-1'),
        );

        expect(loginResult.isSuccess, isTrue);
        expect(coordinator.state.accessToken, 'token-1');
        expect(coordinator.state.appId, 23);
        expect(coordinator.state.versionCode, 2034);
        expect(candidate.compatibilitySnapshots, hasLength(2));
        expect(candidate.compatibilitySnapshots.last.accessToken, 'token-1');
        expect(candidate.compatibilitySnapshots.last.appId, 23);
      },
    );

    test(
      'configure calls with different recovery flags are not coalesced',
      () async {
        final flags = <bool>[];
        final candidate = _FakePlatform(
          capabilities: _completeCapabilities(),
          configureHandler: (request) async {
            flags.add(request.enableSubscriptionRecoveryWithoutPayload);
            return InappifySdkResult<void>.success(
              snapshot: const InappifySdkSnapshot(),
            );
          },
        );
        final fallback = _FakePlatform(capabilities: _completeCapabilities());
        final coordinator = InappifyCoordinator(fallbackPlatform: fallback);
        _cleanUp(coordinator, [candidate, fallback]);
        InappifySdkPlatform.instance = candidate;
        final enabled = coordinator.configure(
          const InappifyConfigureRequest(apiKey: 'fixture-key'),
        );
        final disabled = coordinator.configure(
          const InappifyConfigureRequest(
            apiKey: 'fixture-key',
            enableSubscriptionRecoveryWithoutPayload: false,
          ),
        );
        expect(identical(enabled, disabled), isFalse);
        expect((await enabled).isSuccess, isTrue);
        expect((await disabled).isSuccess, isTrue);
        expect(flags, [true, false]);
      },
    );

    test('coalesces concurrent configure calls with identical input', () async {
      final pending = Completer<InappifySdkResult<void>>();
      final candidate = _FakePlatform(
        capabilities: _completeCapabilities(),
        configureHandler: (_) => pending.future,
      );
      final fallback = _FakePlatform(capabilities: _completeCapabilities());
      final coordinator = InappifyCoordinator(fallbackPlatform: fallback);
      _cleanUp(coordinator, <_FakePlatform>[candidate, fallback]);
      InappifySdkPlatform.instance = candidate;
      const request = InappifyConfigureRequest(
        apiKey: 'api-key',
        appUserIdentifier: 'customer-1',
      );

      final first = coordinator.configure(request);
      final second = coordinator.configure(request);
      await Future<void>.delayed(Duration.zero);

      expect(candidate.configureCalls, 1);
      pending.complete(
        InappifySdkResult<void>.success(snapshot: const InappifySdkSnapshot()),
      );
      expect((await first).isSuccess, isTrue);
      expect((await second).isSuccess, isTrue);
      expect(candidate.configureCalls, 1);
    });

    test(
      'serializes configure calls for different customer identities',
      () async {
        final firstPending = Completer<InappifySdkResult<void>>();
        final secondPending = Completer<InappifySdkResult<void>>();
        final candidate = _FakePlatform(
          capabilities: _completeCapabilities(),
          configureHandler: (request) {
            return request.appUserIdentifier == 'customer-1'
                ? firstPending.future
                : secondPending.future;
          },
        );
        final fallback = _FakePlatform(capabilities: _completeCapabilities());
        final coordinator = InappifyCoordinator(fallbackPlatform: fallback);
        _cleanUp(coordinator, <_FakePlatform>[candidate, fallback]);
        InappifySdkPlatform.instance = candidate;

        final first = coordinator.configure(
          const InappifyConfigureRequest(
            apiKey: 'api-key',
            appUserIdentifier: 'customer-1',
          ),
        );
        final second = coordinator.configure(
          const InappifyConfigureRequest(
            apiKey: 'api-key',
            appUserIdentifier: 'customer-2',
          ),
        );
        await Future<void>.delayed(Duration.zero);

        expect(candidate.configureCalls, 1);
        firstPending.complete(
          InappifySdkResult<void>.success(
            snapshot: const InappifySdkSnapshot(accessToken: 'token-1'),
          ),
        );
        expect((await first).isSuccess, isTrue);
        await Future<void>.delayed(Duration.zero);
        expect(candidate.configureCalls, 2);

        secondPending.complete(
          InappifySdkResult<void>.success(
            snapshot: const InappifySdkSnapshot(accessToken: 'token-2'),
          ),
        );
        expect((await second).isSuccess, isTrue);
        expect(coordinator.state.accessToken, 'token-2');
      },
    );

    test('rejects a successful backend result without a snapshot', () async {
      final candidate = _FakePlatform(
        capabilities: _completeCapabilities(),
        configureHandler: (_) async => InappifySdkResult<void>.success(),
      );
      final fallback = _FakePlatform(capabilities: _completeCapabilities());
      final coordinator = InappifyCoordinator(fallbackPlatform: fallback);
      _cleanUp(coordinator, <_FakePlatform>[candidate, fallback]);
      InappifySdkPlatform.instance = candidate;

      final result = await coordinator.configure(
        const InappifyConfigureRequest(apiKey: 'api-key'),
      );

      expect(result.isSuccess, isFalse);
      expect(result.failure?.code, InappifyFailureCode.malformedResponse);
    });

    test('converts backend exceptions into stable semantic failures', () async {
      final candidate = _FakePlatform(
        capabilities: _completeCapabilities(),
        loginHandler: (_) => Future<InappifySdkResult<void>>.error(
          StateError('sensitive implementation detail'),
        ),
      );
      final fallback = _FakePlatform(capabilities: _completeCapabilities());
      final coordinator = InappifyCoordinator(fallbackPlatform: fallback);
      _cleanUp(coordinator, <_FakePlatform>[candidate, fallback]);
      InappifySdkPlatform.instance = candidate;

      final result = await coordinator.login(
        const InappifyLoginRequest(appUserIdentifier: 'customer-1'),
      );

      expect(result.isSuccess, isFalse);
      expect(result.failure?.code, InappifyFailureCode.unknown);
      expect(result.failure?.message, 'Inappify login failed.');
      expect(result.failure?.details, <String, Object?>{'operation': 'login'});
    });

    test('applies asynchronous snapshots from the selected backend', () async {
      final candidate = _FakePlatform(capabilities: _completeCapabilities());
      final fallback = _FakePlatform(capabilities: _completeCapabilities());
      final coordinator = InappifyCoordinator(fallbackPlatform: fallback);
      _cleanUp(coordinator, <_FakePlatform>[candidate, fallback]);
      InappifySdkPlatform.instance = candidate;
      await coordinator.configure(
        const InappifyConfigureRequest(apiKey: 'api-key'),
      );

      candidate.emit(
        const InappifyPlatformEvent(
          type: InappifyPlatformEventType.stateChanged,
          snapshot: InappifySdkSnapshot(
            accessToken: 'event-token',
            apiKey: 'api-key',
            appId: 77,
          ),
        ),
      );
      await Future<void>.delayed(Duration.zero);

      expect(coordinator.state.accessToken, 'event-token');
      expect(coordinator.state.appId, 77);
    });

    test('applies an event after an in-flight operation response', () async {
      final pending = Completer<InappifySdkResult<void>>();
      final candidate = _FakePlatform(
        capabilities: _completeCapabilities(),
        configureHandler: (_) => pending.future,
      );
      final fallback = _FakePlatform(capabilities: _completeCapabilities());
      final coordinator = InappifyCoordinator(fallbackPlatform: fallback);
      _cleanUp(coordinator, <_FakePlatform>[candidate, fallback]);
      InappifySdkPlatform.instance = candidate;

      final operation = coordinator.configure(
        const InappifyConfigureRequest(apiKey: 'api-key'),
      );
      await Future<void>.delayed(Duration.zero);
      candidate.emit(
        const InappifyPlatformEvent(
          type: InappifyPlatformEventType.purchaseUpdated,
          snapshot: InappifySdkSnapshot(accessToken: 'event-token'),
        ),
      );
      pending.complete(
        InappifySdkResult<void>.success(
          snapshot: const InappifySdkSnapshot(accessToken: 'response-token'),
        ),
      );

      expect((await operation).isSuccess, isTrue);
      await Future<void>.delayed(Duration.zero);
      expect(coordinator.state.accessToken, 'event-token');
    });
  });

  group('InappifySdk compatibility helpers', () {
    test('recognizes anonymous customer identifiers', () {
      expect(InappifySdk.isCustomerAnonymous(appUserIdentifier: null), isTrue);
      expect(
        InappifySdk.isCustomerAnonymous(
          appUserIdentifier: 'InaAnonymousId-123',
        ),
        isTrue,
      );
      expect(
        InappifySdk.isCustomerAnonymous(appUserIdentifier: 'customer-123'),
        isFalse,
      );
    });

    test('reads active entitlements from the mirrored customer snapshot', () {
      final originalCustomer = InappifySdk.customerInfo;
      addTearDown(() => InappifySdk.customerInfo = originalCustomer);
      InappifySdk.customerInfo = CustomerInfo(
        entitlements: <EntitlementModel>[
          EntitlementModel(identifier: 'pro', isActive: true),
          EntitlementModel(identifier: 'expired', isActive: false),
        ],
      );

      expect(InappifySdk.isActiveEntitlement('pro'), isTrue);
      expect(InappifySdk.isActiveEntitlement('expired'), isFalse);
      expect(InappifySdk.isActiveEntitlement('missing'), isFalse);
    });
  });
}

class _MinimalPlatform extends InappifySdkPlatform {}

class _FakePlatform extends InappifySdkPlatform {
  _FakePlatform({
    required this.capabilities,
    this.configureHandler,
    this.loginHandler,
    this.throwWhenReadingEvents = false,
  });

  final InappifyBackendCapabilities capabilities;
  final Future<InappifySdkResult<void>> Function(InappifyConfigureRequest)?
  configureHandler;
  final Future<InappifySdkResult<void>> Function(InappifyLoginRequest)?
  loginHandler;
  final bool throwWhenReadingEvents;

  final StreamController<InappifyPlatformEvent> _events =
      StreamController<InappifyPlatformEvent>.broadcast(sync: true);

  int capabilityCalls = 0;
  int configureCalls = 0;
  int loginCalls = 0;
  final List<InappifySdkSnapshot> compatibilitySnapshots =
      <InappifySdkSnapshot>[];

  @override
  Stream<InappifyPlatformEvent> get events {
    if (throwWhenReadingEvents) {
      throw StateError('Event bridge is unavailable.');
    }
    return _events.stream;
  }

  @override
  Future<InappifyBackendCapabilities> getCapabilities() async {
    capabilityCalls += 1;
    return capabilities;
  }

  @override
  void synchronizeCompatibilityState(InappifySdkSnapshot snapshot) {
    compatibilitySnapshots.add(snapshot);
  }

  @override
  Future<InappifySdkResult<void>> configure(InappifyConfigureRequest request) {
    configureCalls += 1;
    return configureHandler?.call(request) ??
        Future<InappifySdkResult<void>>.value(
          InappifySdkResult<void>.success(
            snapshot: compatibilitySnapshots.last,
          ),
        );
  }

  @override
  Future<InappifySdkResult<void>> login(InappifyLoginRequest request) {
    loginCalls += 1;
    return loginHandler?.call(request) ??
        Future<InappifySdkResult<void>>.value(
          InappifySdkResult<void>.success(
            snapshot: compatibilitySnapshots.last,
          ),
        );
  }

  void emit(InappifyPlatformEvent event) => _events.add(event);

  Future<void> dispose() => _events.close();
}

InappifyBackendCapabilities _completeCapabilities() {
  return InappifyBackendCapabilities(
    backendKind: InappifyBackendKind.methodChannel,
    protocolVersion: InappifyBackendCapabilities.currentProtocolVersion,
    ownsSession: true,
    supportedOperations: Set<InappifyOperation>.unmodifiable(
      InappifyOperation.values,
    ),
    sdkVersion: 'test',
  );
}

void _cleanUp(InappifyCoordinator coordinator, List<_FakePlatform> platforms) {
  addTearDown(() async {
    await coordinator.resetForTesting();
    for (final platform in platforms) {
      await platform.dispose();
    }
  });
}
