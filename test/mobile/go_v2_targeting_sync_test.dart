import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:inappify_sdk/inappify_sdk.dart';
import 'package:inappify_sdk/inappify_sdk_platform_interface.dart';
import 'package:inappify_sdk/models/attribute.dart';
import 'package:inappify_sdk/src/application/inappify_coordinator.dart';
import 'package:inappify_sdk/src/bootstrap/inappify_sdk_runtime.dart';
import 'package:inappify_sdk/src/platform/mobile/go_v2_platform.dart';
import 'package:inappify_sdk/src/platform/mobile/go_v2_protocol.dart';

import 'go_commerce_fixture.dart' as direct;
import 'go_v2_platform_test.dart' as fixture;

class _Unavailable extends InappifySdkPlatform {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late fixture.MemoryStore store;
  late fixture.FakeTransport transport;
  late GoV2Platform backend;
  late InappifyCoordinator client;
  late InappifySdkPlatform originalPlatform;
  var elapsed = 0;

  Future<void> configure([String? identity]) async {
    final result = await client.configure(
      InappifyConfigureRequest(
        apiKey: 'public-fixture',
        appUserIdentifier: identity,
      ),
    );
    expect(result.isSuccess, true, reason: '${result.failure}');
  }

  Map<String, dynamic> saved() => jsonDecode(store.raw!);
  Future<void> syncFive() async {
    for (var i = 0; i < 5; i++) {
      expect((await client.syncAttributesAndOfferingsIfNeeded()).isSuccess, true);
    }
  }

  Future<void> pendingAttributes() async {
    transport.respond = (_, _) async => throw const GoV2ProtocolException(
      'NETWORK',
      'OFFLINE',
      retryable: true,
    );
    final result = await client.setAttributes(
      InappifyAttributesRequest(
        attributes: [
          Attribute(key: 'plan', value: 'premium'),
          Attribute(key: r'$email', value: 'fixture@example.test'),
        ],
      ),
    );
    expect(result.isSuccess, false);
    transport.respond = null;
    transport.calls.clear();
  }

  setUp(() {
    elapsed = 0;
    store = fixture.MemoryStore();
    transport = fixture.FakeTransport();
    backend = GoV2Platform(
      transport: transport,
      commerceTransport: fixture.FakeTransport(),
      storage: store,
      metadataProvider: () async => direct.metadata,
      verifier: fixture.StateVerifier(),
      now: () => fixture.now,
      monotonicMilliseconds: () => elapsed,
      anonymousIdFactory: () => fixture.anonymous,
      backgroundRecovery: false,
    );
    originalPlatform = InappifySdkPlatform.instance;
    InappifySdkPlatform.instance = _Unavailable();
    client = InappifyCoordinator(
      fallbackPlatform: _Unavailable(),
      goPlatformFactory: () => backend,
    );
  });

  tearDown(() async {
    await client.resetForTesting();
    await InappifySdkRuntime.coordinator.resetForTesting();
    InappifySdkPlatform.instance = originalPlatform;
    await backend.close();
  });

  test('public facade selects iOS Go backend and advertises combined sync', () async {
    InappifySdkPlatform.instance = backend;
    await InappifySdkRuntime.coordinator.resetForTesting();
    final configured = await InappifySdk.configureResult(apiKey: 'public-fixture');
    expect(configured.isSuccess, true);
    final capabilities = await backend.getCapabilities();
    expect(
      capabilities.supportedOperations,
      contains(InappifyOperation.syncAttributesAndOfferingsIfNeeded),
    );
    transport.calls.clear();
    final result = await InappifySdk.syncAttributesAndOfferingsIfNeeded();
    expect(result.isSuccess, true);
    expect(result.data?.current?.identifier, 'current');
    expect(InappifySdk.snapshot.offerings?.current?.identifier, 'current');
    expect(transport.calls.map((call) => call.endpoint), ['offerings']);
  });

  test('flushes custom and reserved attributes once before fresh offerings, then commits and emits', () async {
    await configure();
    await pendingAttributes();
    final events = <InappifyPlatformEvent>[];
    final subscription = client.events.listen(events.add);
    addTearDown(subscription.cancel);
    final revision = backend.snapshot.revision!;
    final result = await client.syncAttributesAndOfferingsIfNeeded();
    await Future<void>.delayed(Duration.zero);

    expect(result.isSuccess, true);
    expect(transport.calls.map((call) => call.endpoint), [
      'attributes',
      'offerings',
    ]);
    expect(transport.calls.first.body['attributes'], {
      'plan': 'premium',
      r'$email': 'fixture@example.test',
    });
    expect(saved()['attributes'], isEmpty);
    expect(saved()['offerings']['currentOffering'], 'current');
    expect(result.snapshot?.revision, revision + 2);
    expect(result.data?.current?.identifier, 'current');
    expect(client.state.snapshot.offerings?.current?.identifier, 'current');
    expect(events.last.type, InappifyPlatformEventType.stateChanged);
    expect(events.last.snapshot?.revision, result.snapshot?.revision);
    expect(events.last.snapshot?.offerings?.current?.identifier, 'current');
  });

