import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:inappify_sdk/inappify_sdk_platform_interface.dart';
import 'package:inappify_sdk/models/attribute.dart';
import 'package:inappify_sdk/src/platform/mobile/go_v2_infrastructure.dart';
import 'package:inappify_sdk/src/platform/mobile/go_v2_platform.dart';
import 'package:inappify_sdk/src/platform/mobile/go_v2_protocol.dart';

const anonymous = r'$INAAnonymousID:550e8400-e29b-41d4-a716-446655440000';
const customUser = 'account_user_123456';
final now = DateTime.utc(2026, 9, 17);

class MemoryStore extends GoV2Storage {
  String? raw;
  int writes = 0;
  int? failAt;
  @override
  Future<String?> read() async => raw;
  @override
  Future<void> write(String document) async {
    writes++;
    if (writes == failAt) throw StateError('fixture storage failure');
    raw = document;
  }
}

class FakeTransport extends GoV2Transport {
  final calls =
      <
        ({
          String endpoint,
          String? bearer,
          Map<String, Object?> body,
          Map<String, String> headers,
          bool retry,
        })
      >[];
  Future<Map<String, dynamic>> Function(String, Map<String, Object?>)? respond;
  String identity = anonymous;
  String subject = 'internal-123';
  @override
  Stream<Map<String, Object?>> get traces => const Stream.empty();
  @override
  Future<void> close() async {}
  @override
  Future<Map<String, dynamic>> request(
    String endpoint, {
    String? bearer,
    Map<String, Object?> body = const {},
    Map<String, String> headers = const {},
    bool retry = true,
  }) async {
    if (!enabled) {
      throw const GoV2ProtocolException('CONFIGURATION', 'V2_DISABLED');
    }
    calls.add((
      endpoint: endpoint,
      bearer: bearer,
      body: body,
      retry: retry,
      headers: headers,
    ));
    if (respond != null) return respond!(endpoint, body);
    return standard(endpoint, body);
  }

  Map<String, dynamic> standard(String endpoint, Map<String, Object?> body) {
    if (endpoint == 'configure' || endpoint == 'login') {
      identity = body['appUserIdentifier'] as String;
    }
    if (endpoint == 'logout') identity = anonymous;
    if (endpoint == 'offerings') return catalog();
    if (endpoint == 'attributes') return {};
    return envelope(identity, subject: subject);
  }
}

// State-machine fixtures intentionally inject a deterministic verifier. Actual
// Ed25519, malformed JWS/JSON and trust tests are in go_v2_protocol_test.dart.
class StateVerifier extends GoV2Verifier {
  bool reject = false;
  @override
  bool known(String kid) => true;
  @override
  Future<GoV2VerifiedCustomer> verify(
    Map<String, dynamic> envelope, {
    required String expectedPublicUserId,
    Map<String, Object?>? expectedScope,
    String? expectedSubject,
    bool allowExpiredCache = false,
  }) async {
    final customer = Map<String, dynamic>.from(envelope['customerInfo'] as Map);
    final subject = envelope['_testSubject'] as String;
    final scope = <String, Object?>{
      'issuer': 'https://service.inappify.com',
      'appId': 7,
      'projectId': 3,
    };
    if (reject ||
        customer['originalAppUserId'] != expectedPublicUserId ||
        (expectedSubject != null && subject != expectedSubject) ||
        (expectedScope != null &&
            jsonEncode(expectedScope) != jsonEncode(scope))) {
      throw const GoV2ProtocolException('SIGNATURE', 'SCOPE_MISMATCH');
    }
    return GoV2VerifiedCustomer(
      info: customer,
      scope: scope,
      subject: subject,
      expiresAt: now.add(const Duration(days: 1)),
    );
  }
}

Map<String, dynamic> envelope(
  String identity, {
  String subject = 'internal-123',
}) => {
  'status': true,
  'appId': 7,
  'appUserId': identity,
  'sessionType': 'public',
  'sessionToken': 'synthetic-go-token',
  'sessionExpiresAt': '2026-09-18T00:00:00Z',
  'forceVersion': 1,
  'storePlatform': 1,
  'customerInfo': {
    'originalAppUserId': identity,
    'firstSeen': '2026-09-17T00:00:00Z',
    'requestDate': '2026-09-17T00:00:00Z',
    'hasUsedTrial': false,
    'attributes': [
      {'key': 'hidden', 'value': 'not a Go read-back'},
    ],
    'entitlements': [
      {
        'identifier': 'expired',
        'is_active': true,
        'expiration_date': '2026-09-16T00:00:00Z',
      },
    ],
  },
  'verification': {'keyId': 'fixture'},
  '_testSubject': subject,
};
Map<String, dynamic> catalog() => {
  'status': true,
  'hasForceUpdate': false,
  'forceVersion': 2,
  'currentOffering': 'current',
  'placements': {'upgrade': 'placement'},
  'offerings': [
    {'identifier': 'default', 'isDefault': true},
    {'identifier': 'current'},
    {'identifier': 'placement'},
  ],
  'rules': [
    {'invalidV1RuleMustBeIgnored': true},
  ],
};

