import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inappify_sdk/inappify_sdk_method_channel.dart';
import 'package:inappify_sdk/inappify_sdk_platform_interface.dart';
import 'package:inappify_sdk/models/enums/market.dart';
import 'package:inappify_sdk/src/platform/mobile/native_required_platform.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('synthetic-myket-android');
  const deliveryId = 9007199254740993;
  final calls = <MethodCall>[];
  late MethodChannelInappifySdk platform;
  late InappifyMobileProtocol protocol;
  bool rejectPurchase = false;

  Map<String, Object?> snapshot() => InappifySdkSnapshot(
    sdkVersion: '0.1.1',
    revision: 1,
    isConfigured: true,
    market: 'myket',
    storePlatform: 11,
    mobileProtocol: protocol,
  ).toMap();

  Map<String, Object?> purchase(String status) => {
    'mobile': {
      'market': 'myket',
      'idempotencyKey': 'same-attempt',
      'productIdentifier': 'coins',
      'offeringIdentifier': 'main',
      'storePurchaseStatus': status,
      'deliveryId': deliveryId,
      'verificationRequestId': '31',
    },
  };

  setUp(() {
    calls.clear();
    rejectPurchase = false;
    protocol = InappifyMobileProtocol.goV2;
    platform = MethodChannelInappifySdk(methodChannel: channel);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          final envelope = call.arguments as Map;
          final payload = envelope['payload'] as Map;
          final rejected = call.method == 'sdkPurchase' && rejectPurchase;
          final data = switch (call.method) {
            'sdkConfigure' => <String, Object?>{},
            'sdkRestoreCachedSession' => {'value': true},
            'sdkPurchase' => purchase('DELIVERY_REQUIRED'),
            'sdkSyncPurchases' => {
              'purchases': [purchase('DELIVERY_REQUIRED')],
            },
            'sdkRestorePurchases' => {
              'restoredCount': 1,
              'alreadyProcessedCount': 1,
              'failedCount': 0,
            },
            'sdkSyncPendingConsumables' => {
              'discoveredCount': 1,
              'completedCount': 0,
              'pendingDeliveries': [
                {
                  'deliveryId': deliveryId,
                  'productIdentifier': 'coins',
                  'source': 'MYKET',
                },
              ],
            },
            'sdkConfirmDelivery' => purchase('CONSUME_REQUIRED'),
            _ => throw StateError('Unexpected method: ${call.method}'),
          };
          expect(envelope['protocolVersion'], 1);
          if (call.method == 'sdkPurchase') {
            expect(envelope['requestId'], payload['idempotencyKey']);
          }
          return {
            'protocolVersion': 1,
            'requestId': envelope['requestId'],
            'ok': !rejected,
            'snapshot': snapshot(),
            if (!rejected) 'data': data,
            if (rejected)
              'error': {
                'code': 'unsupportedOperation',
                'message': 'Myket native subscriptions are unsupported.',
                'retryable': false,
                'details': {
                  'operation': 'purchase',
                  'outcomeMayHaveCommitted': false,
                },
              },
          };
        });
  });
  tearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null),
  );

  for (final mode in InappifyMobileProtocol.values) {
    group(mode.name, () {
      setUp(() => protocol = mode);
      test(
        'Myket configure and cached restore use existing native commands',
        () async {
          final request = InappifyConfigureRequest(
            apiKey: 'synthetic-api-key',
            market: Market.myket,
            marketKey: 'synthetic-myket-rsa',
            mobileProtocol: mode,
          );
          final configured = await platform.configure(request);
          expect(configured.isSuccess, isTrue);
          expect(configured.snapshot!.market, 'myket');
          expect(configured.snapshot!.storePlatform, 11);
          expect(configured.snapshot!.sdkVersion, '0.1.1');
          final payload = (calls.single.arguments as Map)['payload'] as Map;
          expect(payload, {
            'apiKey': request.apiKey,
            'appUserIdentifier': null,
          });
          expect(
            (await platform.restoreCachedSession(request)).failure?.code,
            InappifyFailureCode.unsupportedOperation,
          );
          expect(calls.map((c) => c.method), ['sdkConfigure']);
        },
      );

      test(
        'Myket products retain their type, attempt and delivery state',
        () async {
          for (final type in [
            InappifyProductType.consumable,
            InappifyProductType.nonConsumable,
          ]) {
            final result = await platform.purchase(
              InappifyPurchaseRequest(
                productIdentifier: 'coins',
                offeringIdentifier: 'main',
                market: Market.myket,
                productType: type,
                idempotencyKey: 'same-attempt',
              ),
            );
            final payload = (calls.last.arguments as Map)['payload'] as Map;
            expect(payload.containsKey('market'), isFalse);
            expect(
              ((payload['packageToPurchase'] as Map)['product']
                  as Map)['productType'],
              type.wireName,
            );
            expect(payload['idempotencyKey'], 'same-attempt');
            expect(result.data!.mobile!.market, 'myket');
            expect(result.data!.mobile!.requiresDelivery, isTrue);
            expect(result.data!.mobile!.deliveryId, deliveryId);
            expect(result.data!.purchaseStatus, isNull);
          }
          expect(calls.every((c) => c.method == 'sdkPurchase'), isTrue);
        },
      );

      test(
        'Myket recovery and manual confirmation preserve source and exact ID',
        () async {
          expect(
            (await platform.syncStorePurchases()).data!.single.mobile!.market,
            'myket',
          );
          expect((await platform.restoreStorePurchases()).data!.totalCount, 2);
          final pending = (await platform.syncPendingConsumables()).data!;
          expect(
            pending.pendingDeliveries.single.source,
            InappifyDeliverySource.myket,
          );
          expect(pending.pendingDeliveries.single.deliveryId, deliveryId);
          expect(calls.any((c) => c.method == 'sdkConfirmDelivery'), isFalse);
          final confirmed = await platform.confirmDelivery(deliveryId);
          expect((calls.last.arguments as Map)['payload'], {
            'deliveryId': deliveryId,
          });
          expect(confirmed.data!.mobile!.market, 'myket');
          expect(
            confirmed.data!.mobile!.storePurchaseStatus,
            InappifyStorePurchaseStatus.consumeRequired,
          );
        },
      );
    });
  }

  test(
    'Myket native rejection is returned without retries or fallback',
    () async {
      rejectPurchase = true;
      final result = await platform.purchase(
        const InappifyPurchaseRequest(
          productIdentifier: 'subscription',
          offeringIdentifier: 'main',
          market: Market.myket,
          productType: InappifyProductType.subscription,
          idempotencyKey: 'same-attempt',
        ),
      );
      expect(result.failure!.code, InappifyFailureCode.unsupportedOperation);
      expect(result.failure!.details['outcomeMayHaveCommitted'], isFalse);
      expect(calls.single.method, 'sdkPurchase');
    },
  );

  test(
    'Myket needs the Android native owner and cannot fall back to Dart billing',
    () async {
      final result = await NativeRequiredPlatform().configure(
        const InappifyConfigureRequest(
          apiKey: 'synthetic-api-key',
          market: Market.myket,
          marketKey: 'synthetic-myket-rsa',
        ),
      );
      expect(result.failure!.code, InappifyFailureCode.bridgeUnavailable);
      expect(calls, isEmpty);
    },
  );
}