  test('empty queue still fetches fresh offerings, including with existing cache', () async {
    await configure();
    var generation = 0;
    transport.calls.clear();
    transport.respond = (endpoint, body) async => endpoint == 'offerings'
        ? {
            'currentOffering': 'fresh-${++generation}',
            'offerings': [
              {'identifier': 'fresh-$generation'},
            ],
          }
        : transport.standard(endpoint, body);
    final first = await client.syncAttributesAndOfferingsIfNeeded();
    final second = await client.syncAttributesAndOfferingsIfNeeded();
    expect(first.data?.current?.identifier, 'fresh-1');
    expect(second.data?.current?.identifier, 'fresh-2');
    expect(transport.calls.map((call) => call.endpoint), [
      'offerings',
      'offerings',
    ]);
  });

  test('six concurrent calls admit five executions; denied call returns cache without network or writes', () async {
    await configure();
    transport.calls.clear();
    final results = await Future.wait(
      List.generate(6, (_) => client.syncAttributesAndOfferingsIfNeeded()),
    );
    expect(results.every((result) => result.isSuccess), true);
    expect(
      transport.calls.map((call) => call.endpoint),
      List.filled(5, 'offerings'),
    );
    final writes = store.writes;
    final revision = backend.snapshot.revision;
    transport.calls.clear();
    final cached = await client.syncAttributesAndOfferingsIfNeeded();
    expect(cached.data?.current?.identifier, 'current');
    expect(cached.snapshot?.revision, revision);
    expect(transport.calls, isEmpty);
    expect(store.writes, writes);
  });

  test('failed admissions consume quota; no cache returns Android-shaped rate limit failure', () async {
    await configure();
    transport.respond = (_, _) async => throw const GoV2ProtocolException(
      'NETWORK',
      'OFFLINE',
      retryable: true,
    );
    transport.calls.clear();
    for (var i = 0; i < 5; i++) {
      final result = await client.syncAttributesAndOfferingsIfNeeded();
      expect(result.failure?.code, InappifyFailureCode.network);
      expect(
        result.failure?.details['operation'],
        'syncAttributesAndOfferingsIfNeeded',
      );
    }
    final result = await client.syncAttributesAndOfferingsIfNeeded();
    expect(result.failure?.code, InappifyFailureCode.unknown);
    expect(result.failure?.isRetryable, true);
    expect(
      result.failure?.details,
      containsPair('operation', 'syncAttributesAndOfferingsIfNeeded'),
    );
    expect(result.failure?.details, containsPair('category', 'RATE_LIMIT'));
    expect(
      result.failure?.details,
      containsPair('reason', 'RATE_LIMITED_NO_CACHE'),
    );
    expect(result.failure?.details, containsPair('retryAfterMillis', 60000));
    expect(transport.calls.length, 5);
  });

  test('rolling quota releases individual starts exactly at 60 seconds', () async {
    await configure();
    for (var i = 0; i < 5; i++) {
      elapsed = i * 1000;
      await client.syncAttributesAndOfferingsIfNeeded();
    }
    transport.calls.clear();
    elapsed = 59999;
    await client.syncAttributesAndOfferingsIfNeeded();
    expect(transport.calls, isEmpty);
    elapsed = 60000;
    await client.syncAttributesAndOfferingsIfNeeded();
    await client.syncAttributesAndOfferingsIfNeeded();
    expect(transport.calls.length, 1);
    elapsed = 61000;
    await client.syncAttributesAndOfferingsIfNeeded();
    expect(transport.calls.length, 2);
  });

  test('attribute network failure preserves pending attributes and prevents offerings request', () async {
    await configure();
    await pendingAttributes();
    transport.respond = (_, _) async => throw const GoV2ProtocolException(
      'NETWORK',
      'OFFLINE',
      retryable: true,
    );
    final result = await client.syncAttributesAndOfferingsIfNeeded();
    expect(result.failure?.code, InappifyFailureCode.network);
    expect(transport.calls.map((call) => call.endpoint), ['attributes']);
    expect(saved()['attributes'], {
      'plan': 'premium',
      r'$email': 'fixture@example.test',
    });
    expect(saved()['quarantine'], isNull);
  });

