import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:inappify_sdk/inappify_sdk_platform_interface.dart';
import 'package:inappify_sdk/src/platform/mobile/go_v2_infrastructure.dart';
import 'package:inappify_sdk/src/platform/mobile/go_v2_platform.dart';
import 'package:inappify_sdk/src/platform/mobile/go_v2_protocol.dart';

import 'go_v2_platform_test.dart' as fixture;

void main() {
  late fixture.MemoryStore store;
  late fixture.FakeTransport transport;
  late GoV2Platform client;
  var wall = fixture.now;
  var elapsed = 0;

  GoV2Platform create() => GoV2Platform(
    storage: store,
    transport: transport,
    verifier: fixture.StateVerifier(),
    now: () => wall,
    monotonicMilliseconds: () => elapsed,
    anonymousIdFactory: () => fixture.anonymous,
    backgroundRecovery: false,
    metadataProvider: () async => const GoV2Metadata(
      identifierValue: 'com.example.fixture',
      versionName: '2.1.0',
      versionCode: 21,
    ),
  );
  Future<void> configure() async {
    expect(
      (await client.configure(
        const InappifyConfigureRequest(apiKey: 'public-fixture'),
      )).isSuccess,
      isTrue,
    );
  }

  setUp(() {
    wall = fixture.now;
    elapsed = 0;
    store = fixture.MemoryStore();
    transport = fixture.FakeTransport();
    client = create();
  });
  tearDown(() => client.close());

  test(
    'CustomerInfo public policies preserve cache-only and explicit server failure semantics',
    () async {
      await configure();
      transport.calls.clear();
      expect(
        (await client.getCustomerInfo(
          const InappifyRefreshRequest(
            fetchPolicy: InappifyCacheFetchPolicy.cachedOrFetched,
          ),
        )).isSuccess,
        isTrue,
      );
      expect(
        (await client.getCustomerInfo(
          const InappifyRefreshRequest(
            fetchPolicy: InappifyCacheFetchPolicy.cacheOnly,
          ),
        )).isSuccess,
        isTrue,
      );
      expect(transport.calls, isEmpty);
      transport.respond = (_, _) async =>
          throw const GoV2ProtocolException('NETWORK', 'OFFLINE');
      expect(
        (await client.getCustomerInfo(
          const InappifyRefreshRequest(
            fetchPolicy: InappifyCacheFetchPolicy.fetchCurrent,
          ),
        )).isSuccess,
        isFalse,
      );
      expect(
        (await client.getCustomerInfo(
          const InappifyRefreshRequest(
            fetchPolicy: InappifyCacheFetchPolicy.cacheOnly,
          ),
        )).isSuccess,
        isTrue,
      );
    },
  );

  test(
    'offering CACHE_ONLY miss never waits for an in-flight HTTP fetch',
    () async {
      await configure();
      final gate = Completer<Map<String, dynamic>>();
      transport.respond = (_, _) => gate.future;
      final network = client.offeringsWithPolicy(
        InappifyFetchPolicy.networkOnly,
      );
      await Future<void>.delayed(Duration.zero);
      final cached = await client
          .offeringsWithPolicy(InappifyFetchPolicy.cacheOnly)
          .timeout(const Duration(seconds: 1));
      expect(cached.isSuccess, isFalse);
      expect(cached.failure?.details['serverCode'], 'CACHE_MISS');
      gate.complete(fixture.catalog());
      expect((await network).isSuccess, isTrue);
    },
  );

  test(
    'customer CACHE_ONLY miss never joins an in-flight HTTP fetch',
    () async {
      await configure();
      final saved = jsonDecode(store.raw!) as Map<String, dynamic>;
      saved.remove('info');
      store.raw = jsonEncode(saved);
      await client.close();
      client = create();
      await configure();
      final gate = Completer<Map<String, dynamic>>();
      transport.respond = (_, _) => gate.future;
      final network = client.customerInfoWithPolicy(
        InappifyFetchPolicy.networkOnly,
      );
      await Future<void>.delayed(Duration.zero);
      final cached = await client
          .customerInfoWithPolicy(InappifyFetchPolicy.cacheOnly)
          .timeout(const Duration(seconds: 1));
      expect(cached.failure?.details['serverCode'], 'CACHE_MISS');
      gate.complete(fixture.envelope(fixture.anonymous));
      expect((await network).isSuccess, isTrue);
    },
  );

  for (final offerings in [false, true]) {
    test(
      'shared ${offerings ? 'offering' : 'customer'} HTTP keeps caller-specific fallback policy',
      () async {
        await configure();
        if (offerings) {
          await client.offeringsWithPolicy(InappifyFetchPolicy.networkOnly);
        }
        transport.calls.clear();
        final gate = Completer<Map<String, dynamic>>();
        transport.respond = (_, _) => gate.future;
        final networkFirst = offerings
            ? client.offeringsWithPolicy(InappifyFetchPolicy.networkFirst)
            : client.customerInfoWithPolicy(InappifyFetchPolicy.networkFirst);
        final networkOnly = offerings
            ? client.offeringsWithPolicy(InappifyFetchPolicy.networkOnly)
            : client.customerInfoWithPolicy(InappifyFetchPolicy.networkOnly);
        await Future<void>.delayed(Duration.zero);
        expect(transport.calls, hasLength(1));
        gate.completeError(
          const GoV2ProtocolException('NETWORK', 'OFFLINE', retryable: true),
        );
        expect((await networkFirst).isSuccess, isTrue);
        expect((await networkOnly).isSuccess, isFalse);
      },
    );
  }

  test(
    'invalid cached expiry is never published before online recovery',
    () async {
      await configure();
      final saved = jsonDecode(store.raw!) as Map<String, dynamic>;
      (saved['session'] as Map)['sessionExpiresAt'] = 'malformed-date';
      store.raw = jsonEncode(saved);
      await client.close();
      client = create();
      final gate = Completer<Map<String, dynamic>>();
      transport.respond = (_, _) => gate.future;
      final events = <InappifyPlatformEvent>[];
      final subscription = client.events.listen(events.add);
      final configuring = client.configure(
        const InappifyConfigureRequest(apiKey: 'public-fixture'),
      );
      await Future<void>.delayed(Duration.zero);
      expect(client.snapshot.isConfigured, isFalse);
      expect(
        events.where((event) => event.snapshot?.isConfigured == true),
        isEmpty,
      );
      gate.complete(fixture.envelope(fixture.anonymous));
      expect((await configuring).isSuccess, isTrue);
      await subscription.cancel();
    },
  );

  test(
    'signed server floor prevents wall-clock rollback reviving an entitlement',
    () async {
      await configure();
      wall = fixture.now.subtract(const Duration(days: 7));
      expect(
        client.snapshot.customerInfo!.entitlements.single.isActive,
        isFalse,
      );
    },
  );

  test(
    'monotonic elapsed time expires entitlement even while wall time is frozen',
    () async {
      transport.respond = (endpoint, body) async {
        final response = transport.standard(endpoint, body);
        (response['customerInfo'] as Map)['entitlements'] = [
          {
            'identifier': 'short',
            'is_active': true,
            'expiration_date': fixture.now
                .add(const Duration(minutes: 1))
                .toIso8601String(),
          },
        ];
        return response;
      };
      await configure();
      expect(
        client.snapshot.customerInfo!.entitlements.single.isActive,
        isTrue,
      );
      elapsed = const Duration(minutes: 2).inMilliseconds;
      expect(
        client.snapshot.customerInfo!.entitlements.single.isActive,
        isFalse,
      );
      wall = fixture.now.subtract(const Duration(days: 1));
      expect(
        client.snapshot.customerInfo!.entitlements.single.isActive,
        isFalse,
      );
    },
  );

  test(
    'restart re-establishes the trusted floor only from verified server time',
    () async {
      await configure();
      await client.close();
      wall = fixture.now.subtract(const Duration(days: 7));
      client = create();
      await configure();
      expect(
        client.snapshot.customerInfo!.entitlements.single.isActive,
        isFalse,
      );
    },
  );
}
