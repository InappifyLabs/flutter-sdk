import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:inappify_sdk/inappify_sdk_platform_interface.dart';
import 'package:inappify_sdk/src/platform/mobile/go_v2_platform.dart';
import 'package:inappify_sdk/src/platform/mobile/go_v2_protocol.dart';
import 'go_commerce_fixture.dart' as direct;
import 'go_v2_platform_test.dart' as go;

class Commerce extends go.FakeTransport {
  String scope = 'https://api.inappify.com/app/v2/';
  @override
  String get commerceScope => scope;
}

void main() {
  late go.FakeTransport sdk;
  late Commerce commerce;
  late go.MemoryStore store;
  late go.StateVerifier verifier;
  late GoV2Platform client;
  var generation = 0;
  GoV2Platform create() => GoV2Platform(
    transport: sdk,
    commerceTransport: commerce,
    storage: store,
    verifier: verifier,
    now: () => go.now,
    metadataProvider: () async => direct.metadata,
    backgroundRecovery: false,
  );
  Future<void> configure([String id = go.customUser]) async {
    expect(
      (await client.configure(
        InappifyConfigureRequest(
          apiKey: 'public-fixture',
          appUserIdentifier: id,
        ),
      )).isSuccess,
      true,
    );
    expect(
      (await client.offeringsWithPolicy(
        InappifyFetchPolicy.networkOnly,
      )).isSuccess,
      true,
    );
  }

  setUp(() {
    sdk = go.FakeTransport();
    commerce = Commerce();
    store = go.MemoryStore();
    verifier = go.StateVerifier();
    generation = 0;
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
      if (endpoint == 'configure') {
        response['sessionToken'] = 'session-${++generation}';
      }
      return response;
    };
    commerce.respond = (endpoint, _) async =>
        direct.DirectFakeTransport().standard(endpoint);
    client = create();
  });
  tearDown(() => client.close());

  test(
    'readonly verified scope cannot mutate private session binding',
    () async {
      await configure();
      final configuration = (await client.getConfiguration()).data!;
      final scope = configuration.values['verifiedSessionScope'] as Map;
      expect(() => scope['appId'] = 99, throwsUnsupportedError);
      expect(
        (await client.getConfiguration()).data!.values['verifiedSessionScope'],
        {'issuer': 'https://service.inappify.com', 'appId': 7, 'projectId': 3},
      );
    },
  );

  for (final code in [
    'SESSION_EXPIRED',
    'SESSION_REQUIRED',
    'SESSION_INVALID',
    'SESSION_REVOKED',
    'V2_NOT_AVAILABLE',
  ]) {
    test('SDK resource auth policy $code matches commerce', () async {
      await configure();
      final standard = sdk.respond!;
      var resourceCalls = 0;
      sdk.respond = (endpoint, body) async {
        if (endpoint == 'customerInfo' && ++resourceCalls == 1) {
          throw GoV2ProtocolException(
            'AUTH',
            code,
            details: {'httpStatus': code == 'V2_NOT_AVAILABLE' ? 503 : 401},
          );
        }
        return standard(endpoint, body);
      };
      final result = await client.customerInfoWithPolicy(
        InappifyFetchPolicy.networkOnly,
      );
      expect(result.isSuccess, code == 'SESSION_EXPIRED');
      expect(generation, code == 'SESSION_EXPIRED' ? 2 : 1);
      expect(resourceCalls, code == 'SESSION_EXPIRED' ? 2 : 1);
    });
  }

  test(
    'Direct checkout, pending and ACK use current Bearer and only V2 bodies',
    () async {
      await configure();
      expect((await client.purchase(direct.purchaseRequest)).isSuccess, true);
      final pending = await client.syncPendingConsumables();
      expect(pending.data!.pendingDeliveries.single.deliveryId, 11);
      expect((await client.confirmDelivery(11)).isSuccess, true);
      expect(commerce.calls.map((c) => c.endpoint), [
        'purchase',
        'consumable-deliveries/pending',
        'consumable-deliveries/11/delivered',
      ]);
      expect(commerce.calls.map((c) => c.bearer), everyElement('session-1'));
      expect(commerce.calls.map((c) => c.retry), everyElement(false));
      expect(commerce.calls.first.body, {
        'productIdentifier': 'coins',
        'offeringIdentifier': 'main',
        'isCrypto': false,
      });
      expect(commerce.calls.skip(1).map((c) => c.body), everyElement(isEmpty));
      expect(client.snapshot.accessToken, '');
    },
  );

  for (final endpoint in [
    'purchase',
    'consumable-deliveries/pending',
    'consumable-deliveries/11/delivered',
  ]) {
    test(
      '$endpoint renews once on 401 EXPIRED and persists before replay',
      () async {
        await configure();
        if (endpoint.endsWith('/delivered')) {
          await client.syncPendingConsumables();
        }
        commerce.calls.clear();
        var attempts = 0;
        commerce.respond = (path, _) async {
          if (path == endpoint && ++attempts == 1) {
            throw const GoV2ProtocolException(
              'AUTH',
              'SESSION_EXPIRED',
              details: {'httpStatus': 401},
            );
          }
          expect(
            (jsonDecode(store.raw!) as Map)['session']['sessionToken'],
            'session-2',
          );
          return direct.DirectFakeTransport().standard(path);
        };
        final result = endpoint == 'purchase'
            ? await client.purchase(direct.purchaseRequest)
            : endpoint.endsWith('/pending')
            ? await client.syncPendingConsumables()
            : await client.confirmDelivery(11);
        expect(result.isSuccess, true, reason: '${result.failure}');
        expect(commerce.calls.map((c) => c.bearer), ['session-1', 'session-2']);
        expect(commerce.calls.first.body, commerce.calls.last.body);
        expect(
          sdk.calls.where((c) => c.endpoint == 'configure').last.retry,
          false,
        );
      },
    );
  }

  for (final code in [
    'SESSION_REQUIRED',
    'SESSION_INVALID',
    'SESSION_REVOKED',
    'V2_NOT_AVAILABLE',
  ]) {
    test('$code cannot renew session or retry checkout', () async {
      await configure();
      commerce.respond = (_, _) async => throw GoV2ProtocolException(
        'AUTH',
        code,
        details: {'httpStatus': code == 'V2_NOT_AVAILABLE' ? 503 : 401},
      );
      final result = await client.purchase(direct.purchaseRequest);
      expect(result.isSuccess, false);
      expect(generation, 1);
      expect(commerce.calls, hasLength(1));
    });
  }

  test('second EXPIRED and wrong-status EXPIRED never loop', () async {
    await configure();
    commerce.respond = (_, _) async => throw const GoV2ProtocolException(
      'AUTH',
      'SESSION_EXPIRED',
      details: {'httpStatus': 401},
    );
    expect((await client.purchase(direct.purchaseRequest)).isSuccess, false);
    expect(generation, 2);
    expect(commerce.calls, hasLength(2));
    await client.offeringsWithPolicy(InappifyFetchPolicy.networkOnly);
    commerce.calls.clear();
    commerce.respond = (_, _) async => throw const GoV2ProtocolException(
      'AUTH',
      'SESSION_EXPIRED',
      details: {'httpStatus': 403},
    );
    expect((await client.purchase(direct.purchaseRequest)).isSuccess, false);
    expect(generation, 2);
    expect(commerce.calls, hasLength(1));
  });

  for (final broken in ['signature', 'storage', 'route']) {
    test(
      'renewal $broken failure cannot send checkout with uncommitted session',
      () async {
        await configure();
        commerce.respond = (_, _) async {
          if (broken == 'signature') verifier.reject = true;
          if (broken == 'storage') store.failAt = store.writes + 1;
          if (broken == 'route') {
            sdk.respond = (endpoint, body) async =>
                sdk.standard(endpoint, body)..['storePlatform'] = 11;
          }
          throw const GoV2ProtocolException(
            'AUTH',
            'SESSION_EXPIRED',
            details: {'httpStatus': 401},
          );
        };
        expect(
          (await client.purchase(direct.purchaseRequest)).isSuccess,
          false,
        );
        expect(commerce.calls, hasLength(1));
      },
    );
  }

  test(
    'lost ACK survives restart and retries even with an empty server pending list',
    () async {
      await configure();
      await client.syncPendingConsumables();
      commerce.respond = (_, _) async =>
          throw const GoV2ProtocolException('TIMEOUT', 'TIMEOUT');
      final failed = await client.confirmDelivery(11);
      expect(failed.failure!.details['outcomeMayHaveCommitted'], true);
      expect(
        commerce.calls.where((c) => c.endpoint.endsWith('/delivered')),
        hasLength(1),
      );
      await client.close();
      client = create();
      commerce.calls.clear();
      commerce.respond = (endpoint, _) async => endpoint.endsWith('/pending')
          ? {
              'status': true,
              'data': {'deliveries': []},
            }
          : direct.DirectFakeTransport().standard(endpoint);
      await configure();
      final sync = await client.syncPendingConsumables();
      expect(sync.isSuccess, true, reason: '${sync.failure}');
      expect(sync.data!.completedCount, 1);
      expect(sync.data!.pendingDeliveries, isEmpty);
      expect(commerce.calls.map((c) => c.endpoint), [
        'consumable-deliveries/11/delivered',
        'consumable-deliveries/pending',
      ]);
      expect((await client.confirmDelivery(11)).isSuccess, true);
      expect(commerce.calls, hasLength(2));
    },
  );

  for (final change in ['account', 'endpoint']) {
    test('$change never replays another scope delivery', () async {
      await configure();
      await client.syncPendingConsumables();
      commerce.calls.clear();
      if (change == 'endpoint') {
        await client.close();
        commerce.scope = 'https://other.example.test/app/v2/';
        client = create();
        await configure();
      } else {
        expect(
          (await client.login(
            const InappifyLoginRequest(appUserIdentifier: 'another-user',),
          )).isSuccess,
          true,
        );
      }
      expect(
        (await client.confirmDelivery(11)).failure!.details['serverCode'],
        'DELIVERY_NOT_FOUND',
      );
      expect(commerce.calls, isEmpty);
    });
  }

  for (final invalid in ['id', 'product', 'transaction', 'state']) {
    test('mismatched ACK $invalid stays pending in durable journal', () async {
      await configure();
      await client.syncPendingConsumables();
      final data = direct.delivery(completed: true);
      if (invalid == 'id') data['deliveryId'] = 12;
      if (invalid == 'product') data['productIdentifier'] = 'different';
      if (invalid == 'transaction') data['transactionId'] = 'different';
      if (invalid == 'state') {
        data['status'] = 'DELIVERY_REQUIRED';
        data['alreadyDelivered'] = false;
      }
      commerce.respond = (_, _) async => {'status': true, 'data': data};
      expect((await client.confirmDelivery(11)).isSuccess, false);
      final record = jsonDecode(
        store.raw!,
      )['directDeliveries']['records']['11'];
      expect(record['delivery']['status'], 'DELIVERY_REQUIRED');
      expect(record['hostDelivered'], true);
    });
  }

  test(
    'failed grant marker storage prevents ACK; unknown delivery cannot be confirmed',
    () async {
      await configure();
      expect((await client.confirmDelivery(11)).isSuccess, false);
      expect(commerce.calls, isEmpty);
      await client.syncPendingConsumables();
      commerce.calls.clear();
      store.failAt = store.writes + 1;
      expect((await client.confirmDelivery(11)).isSuccess, false);
      expect(commerce.calls, isEmpty);
    },
  );

  test(
    'network switch blocks pending deliveries and checkout',
    () async {
      await configure();
      await client.setNetworkEnabled(false);
      expect((await client.syncPendingConsumables()).isSuccess, false);
      expect((await client.purchase(direct.purchaseRequest)).isSuccess, false);
      expect(commerce.calls, isEmpty);
    },
  );

  test(
    'financial success survives subsequent customer refresh failure',
    () async {
      await configure();
      sdk.respond = (_, _) async =>
          throw const GoV2ProtocolException('NETWORK', 'OFFLINE');
      expect((await client.purchase(direct.purchaseRequest)).isSuccess, true);
    },
  );
}