  test('attribute rejection preserves existing quarantine semantics and stops refresh', () async {
    await configure();
    await pendingAttributes();
    transport.respond = (_, _) async => throw const GoV2ProtocolException(
      'VALIDATION',
      'ATTRIBUTES_INVALID',
      details: {'httpStatus': 422},
    );
    final result = await client.syncAttributesAndOfferingsIfNeeded();
    expect(result.failure?.details['serverCode'], 'ATTRIBUTES_INVALID');
    expect(transport.calls.map((call) => call.endpoint), ['attributes']);
    expect(saved()['attributes'], isEmpty);
    expect(saved()['quarantine'], {
      'plan': 'premium',
      r'$email': 'fixture@example.test',
    });
  });

  test('offerings failure after flush returns structured error without requeueing delivered attributes', () async {
    await configure();
    await pendingAttributes();
    transport.respond = (endpoint, body) async {
      if (endpoint == 'offerings') {
        throw const GoV2ProtocolException(
          'TIMEOUT',
          'REQUEST_TIMEOUT',
          retryable: true,
        );
      }
      return transport.standard(endpoint, body);
    };
    final result = await client.syncAttributesAndOfferingsIfNeeded();
    expect(result.failure?.code, InappifyFailureCode.timeout);
    expect(result.failure?.isRetryable, true);
    expect(transport.calls.map((call) => call.endpoint), [
      'attributes',
      'offerings',
    ]);
    expect(saved()['attributes'], isEmpty);
    expect(result.snapshot?.offerings, isNull);
  });

  test('admitted refresh failure stays a failure even when current-session cache exists', () async {
    await configure();
    await client.syncAttributesAndOfferingsIfNeeded();
    transport.respond = (_, _) async => throw const GoV2ProtocolException(
      'NETWORK',
      'OFFLINE',
      retryable: true,
    );
    final result = await client.syncAttributesAndOfferingsIfNeeded();
    expect(result.isSuccess, false);
    expect(result.failure?.code, InappifyFailureCode.network);
    expect(result.snapshot?.offerings?.current?.identifier, 'current');
  });

  test('queued login, configure and logout retain quota and cannot return predecessor cache', () async {
    await configure();
    await syncFive();
    final login = client.login(
      const InappifyLoginRequest(appUserIdentifier: fixture.customUser),
    );
    final afterLogin = client.syncAttributesAndOfferingsIfNeeded();
    expect((await login).isSuccess, true);
    final blocked = await afterLogin;
    expect(blocked.failure?.details['reason'], 'RATE_LIMITED_NO_CACHE');
    expect(blocked.snapshot?.appUserIdentifier, fixture.customUser);
    expect(blocked.snapshot?.offerings, isNull);
    expect(client.state.snapshot.offerings, isNull);
    await configure(fixture.customUser);
    final afterConfigure = await client.syncAttributesAndOfferingsIfNeeded();
    expect(afterConfigure.failure?.details['reason'], 'RATE_LIMITED_NO_CACHE');
    expect((await client.logout()).isSuccess, true);
    transport.calls.clear();
    final afterLogout = await client.syncAttributesAndOfferingsIfNeeded();
    expect(afterLogout.failure?.details['reason'], 'RATE_LIMITED_NO_CACHE');
    expect(afterLogout.snapshot?.appUserIdentifier, fixture.anonymous);
    expect(afterLogout.snapshot?.offerings, isNull);
    expect(transport.calls, isEmpty);
    elapsed = 60000;
    expect((await client.syncAttributesAndOfferingsIfNeeded()).isSuccess, true);
  });

  test('failed login hides old cache and blocks combined sync without network', () async {
    await configure();
    await syncFive();
    transport.respond = (_, _) async => throw const GoV2ProtocolException(
      'NETWORK',
      'OFFLINE',
      retryable: true,
    );
    final login = await client.login(
      const InappifyLoginRequest(appUserIdentifier: fixture.customUser),
    );
    expect(login.isSuccess, false);
    transport.calls.clear();
    final result = await client.syncAttributesAndOfferingsIfNeeded();
    expect(result.failure?.details['serverCode'], 'LOGIN_PENDING');
    expect(result.snapshot?.offerings, isNull);
    expect(result.snapshot?.appUserIdentifier, isNull);
    expect(transport.calls, isEmpty);
  });

  test('unconfigured calls do not consume client quota', () async {
    for (var i = 0; i < 6; i++) {
      final result = await backend.syncAttributesAndOfferingsIfNeeded();
      expect(result.failure?.code, InappifyFailureCode.notConfigured);
    }
    await configure();
    transport.calls.clear();
    await syncFive();
    expect(transport.calls.length, 5);
  });
}
