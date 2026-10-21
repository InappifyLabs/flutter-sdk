import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inappify_sdk/inappify_sdk.dart';
import 'package:inappify_sdk/inappify_sdk_method_channel.dart';
import 'package:inappify_sdk/models/offering_model.dart';
import 'package:inappify_sdk/models/attribute.dart';
import 'package:inappify_sdk/src/platform/channel/channel_contract.dart';
import 'package:inappify_sdk/src/platform/contracts/sdk_requests.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('inappify_sdk');
  late MethodChannelInappifySdk platform;
  late List<MethodCall> calls;

  setUp(() {
    calls = [];
    platform = MethodChannelInappifySdk(methodChannel: channel);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          final args = call.arguments as Map;
          Object? data = <String, Object?>{};
          switch (call.method) {
            case 'sdkGetCustomerInfo':
              data = {
                'entitlements': [],
                'entitlementEvaluationTimeMillis': 2000000000000,
              };
            case 'sdkGetOfferings' || 'sdkSyncAttributesAndOfferingsIfNeeded':
              data = {'offerings': []};
            case 'sdkGetOffering' || 'sdkGetCurrentOffering':
              data = null;
            case 'sdkSetAttributes':
              data = {'attributes': []};
            case 'sdkPurchase':
              data = {
                'purchaseStatus': 'NEEDTOPAY',
                'url': 'https://pay.example.test/',
              };
            case 'sdkHandleDeepLink':
              data = {'value': false};
            case 'sdkSyncPurchases':
              data = {'purchases': []};
            case 'sdkRestorePurchases':
              data = {
                'restoredCount': 1,
                'alreadyProcessedCount': 2,
                'failedCount': 0,
              };
          }
          return {
            'protocolVersion': 1,
            'requestId': args['requestId'],
            'ok': true,
            'data': data,
            'snapshot': const InappifySdkSnapshot().toMap(),
          };
        });
  });

  tearDown(() {
    channel.setMethodCallHandler(null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  Map payload() => (calls.last.arguments as Map)['payload'] as Map;

  test(
    'store purchase names keep their parameter-free wire contract',
    () async {
      final synced = await platform.syncStorePurchases();
      expect(synced.isSuccess, isTrue);
      expect(synced.data, isEmpty);
      expect(calls.last.method, 'sdkSyncPurchases');
      expect(payload(), isEmpty);
      final restored = await platform.restoreStorePurchases();
      expect(restored.isSuccess, isTrue);
      expect(restored.data!.totalCount, 3);
      expect(calls.last.method, 'sdkRestorePurchases');
      expect(payload(), isEmpty);
    },
  );

  test('platform no longer exposes recovery or old purchase aliases', () {
    final dynamic api = platform;
    expect(() => api.recover(), throwsNoSuchMethodError);
    expect(() => api.syncPurchases(), throwsNoSuchMethodError);
    expect(() => api.restorePurchases(), throwsNoSuchMethodError);
    expect(calls, isEmpty);
  });

  test(
    'CustomerInfo default and four policies cross the bridge without a force flag',
    () async {
      await platform.getCustomerInfo(const InappifyRefreshRequest());
      expect(payload(), {'fetchPolicy': 'cachedOrFetched'});
      for (final policy in InappifyCacheFetchPolicy.values) {
        final result = await platform.getCustomerInfo(
          InappifyRefreshRequest(fetchPolicy: policy),
        );
        expect(result.isSuccess, isTrue);
        expect(payload(), {'fetchPolicy': policy.name});
      }
    },
  );

  test(
    'offerings selection and combined sync use independent current commands',
    () async {
      await platform.getOfferings(const InappifyRefreshRequest());
      expect(payload(), isEmpty);
      expect((await platform.getOffering('special_offer')).data, isNull);
      expect(payload(), {'identifier': 'special_offer'});
      await platform.getCurrentOffering(
        InappifyCurrentOfferingRequest(placementIdentifier: 'home'),
      );
      expect(payload(), {'placementIdentifier': 'home'});
      await platform.syncAttributesAndOfferingsIfNeeded();
      expect(calls.last.method, 'sdkSyncAttributesAndOfferingsIfNeeded');
      expect(payload(), isEmpty);
    },
  );

  test(
    'attributes use one map and preserve deletion and the reserved IP key',
    () async {
      await platform.setAttributes(
        InappifyAttributesRequest(
          attributes: [
            // The facade converts its public Map into this internal adapter.
            ...{
              'tier': 'gold',
              'removed': null,
              r'$ip': '1.2.3.4',
            }.entries.map((e) => Attribute(key: e.key, value: e.value)),
          ],
        ),
      );
      expect(payload(), {
        'attributes': {'tier': 'gold', 'removed': null, r'$ip': '1.2.3.4'},
      });
    },
  );

  test(
    'package parent and classification survive round-trip and purchase payload',
    () async {
      final offering = OfferingModel.fromJson({
        'identifier': 'special',
        'packages': [
          {
            'identifier': 'coins',
            'product': {'identifier': 'coins-100', 'productType': 'CONSUMABLE'},
          },
        ],
      });
      final package = PackageModel.fromJson(offering.packages!.single.toJson());
      expect(package.offeringIdentifier, 'special');
      expect(package.product!.productType, InappifyProductType.consumable);
      await platform.purchase(
        InappifyPurchaseRequest(
          productIdentifier: 'coins-100',
          offeringIdentifier: 'special',
          packageIdentifier: 'coins',
          productType: InappifyProductType.consumable,
          packageToPurchase: package,
          idempotencyKey: 'same-attempt',
        ),
      );
      expect(
        payload().keys,
        unorderedEquals(['packageToPurchase', 'idempotencyKey']),
      );
      final selected = payload()['packageToPurchase'] as Map;
      expect(selected['offeringIdentifier'], 'special');
      expect((selected['product'] as Map)['productType'], 'CONSUMABLE');
      expect((calls.last.arguments as Map)['requestId'], 'same-attempt');
    },
  );

  test('native trusted time controls active rights; maps remain read-only', () {
    final info = CustomerInfo.fromJson({
      'entitlementEvaluationTimeMillis': DateTime.utc(
        2040,
      ).millisecondsSinceEpoch,
      'entitlements': [
        {
          'identifier': 'expired',
          'is_active': true,
          'expiration_date': '2039-01-01T00:00:00Z',
        },
        {
          'identifier': 'active',
          'is_active': true,
          'expiration_date': '2041-01-01T00:00:00Z',
        },
        {
          'identifier': 'invalid',
          'is_active': true,
          'expiration_date': 'invalid',
        },
        {'identifier': 'revoked', 'is_active': false},
      ],
    });
    expect(info.entitlements.all, hasLength(4));
    expect(info.entitlements.active.keys, ['active']);
    expect(() => info.entitlements.active.clear(), throwsUnsupportedError);
    expect(() => info.entitlements.clear(), throwsUnsupportedError);
    // Bridge-only clock metadata does not change the persisted model format.
    expect(
      info.toJson().containsKey('entitlementEvaluationTimeMillis'),
      isFalse,
    );
  });

  Future<Object?> deliverToFlutter(Map<String, Object?> value) {
    final result = Completer<Object?>();
    ServicesBinding.instance.channelBuffers.push(
      channel.name,
      channel.codec.encodeMethodCall(
        MethodCall(InappifyChannelContract.consumableDeliveryCallback, value),
      ),
      (reply) => result.complete(channel.codec.decodeEnvelope(reply!)),
    );
    return result.future;
  }

  test(
    'delivery callback waits for durable host result and preserves large identifiers',
    () async {
      final committed = Completer<InappifyDeliveryResult>();
      const id = 9007199254740993;
      await platform.setConsumableDeliveryHandler((delivery) {
        expect(delivery.deliveryId, id);
        return committed.future;
      });
      expect(payload(), {'enabled': true});
      final response = deliverToFlutter({
        'deliveryId': id,
        'productIdentifier': 'coins',
        'source': 'MYKET',
      });
      var completed = false;
      response.then((_) => completed = true);
      await Future<void>.delayed(Duration.zero);
      expect(completed, isFalse);
      committed.complete(InappifyDeliveryResult.delivered);
      expect(await response, 'delivered');
      expect(calls.any((call) => call.method == 'sdkConfirmDelivery'), isFalse);
    },
  );

  test(
    'missing or failing delivery handlers request retry instead of acknowledgement',
    () async {
      final delivery = {
        'deliveryId': 9,
        'productIdentifier': 'coins',
        'source': 'BAZAAR',
      };
      await platform.setConsumableDeliveryHandler(
        (_) async => throw StateError('host unavailable'),
      );
      expect(await deliverToFlutter(delivery), 'retryLater');
      await platform.setConsumableDeliveryHandler(null);
      expect(payload(), {'enabled': false});
      expect(await deliverToFlutter(delivery), 'retryLater');
    },
  );
}