void main() {
  late MemoryStore store;
  late FakeTransport transport;
  late StateVerifier verifier;
  late GoV2Platform client;
  GoV2Platform makeClient() => GoV2Platform(
    transport: transport,
    storage: store,
    verifier: verifier,
    now: () => now,
    anonymousIdFactory: () => anonymous,
    metadataProvider: () async => const GoV2Metadata(
      identifierValue: 'com.example.fixture',
      versionName: '2.1.0',
      versionCode: 21,
    ),
    backgroundRecovery: false,
  );
  Future<InappifySdkResult<void>> configure() => client.configure(
    const InappifyConfigureRequest(apiKey: 'public-fixture'),
  );

  setUp(() {
    store = MemoryStore();
    transport = FakeTransport();
    verifier = StateVerifier();
    client = makeClient();
  });
  tearDown(() async => client.close());

  test(
    'anonymous identity persisted before HTTP; correct Go body and no token projection',
    () async {
      transport.respond = (endpoint, body) async {
        expect(jsonDecode(store.raw!)['anonymousId'], anonymous);
        return transport.standard(endpoint, body);
      };
      final result = await configure();
      expect(result.isSuccess, true);
      expect(transport.calls.single.body, {
        'appUserIdentifier': anonymous,
        'identifierValue': 'com.example.fixture',
        'versionName': '2.1.0',
        'versionCode': 21,
        'sdkVersion': '0.2.4',
        'country': 'IR',
      });
      expect(transport.calls.single.bearer, 'public-fixture');
      expect(result.snapshot!.accessToken, '');
      expect(result.snapshot!.apiKey, '');
      expect(result.snapshot!.isAuthenticated, false);
      expect(result.snapshot!.customerInfo!.attributes, null);
      expect(
        result.snapshot!.customerInfo!.entitlements.single.isActive,
        false,
      );
      expect(jsonDecode(store.raw!)['customerSubject'], 'internal-123');
    },
  );

  test('Android recovery opt-out adds no iOS Configure wire field', () async {
    final result = await client.configure(
      const InappifyConfigureRequest(
        apiKey: 'public-fixture',
        enableSubscriptionRecoveryWithoutPayload: false,
      ),
    );
    expect(result.isSuccess, isTrue);
    expect(
      transport.calls.single.body.containsKey(
        'enableSubscriptionRecoveryWithoutPayload',
      ),
      isFalse,
    );
    expect(
      store.raw!,
      isNot(contains('enableSubscriptionRecoveryWithoutPayload')),
    );
  });

  test('identity write failure prevents HTTP', () async {
    store.failAt = 1;
    final result = await configure();
    expect(result.failure!.code, InappifyFailureCode.storageUnavailable);
    expect(transport.calls, isEmpty);
  });

  test('verified session write failure does not publish identity', () async {
    store.failAt = 2;
    final result = await configure();
    expect(result.failure!.code, InappifyFailureCode.storageUnavailable);
    expect(result.snapshot!.customerInfo, null);
    expect(jsonDecode(store.raw!)['anonymousId'], anonymous);
    expect(jsonDecode(store.raw!).containsKey('session'), false);
  });

  test('signature failure preserves anonymous identity for retry', () async {
    verifier.reject = true;
    expect(
      (await configure()).failure!.code,
      InappifyFailureCode.malformedResponse,
    );
    verifier.reject = false;
    expect((await configure()).isSuccess, true);
    expect(
      transport.calls.map((e) => e.body['appUserIdentifier']),
      everyElement(anonymous),
    );
  });

  test(
    'restart verifies and restores valid cache without Configure HTTP',
    () async {
      await configure();
      transport.calls.clear();
      final restarted = makeClient();
      final result = await restarted.configure(
        const InappifyConfigureRequest(apiKey: 'public-fixture'),
      );
      expect(result.isSuccess, true);
      expect(transport.calls, isEmpty);
      expect(result.snapshot!.customerInfo!.originalAppUserId, anonymous);
      await restarted.close();
    },
  );

  test('public model mutation cannot poison cached authority', () async {
    final result = await configure();
    result.snapshot!.customerInfo!.attributes = [
      Attribute(key: 'poison', value: 'value'),
    ];
    expect(
      () => result.snapshot!.customerInfo!.entitlements.clear(),
      throwsUnsupportedError,
    );
    final read = await client.customerInfoWithPolicy(
      InappifyFetchPolicy.cacheOnly,
    );
    expect(read.data!.attributes, null);
    expect(read.data!.entitlements, hasLength(1));
  });

  test('changing app API key requires a new instance', () async {
    await configure();
    final result = await client.configure(
      const InappifyConfigureRequest(apiKey: 'different-fixture'),
    );
    expect(
      result.failure!.details['serverCode'],
      'CREATE_NEW_CLIENT_FOR_APP_CHANGE',
    );
    expect(transport.calls, hasLength(1));
  });

  test('cached no-network and network-first fallback are distinct', () async {
    await configure();
    transport.calls.clear();
    expect(
      (await client.customerInfoWithPolicy(
        InappifyFetchPolicy.cacheOnly,
      )).isSuccess,
      true,
    );
    expect(transport.calls, isEmpty);
    transport.respond = (_, _) async => throw const GoV2ProtocolException(
      'NETWORK',
      'OFFLINE',
      retryable: true,
    );
    expect(
      (await client.customerInfoWithPolicy(
        InappifyFetchPolicy.networkOnly,
      )).isSuccess,
      false,
    );
    expect(
      (await client.customerInfoWithPolicy(
        InappifyFetchPolicy.networkFirst,
      )).isSuccess,
      true,
    );
  });

  test('concurrent equivalent customer requests share HTTP', () async {
    await configure();
    transport.calls.clear();
    final gate = Completer<Map<String, dynamic>>();
    transport.respond = (_, _) => gate.future;
    final a = client.customerInfoWithPolicy(InappifyFetchPolicy.networkOnly);
    final b = client.customerInfoWithPolicy(InappifyFetchPolicy.networkOnly);
    await Future<void>.delayed(Duration.zero);
    expect(transport.calls, hasLength(1));
    gate.complete(envelope(anonymous));
    expect((await a).isSuccess, true);
    expect((await b).isSuccess, true);
  });

  test(
    'refresh rejects changed internal subject without replacing old data',
    () async {
      await configure();
      transport.subject = 'different-internal-id';
      final result = await client.customerInfoWithPolicy(
        InappifyFetchPolicy.networkOnly,
      );
      expect(result.failure!.details['serverCode'], 'SCOPE_MISMATCH');
      expect(jsonDecode(store.raw!)['customerSubject'], 'internal-123');
    },
  );

  test(
    'login without configure cannot create an unauthenticated session',
    () async {
      final result = await client.login(
        const InappifyLoginRequest(appUserIdentifier: customUser),
      );
      expect(result.isSuccess, false);
      expect(transport.calls, isEmpty);
      expect(store.raw, isNull);
    },
  );

  test('login changes subject and clears prior attributes/catalog', () async {
    await configure();
    await client.queueAttributes({'previous': 'value'});
    await client.offeringsWithPolicy(InappifyFetchPolicy.networkOnly);
    await client.queueAttributes({'notSent': 'value'});
    transport.subject = 'new-internal-subject';
    final result = await client.login(
      const InappifyLoginRequest(appUserIdentifier: customUser),
    );
    expect(result.isSuccess, true);
    final saved = jsonDecode(store.raw!);
    expect(saved['attributes'], null);
    expect(saved['offerings'], null);
    expect(saved['customerSubject'], 'new-internal-subject');
    expect(transport.calls.last.body, {'appUserIdentifier': customUser});
    expect(transport.calls.last.bearer, 'synthetic-go-token');
    expect(transport.calls.last.retry, true);
    expect(
      transport.calls.last.headers['X-Inappify-Login-Attempt'],
      isNotEmpty,
    );
  });

  test(
    'offline logout hides and persists previous identity, restart recovers logout first',
    () async {
      await configure();
      await client.login(
        const InappifyLoginRequest(appUserIdentifier: customUser),
      );
      transport.respond = (endpoint, body) async {
        if (endpoint == 'logout') {
          throw const GoV2ProtocolException(
            'NETWORK',
            'OFFLINE',
            retryable: true,
          );
        }
        return transport.standard(endpoint, body);
      };
      final result = await client.logout();
      expect(result.isSuccess, false);
      expect(result.snapshot!.customerInfo, null);
      expect(result.snapshot!.isLogoutPending, true);
      expect(jsonDecode(store.raw!)['pendingLogout'], true);
      transport.respond = null;
      transport.calls.clear();
      final restarted = makeClient();
      final recovered = await restarted.configure(
        const InappifyConfigureRequest(apiKey: 'public-fixture'),
      );
      expect(recovered.isSuccess, true);
      expect(transport.calls.first.endpoint, 'logout');
      expect(recovered.snapshot!.customerInfo!.originalAppUserId, anonymous);
      await restarted.close();
    },
  );

  test(
    'write-only attributes batch 50 and coalesce before catalog fetch',
    () async {
      await configure();
      transport.calls.clear();
      await client.queueAttributes({
        for (var i = 0; i < 51; i++) 'field$i': 'a',
      });
      await client.queueAttributes({'field0': 'updated'});
      expect(transport.calls, isEmpty);
      expect(
        (await client.offeringsWithPolicy(
          InappifyFetchPolicy.networkOnly,
        )).isSuccess,
        true,
      );
      expect(transport.calls.map((v) => v.endpoint), [
        'attributes',
        'attributes',
        'offerings',
      ]);
      expect((transport.calls[0].body['attributes'] as Map).length, 50);
      expect(
        (transport.calls[0].body['attributes'] as Map)['field0'],
        'updated',
      );
      expect((transport.calls[1].body['attributes'] as Map).length, 1);
      expect(jsonDecode(store.raw!)['attributes'], isEmpty);
    },
  );

  test(
    '422 quarantines rejected batch; retryable error keeps queued values',
    () async {
      await configure();
      await client.queueAttributes({'a': 'bad'});
      transport.respond = (_, _) async => throw const GoV2ProtocolException(
        'VALIDATION',
        'REJECTED',
        details: {'httpStatus': 422},
      );
      expect((await client.flushAttributes()).isSuccess, false);
      expect(jsonDecode(store.raw!)['attributes'], isEmpty);
      expect(jsonDecode(store.raw!)['quarantine'], {'a': 'bad'});
      await client.queueAttributes({'b': 'pending'});
      transport.respond = (_, _) async => throw const GoV2ProtocolException(
        'NETWORK',
        'OFFLINE',
        retryable: true,
      );
      expect((await client.flushAttributes()).isSuccess, false);
      expect(jsonDecode(store.raw!)['attributes'], {'b': 'pending'});
    },
  );

  test(
    'server placement takes precedence and targeting invalidates catalog',
    () async {
      await configure();
      await client.offeringsWithPolicy(InappifyFetchPolicy.networkOnly);
      final selected = await client.getCurrentOffering(
        InappifyCurrentOfferingRequest(placementIdentifier: 'upgrade'),
      );
      expect(selected.data!.identifier, 'placement');
      await client.setTargetingContext(
        const InappifyTargetingContextRequest(country: 'DE'),
      );
      expect(
        (await client.offeringsWithPolicy(
          InappifyFetchPolicy.cacheOnly,
        )).isSuccess,
        false,
      );
    },
  );

  test(
    'session expiry renews with same public identity before customer request',
    () async {
      await configure();
      final saved = jsonDecode(store.raw!) as Map<String, dynamic>;
      (saved['session'] as Map)['sessionExpiresAt'] = '2026-09-16T00:00:00Z';
      store.raw = jsonEncode(saved);
      transport.calls.clear();
      final restarted = makeClient();
      expect(
        (await restarted.configure(
          const InappifyConfigureRequest(apiKey: 'public-fixture'),
        )).isSuccess,
        true,
      );
      expect(transport.calls.single.body['appUserIdentifier'], anonymous);
      await restarted.close();
    },
  );

  test('no implicit Go to legacy credential bridge', () async {
    await configure();
    final result = await client.purchase(
      const InappifyPurchaseRequest(
        productIdentifier: 'coins',
        offeringIdentifier: 'main',
        idempotencyKey: 'one-attempt',
      ),
    );
    expect(result.failure!.details['serverCode'], 'PRODUCT_NOT_IN_OFFERING');
    expect(transport.calls, hasLength(1));
  });
}
