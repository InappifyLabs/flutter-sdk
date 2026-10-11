import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:inappify_sdk/inappify_sdk_platform_interface.dart';
import 'package:inappify_sdk/models/enums/purchase_status.dart';
import 'package:inappify_sdk/src/application/inappify_coordinator.dart';
import 'package:inappify_sdk/src/platform/mobile/go_v2_platform.dart';
import 'package:inappify_sdk/src/platform/mobile/go_v2_protocol.dart';

import 'go_commerce_fixture.dart' as direct;
import 'go_v2_platform_test.dart' as fixture;

class _Unavailable extends InappifySdkPlatform {}

// Shared contract vectors mirror Android 2.2.0. They never contact a backend,
// perform billing, or replace the real Ed25519 tests in go_v2_protocol_test.dart.
void main() {
  late fixture.MemoryStore store;
  late fixture.FakeTransport sdk;
  late fixture.FakeTransport commerce;
  late fixture.StateVerifier verifier;
  late GoV2Platform client;
  var attempt = 0;
  GoV2Platform create() => GoV2Platform(
    transport: sdk,
    commerceTransport: commerce,
    storage: store,
    verifier: verifier,
    now: () => fixture.now,
    metadataProvider: () async => direct.metadata,
    anonymousIdFactory: () => fixture.anonymous,
    attemptIdFactory: () => 'attempt-${++attempt}',
    backgroundRecovery: false,
  );
  Future<void> configure({
    String? identity,
    String? country,
    String? version,
  }) async {
    final result = await client.configure(
      InappifyConfigureRequest(
        apiKey: 'public-fixture',
        appUserIdentifier: identity,
        country: country,
        appVersion: version,
      ),
    );
    expect(result.isSuccess, true, reason: '${result.failure}');
  }

  Future<void> catalog() async {
    expect(
      (await client.offeringsWithPolicy(
        InappifyFetchPolicy.networkOnly,
      )).isSuccess,
      true,
    );
  }

  Future<void> restart() async {
    await client.close();
    client = create();
  }

  Map<String, dynamic> saved() =>
      jsonDecode(store.raw!) as Map<String, dynamic>;
  Future<InappifySdkResult<void>> login([String identity = '123']) =>
      client.login(
        InappifyLoginRequest(
          apiKey: 'public-fixture',
          appUserIdentifier: identity,
        ),
      );
  const purchase = InappifyPurchaseRequest(
    productIdentifier: 'coins',
    offeringIdentifier: 'main',
    idempotencyKey: 'checkout-1',
    productType: InappifyProductType.consumable,
    paywallId: 17,
    paywallRevision: 2,
  );

  setUp(() {
    store = fixture.MemoryStore();
    sdk = fixture.FakeTransport();
    commerce = fixture.FakeTransport();
    verifier = fixture.StateVerifier();
    attempt = 0;
    sdk.respond = (endpoint, body) async {
      if (endpoint == 'offerings') {
        return {
          'status': true,
          'offerings': direct.offerings
              .toJson()['offerings']!
              .map((dynamic item) => item.toJson())
              .toList(),
        };
      }
      final response = sdk.standard(endpoint, body);
      response.remove('forceVersion');
      return response;
    };
    commerce.respond = (endpoint, _) async => endpoint.endsWith('/pending')
        ? {'status': true, 'data': {'deliveries': []}} : {
      'status': true,
      'data': {
        'purchaseStatus': 'NEEDTOPAY',
        'url': 'https://pay.inappify.com/fixture',
      },
    };
    client = create();
  });
  tearDown(() => client.close());

  for (final logout in [false, true]) {
    test(
      'coordinator hides Go predecessor immediately while ${logout ? 'Logout' : 'Login'} HTTP is pending',
      () async {
        final original = InappifySdkPlatform.instance;
        InappifySdkPlatform.instance = _Unavailable();
        final coordinator = InappifyCoordinator(
          fallbackPlatform: _Unavailable(),
          goPlatformFactory: () => client,
        );
        addTearDown(() async {
          await coordinator.resetForTesting();
          InappifySdkPlatform.instance = original;
        });
        expect(
          (await coordinator.configure(
            const InappifyConfigureRequest(
              apiKey: 'public-fixture',
              mobileProtocol: InappifyMobileProtocol.goV2,
            ),
          )).isSuccess,
          true,
        );
        final gate = Completer<Map<String, dynamic>>();
        sdk.respond = (_, _) => gate.future;
        final operation = logout
            ? coordinator.logout()
            : coordinator.login(
                const InappifyLoginRequest(
                  apiKey: 'public-fixture',
                  appUserIdentifier: '123',
                ),
              );
        await Future<void>.delayed(Duration.zero);
        final pending = coordinator.state.snapshot;
        // Always finish the operation before assertions to leave no pending test work.
        gate.complete(fixture.envelope(logout ? fixture.anonymous : '123'));
        expect((await operation).isSuccess, true);
        expect(pending.isConfigured, false);
        expect(pending.customerInfo, null);
        expect(
          coordinator.state.snapshot.appUserIdentifier,
          logout ? fixture.anonymous : '123',
        );
      },
    );
  }

  test(
    'Go config/catalog need no V1 fields; old fields never escape cache',
    () async {
      await configure(country: ' ir ');
      await catalog();
      expect(sdk.calls.first.body['country'], 'IR');
      expect(sdk.calls.first.body['sdkVersion'], '0.1.0');
      expect(sdk.calls.last.endpoint, 'offerings');
      expect(sdk.calls.last.body['sdkVersion'], '0.1.0');
      expect(sdk.calls.last.body.containsKey('forceVersion'), false);
      expect(client.snapshot.forceVersion, null);
      expect(client.snapshot.offerings!.forceVersion, null);
      expect(
        (await client.getConfiguration()).data!.values['hasForceUpdate'],
        false,
      );
      final old = saved();
      for (final key in ['session', 'info', 'offerings']) {
        (old[key] as Map)['forceVersion'] = 77;
        (old[key] as Map)['hasForceUpdate'] = true;
      }
      store.raw = jsonEncode(old);
      await restart();
      sdk.calls.clear();
      await configure();
      expect(sdk.calls, isEmpty);
      expect(client.snapshot.forceVersion, null);
      expect(client.snapshot.offerings!.forceVersion, null);
      expect(
        (await client.getConfiguration()).data!.values['hasForceUpdate'],
        false,
      );
    },
  );

  for (final identity in [
    '1',
    '123456789',
    'کاربر-۱۲۳',
    'a b',
    '😀' * 100,
    r'$INAAnonymousID:550E8400-E29B-41D4-A716-446655440000',
  ]) {
    test(
      'Go accepts exact Unicode/numeric/old anonymous identity: ${identity.length}',
      () async {
        await configure(identity: identity);
        expect(sdk.calls.single.body['appUserIdentifier'], identity);
        expect(client.snapshot.appUserIdentifier, identity);
      },
    );
  }
  for (final identity in [
    '',
    ' user',
    'user ',
    '\u00a0user',
    'a\u0000b',
    'a\u0085b',
    '\ud800',
    '\udc00',
    '😀' * 101,
    r'$inaanonymousid:invalid',
    r'$INAAnonymousID_invalid',
  ]) {
    test(
      'Go rejects malformed/reserved identity before HTTP: ${identity.hashCode}',
      () async {
        final result = await client.configure(
          InappifyConfigureRequest(
            apiKey: 'public-fixture',
            appUserIdentifier: identity,
          ),
        );
        expect(result.failure!.details['serverCode'], 'APP_USER_ID_INVALID');
        expect(sdk.calls, isEmpty);
        expect(store.raw, null);
      },
    );
  }

  test(
    'context change invalidates catalog durably even if Configure fails',
    () async {
      await configure();
      await catalog();
      sdk.respond = (_, _) async =>
          throw const GoV2ProtocolException('NETWORK', 'OFFLINE');
      final request = InappifyConfigureRequest(
        apiKey: 'public-fixture',
        country: 'de',
        appVersion: '3.0',
      );
      expect((await client.configure(request)).isSuccess, false);
      expect(client.snapshot.offerings, null);
      expect(client.snapshot.customerInfo, isNotNull);
      expect(saved()['offerings'], null);
      expect(saved()['country'], 'IR');
      final before = sdk.calls.length;
      expect((await client.configure(request)).isSuccess, false);
      expect(sdk.calls.length, before + 1);
      expect(sdk.calls.last.body['country'], 'DE');
      sdk.respond = (endpoint, body) async => sdk.standard(endpoint, body);
      expect((await client.configure(request)).isSuccess, true);
      expect(client.snapshot.country, 'DE');
      expect(client.snapshot.versionName, '3.0');
    },
  );

  for (final logout in [false, true]) {
    final endpoint = logout ? 'logout' : 'login';
    final header = logout
        ? 'X-Inappify-Logout-Attempt'
        : 'X-Inappify-Login-Attempt';
    test(
      '$endpoint final storage failure retains the attempt for exact restart replay',
      () async {
        await configure();
        store.failAt =
            store.writes +
            2; // intent succeeds; signed response fails to persist
        final result = await (logout ? client.logout() : login());
        expect(result.failure!.code, InappifyFailureCode.storageUnavailable);
        expect(client.snapshot.customerInfo, null);
        final failed = sdk.calls.last;
        await restart();
        sdk.calls.clear();
        await configure();
        expect(sdk.calls.single.headers[header], failed.headers[header]);
        expect(sdk.calls.single.bearer, failed.bearer);
      },
    );

    test(
      '$endpoint malformed pending cache stays blocked without identity rotation',
      () async {
        await configure();
        final old = saved();
        if (logout) {
          old['pendingLogout'] = true;
          old['pendingLogoutAttempt'] = {'attemptId': 12};
        } else {
          old['pendingLogin'] = {'appUserId': '123', 'attemptId': 12};
        }
        store.raw = jsonEncode(old);
        await restart();
        sdk.calls.clear();
        final result = await client.configure(
          const InappifyConfigureRequest(apiKey: 'public-fixture'),
        );
        expect(result.isSuccess, false);
        expect(client.snapshot.customerInfo, null);
        expect(sdk.calls, isEmpty);
        expect(saved()['session']['appUserId'], fixture.anonymous);
      },
    );
    test(
      '$endpoint persists before HTTP, hides cache, replays same predecessor on restart',
      () async {
        await configure();
        await catalog();
        sdk.respond = (path, body) async {
          expect(path, endpoint);
          expect(saved()[logout ? 'pendingLogout' : 'pendingLogin'], isNotNull);
          expect(client.snapshot.isConfigured, false);
          expect(client.snapshot.customerInfo, null);
          expect(client.verifiedScope, null);
          throw const GoV2ProtocolException(
            'NETWORK',
            'OFFLINE',
            retryable: true,
          );
        };
        expect((await (logout ? client.logout() : login())).isSuccess, false);
        final first = sdk.calls.last;
        expect(first.headers[header], isNotEmpty);
        expect(
          client.snapshot.sessionState,
          InappifySessionState.recoveryRequired,
        );
        expect(
          (await client.customerInfoWithPolicy(
            InappifyFetchPolicy.cacheOnly,
          )).isSuccess,
          false,
        );
        expect(
          (await client.offeringsWithPolicy(
            InappifyFetchPolicy.networkOnly,
          )).isSuccess,
          false,
        );
        expect((await client.purchase(purchase)).isSuccess, false);
        // An expired predecessor is intentionally replayed instead of renewed.
        final old = saved();
        (old['session'] as Map)['sessionExpiresAt'] = '2026-09-16T00:00:00Z';
        store.raw = jsonEncode(old);
        await restart();
        sdk.respond = null;
        sdk.calls.clear();
        await configure();
        expect(sdk.calls.single.endpoint, endpoint);
        expect(sdk.calls.single.headers[header], first.headers[header]);
        expect(sdk.calls.single.bearer, first.bearer);
        expect(
          client.snapshot.appUserIdentifier,
          logout ? fixture.anonymous : '123',
        );
        expect(
          saved().containsKey(logout ? 'pendingLogout' : 'pendingLogin'),
          false,
        );
      },
    );

    test(
      '$endpoint disabled network does not create an unsent barrier',
      () async {
        await configure();
        final before = store.raw;
        sdk.calls.clear();
        await client.setNetworkEnabled(false);
        expect(
          (await (logout ? client.logout() : login()))
              .failure!
              .details['serverCode'],
          'V2_DISABLED',
        );
        expect(store.raw, before);
        expect(client.snapshot.isConfigured, true);
        expect(sdk.calls, isEmpty);
      },
    );

    test(
      '$endpoint storage failure blocks the request before transition',
      () async {
        await configure();
        store.failAt = store.writes + 1;
        sdk.calls.clear();
        expect(
          (await (logout ? client.logout() : login())).failure!.code,
          InappifyFailureCode.storageUnavailable,
        );
        expect(sdk.calls, isEmpty);
        expect(client.snapshot.isConfigured, true);
      },
    );

    test(
      '$endpoint rejected signature preserves a durable recovery barrier',
      () async {
        await configure();
        verifier.reject = true;
        expect((await (logout ? client.logout() : login())).isSuccess, false);
        expect(client.snapshot.isConfigured, false);
        expect(saved()[logout ? 'pendingLogout' : 'pendingLogin'], isNotNull);
      },
    );

    test(
      '$endpoint missing server attempt renews predecessor under barrier exactly once',
      () async {
        await configure();
        sdk.calls.clear();
        var calls = 0;
        sdk.respond = (path, body) async {
          expect(client.snapshot.customerInfo, null);
          if (path == endpoint && calls++ == 0) {
            throw GoV2ProtocolException(
              'AUTH',
              '${endpoint.toUpperCase()}_ATTEMPT_NOT_FOUND',
            );
          }
          return sdk.standard(path, body);
        };
        expect((await (logout ? client.logout() : login())).isSuccess, true);
        expect(sdk.calls.map((c) => c.endpoint), [
          endpoint,
          'configure',
          endpoint,
        ]);
        expect(sdk.calls[0].headers, sdk.calls[2].headers);
        expect(sdk.calls[1].body['appUserIdentifier'], fixture.anonymous);
      },
    );
  }

  test('pending login blocks a different account and logout', () async {
    await configure();
    sdk.respond = (_, _) async =>
        throw const GoV2ProtocolException('NETWORK', 'OFFLINE');
    await login();
    sdk.calls.clear();
    expect(
      (await login('456')).failure!.details['serverCode'],
      'LOGIN_PENDING',
    );
    expect(
      (await client.logout()).failure!.details['serverCode'],
      'LOGIN_PENDING',
    );
    expect(sdk.calls, isEmpty);
    sdk.respond = null;
    expect((await client.recover()).isSuccess, true);
    expect(sdk.calls.first.endpoint, 'login');
  });

  for (final code in ['APP_USER_ID_INVALID', 'CUSTOMER_MERGE_FAILED']) {
    test('proven precommit login failure $code releases predecessor', () async {
      await configure();
      sdk.respond = (_, _) async =>
          throw GoV2ProtocolException('VALIDATION', code);
      expect((await login()).isSuccess, false);
      expect(client.snapshot.appUserIdentifier, fixture.anonymous);
      expect(saved().containsKey('pendingLogin'), false);
    });
  }

  for (final missingToken in [false, true]) {
    test(
      'old boolean logout migration works; missing token=$missingToken',
      () async {
        await configure(identity: '123');
        final old = saved()..['pendingLogout'] = true;
        if (missingToken) {
          old['sessionInvalid'] = true;
          (old['session'] as Map).remove('sessionToken');
        }
        store.raw = jsonEncode(old);
        await restart();
        sdk.calls.clear();
        sdk.respond = (endpoint, body) async {
          expect(client.snapshot.customerInfo, null);
          expect(saved()['pendingLogoutAttempt'], isNotNull);
          return sdk.standard(endpoint, body);
        };
        await configure();
        expect(
          sdk.calls.map((c) => c.endpoint),
          missingToken ? ['configure', 'logout'] : ['logout'],
        );
        expect(sdk.calls.last.headers['X-Inappify-Logout-Attempt'], isNotEmpty);
        expect(client.snapshot.isAuthenticated, false);
      },
    );
  }

  test(
    'revoked logout predecessor recovers through signed anonymous Configure',
    () async {
      await configure(identity: '123');
      sdk.calls.clear();
      sdk.respond = (endpoint, body) async {
        if (endpoint == 'logout') {
          throw const GoV2ProtocolException('AUTH', 'SESSION_REVOKED');
        }
        expect(client.snapshot.customerInfo, null);
        return sdk.standard(endpoint, body);
      };
      expect((await client.logout()).isSuccess, true);
      expect(sdk.calls.map((c) => c.endpoint), ['logout', 'configure']);
      expect(client.snapshot.isAuthenticated, false);
      expect(saved()['pendingLogoutAttempt'], null);
    },
  );

  test(
    'native Go Direct checkout uses commerce Bearer and no legacy credentials',
    () async {
      await configure();
      await catalog();
      sdk.calls.clear();
      final result = await client.purchase(purchase);
      expect(result.isSuccess, true);
      expect(result.data!.purchaseStatus, PurchaseStatus.NEEDTOPAY);
      expect(result.data!.mobile!.requiresDelivery, false);
      expect(result.data!.mobile!.idempotencyKey, 'checkout-1');
      expect(commerce.calls.single.endpoint, 'purchase');
      expect(commerce.calls.single.bearer, 'synthetic-go-token');
      expect(commerce.calls.single.retry, false);
      expect(commerce.calls.single.body, {
        'productIdentifier': 'coins',
        'offeringIdentifier': 'main',
        'isCrypto': false,
        'paywallId': 17,
        'paywallRevision': 2,
      });
      expect(sdk.calls.single.endpoint, 'customerInfo');
      expect(
        (await client.confirmDelivery(11)).failure!.details['serverCode'],
        'DELIVERY_NOT_FOUND',
      );
    },
  );

  for (final field in [
    'country',
    'appVersion',
    'discount',
    'discountCode',
    'apiKey',
    'dynamicPriceToken',
    'isLostPurchase',
    'attempt',
    'attribution',
  ]) {
    test(
      'unbound checkout rejects $field override before commerce HTTP',
      () async {
        await configure();
        await catalog();
        final result = await client.purchase(
          InappifyPurchaseRequest(
            productIdentifier: 'coins',
            offeringIdentifier: 'main',
            idempotencyKey: field == 'attempt' ? 'invalid attempt' : 'a',
            country: field == 'country' ? 'DE' : null,
            appVersion: field == 'appVersion' ? '3.0' : null,
            discount: field == 'discount' ? 1 : 0,
            discountCode: field == 'discountCode' ? 'offer' : null,
            apiKey: field == 'apiKey' ? 'unexpected' : null,
            dynamicPriceToken: field == 'dynamicPriceToken'
                ? 'unexpected'
                : null,
            isLostPurchase: field == 'isLostPurchase',
            paywallId: field == 'attribution' ? 1 : null,
          ),
        );
        expect(result.isSuccess, false);
        expect(commerce.calls, isEmpty);
      },
    );
  }

  for (final type in [null, ...InappifyProductType.values]) {
    test(
      'Direct Go preserves checkout contract for product type $type',
      () async {
        await configure();
        await catalog();
        final result = await client.purchase(
          InappifyPurchaseRequest(
            productIdentifier: 'coins',
            offeringIdentifier: 'main',
            idempotencyKey: 'a',
            productType: type,
          ),
        );
        expect(result.isSuccess, true);
        expect(result.data!.purchaseStatus, PurchaseStatus.NEEDTOPAY);
        expect(result.data!.mobile!.requiresDelivery, false);
        expect(commerce.calls.single.body.containsKey('productType'), false);
      },
    );
  }

  for (final data in <Map<String, Object?>>[
    {'purchaseStatus': 'DONE'},
    {'purchaseStatus': 'UNKNOWN'},
    {'purchaseStatus': true},
    {'purchaseStatus': 'NEEDTOPAY'},
    {'purchaseStatus': 'NEEDTOPAY', 'url': 123},
    {
      'purchaseStatus': 'NEEDTOPAY',
      'url': 'https://untrusted.example.test/pay',
    },
  ]) {
    test('strict checkout status and URL: $data', () async {
      await configure();
      await catalog();
      commerce.respond = (endpoint, _) async => endpoint.endsWith('/pending')
        ? {'status': true, 'data': {'deliveries': []}} : {'status': true, 'data': data};
      final result = await client.purchase(purchase);
      expect(result.isSuccess, data['purchaseStatus'] == 'DONE');
      expect(commerce.calls, hasLength(1));
      if (!result.isSuccess) {
        expect(result.failure!.details['outcomeMayHaveCommitted'], true);
      }
    });
  }

  test(
    'uncertain checkout is not retried; failures never become a grant',
    () async {
      await configure();
      await catalog();
      commerce.respond = (_, _) async => throw const GoV2ProtocolException(
        'TIMEOUT',
        'TIMEOUT',
        retryable: true,
      );
      final result = await client.purchase(purchase);
      expect(result.isSuccess, false);
      expect(result.failure!.details['outcomeMayHaveCommitted'], true);
      expect(commerce.calls.single.retry, false);
    },
  );

  test(
    'network kill switch blocks commerce, cache remains available',
    () async {
      await configure();
      await catalog();
      await client.setNetworkEnabled(false);
      expect(
        (await client.purchase(purchase)).failure!.details['serverCode'],
        'V2_DISABLED',
      );
      expect(commerce.calls, isEmpty);
      expect(client.snapshot.customerInfo, isNotNull);
      expect(client.snapshot.offerings, isNotNull);
    },
  );

  test('commerce checkout uses the selected Go session', () async {
    await configure(identity: fixture.customUser);
    await catalog();
    expect((await client.purchase(purchase)).isSuccess, true);
    expect(commerce.calls.single.endpoint, 'purchase');
    expect(commerce.calls.single.bearer, 'synthetic-go-token');
  });

  test(
    'close during response prevents late session publication or storage',
    () async {
      await configure();
      final before = store.raw;
      final gate = Completer<Map<String, dynamic>>();
      sdk.respond = (_, _) => gate.future;
      final request = client.customerInfoWithPolicy(
        InappifyFetchPolicy.networkOnly,
      );
      await Future<void>.delayed(Duration.zero);
      await client.close();
      gate.complete(fixture.envelope(fixture.anonymous));
      expect((await request).failure!.details['serverCode'], 'CLIENT_CLOSED');
      expect(store.raw, before);
    },
  );
}
