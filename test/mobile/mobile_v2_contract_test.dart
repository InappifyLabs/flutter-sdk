import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inappify_sdk/inappify_sdk_method_channel.dart';
import 'package:inappify_sdk/inappify_sdk_platform_interface.dart';
import 'package:inappify_sdk/models/purchase_result.dart';
import 'package:inappify_sdk/src/application/inappify_coordinator.dart';
import 'package:inappify_sdk/src/platform/mobile/native_required_platform.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('missing Android owner fails closed without a Dart configure', () async {
    final guard = NativeRequiredPlatform();
    final result = await guard.configure(
      const InappifyConfigureRequest(apiKey: 'fixture'),
    );
    expect(result.failure!.code, InappifyFailureCode.bridgeUnavailable);
    expect(result.failure!.details['nativeRequired'], isTrue);
    expect(result.snapshot!.customerInfo, isNull);
    expect((await guard.getCapabilities()).ownsSession, isFalse);
  });

  test('raw native diagnostics cannot enter the filtered public stream', () {
    expect(
      () => InappifyHttpTrace.fromMap({'containsSensitiveData': true}),
      throwsFormatException,
    );
  });

  test('configuration defaults to V2 and preserves purchase wire values', () {
    expect(const InappifyConfigureRequest(apiKey: 'fixture').toMap(), {
      'apiKey': 'fixture',
      'appUserIdentifier': null,
      'market': null,
      'marketKey': null,
      'country': null,
      'appVersion': null,
      'mobileProtocol': 'goV2',
      'enableSubscriptionRecoveryWithoutPayload': true,
    });
    final request = const InappifyPurchaseRequest(
      productIdentifier: 'item',
      offeringIdentifier: 'default',
      idempotencyKey: 'attempt',
    ).toMap();
    expect(request.keys, isNot(contains('productType')));
    expect(request.keys, isNot(contains('paywallId')));
    expect(request.keys, isNot(contains('dynamicPriceToken')));
    expect(PurchaseResult().toJson(), {
      'url': null,
      'purchaseStatus': null,
      'checkoutId': null,
      'checkoutStatus': null,
      'nextActionType': null,
    });
  });

  test('mobile purchase retains delivery instead of fabricating DONE', () {
    final result = PurchaseResult.fromJson({
      'mobile': {
        'storePurchaseStatus': 'DELIVERY_REQUIRED',
        'deliveryId': 7,
        'verificationRequestId': '9',
        'alreadyProcessed': false,
      },
    });
    expect(result.purchaseStatus, isNull);
    expect(result.mobile!.requiresDelivery, isTrue);
    expect(PurchaseResult.fromJson(result.toJson()).mobile!.deliveryId, 7);
  });

  test('new financial identifiers and states reject ambiguous decoding', () {
    for (final value in [0, -1, 1.5, '1']) {
      expect(
        () => InappifyMobilePurchaseData.fromMap({'deliveryId': value}),
        throwsFormatException,
      );
    }
    expect(
      () => InappifyMobilePurchaseData.fromMap({'storePurchaseStatus': 'DONE'}),
      throwsFormatException,
    );
    expect(
      () => InappifyConsumableSyncResult.fromMap({
        'discoveredCount': 0,
        'completedCount': 1,
        'pendingDeliveries': [],
      }),
      throwsFormatException,
    );
  });

  test('optional snapshot fields round trip without changing old shape', () {
    const old = InappifySdkSnapshot();
    expect(old.toMap().keys, isNot(contains('mobileProtocol')));
    expect(old.toMap().keys, isNot(contains('isConfigured')));
    const mobile = InappifySdkSnapshot(
      revision: 3,
      isConfigured: true,
      isAuthenticated: false,
      appUserIdentifier: 'fixture-customer',
      mobileProtocol: InappifyMobileProtocol.goV2,
      storePlatform: 1,
      isLogoutPending: false,
    );
    final decoded = InappifySdkSnapshot.fromMap(mobile.toMap().cast());
    expect(decoded.toMap(), mobile.toMap());
    expect(
      () => InappifySdkSnapshot.fromMap({...old.toMap(), 'revision': 1.5}),
      throwsFormatException,
    );
  });

  group('additive mobile channel', () {
    const channel = MethodChannel('fixture-mobile-channel');
    late MethodChannelInappifySdk platform;
    final calls = <MethodCall>[];
    setUp(() {
      calls.clear();
      platform = MethodChannelInappifySdk(methodChannel: channel);
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls.add(call);
            final args = call.arguments as Map;
            final data = switch (call.method) {
              'sdkSyncPurchases' => {
                'purchases': [
                  {
                    'mobile': {
                      'storePurchaseStatus': 'DELIVERY_REQUIRED',
                      'deliveryId': 8,
                    },
                  },
                ],
              },
              'sdkRestorePurchases' => {
                'restoredCount': 1,
                'alreadyProcessedCount': 2,
                'failedCount': 0,
              },
              'sdkSyncPendingConsumables' => {
                'discoveredCount': 1,
                'completedCount': 0,
                'pendingDeliveries': [
                  {
                    'deliveryId': 8,
                    'productIdentifier': 'coins',
                    'source': 'BAZAAR',
                  },
                ],
              },
              'sdkConfirmDelivery' => {
                'mobile': {
                  'storePurchaseStatus': 'CONSUME_REQUIRED',
                  'deliveryId': 8,
                },
              },
              'sdkV2CustomerInfo' => <String, Object?>{},
              'sdkV2Offerings' => {'offerings': []},
              'sdkIsPaymentUrlAllowed' => {'value': true},
              _ => <String, Object?>{},
            };
            return {
              'protocolVersion': 1,
              'requestId': args['requestId'],
              'ok': true,
              'data': data,
              'snapshot': const InappifySdkSnapshot().toMap(),
            };
          });
    });
    tearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null),
    );

    test(
      'post-dispatch malformed purchase retains uncertain outcome',
      () async {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(
              channel,
              (call) async => {
                'protocolVersion': 1,
                'requestId': (call.arguments as Map)['requestId'],
                'ok': true,
                'snapshot': const InappifySdkSnapshot().toMap(),
                'data': {
                  'mobile': {'deliveryId': 2.5},
                },
              },
            );
        final result = await platform.purchase(
          const InappifyPurchaseRequest(
            productIdentifier: 'item',
            offeringIdentifier: 'default',
            idempotencyKey: 'same-attempt',
          ),
        );
        expect(result.failure!.code, InappifyFailureCode.malformedResponse);
        expect(result.failure!.details['outcomeMayHaveCommitted'], isTrue);
        expect(result.failure!.details['operation'], 'purchase');
      },
    );

    test(
      'manual pending and confirm never conflate store completion with grant',
      () async {
        expect(
          (await platform.syncPurchases()).data!.single.mobile!.deliveryId,
          8,
        );
        expect((await platform.restorePurchases()).data!.totalCount, 3);
        final pending = (await platform.syncPendingConsumables()).data!;
        expect(
          pending.pendingDeliveries.single.source,
          InappifyDeliverySource.bazaar,
        );
        expect(
          calls.map((value) => value.method),
          isNot(contains('sdkConfirmDelivery')),
        );
        final confirmed = await platform.confirmDelivery(8);
        expect(
          confirmed.data!.mobile!.storePurchaseStatus,
          InappifyStorePurchaseStatus.consumeRequired,
        );
        expect((calls.last.arguments as Map)['payload'], {'deliveryId': 8});
      },
    );

    test(
      'Go wire commands keep channel protocol one and optional payloads',
      () async {
        await platform.configure(
          const InappifyConfigureRequest(
            apiKey: 'fixture',
            mobileProtocol: InappifyMobileProtocol.goV2,
          ),
        );
        expect(
          (calls.last.arguments as Map)['payload']['mobileProtocol'],
          'goV2',
        );
        for (final policy in InappifyFetchPolicy.values) {
          expect(
            (await platform.customerInfoWithPolicy(policy)).isSuccess,
            isTrue,
          );
          expect((calls.last.arguments as Map)['payload'], {
            'policy': policy.name,
          });
          expect(
            (await platform.offeringsWithPolicy(policy)).isSuccess,
            isTrue,
          );
        }
        await platform.queueAttributes({'tier': 'gold', 'removed': null});
        expect((calls.last.arguments as Map)['payload'], {
          'values': {'tier': 'gold', 'removed': null},
        });
        await platform.flushAttributes();
        await platform.recover();
        await platform.setNetworkEnabled(false);
        expect((calls.last.arguments as Map)['payload'], {'enabled': false});
        expect(
          (await platform.isPaymentUrlAllowed(
            'https://pay.inappify.com/',
          )).data,
          isTrue,
        );
        expect(
          calls.every(
            (call) => (call.arguments as Map)['protocolVersion'] == 1,
          ),
          isTrue,
        );
      },
    );
  });

  group('safe backend ownership', () {
    late InappifySdkPlatform original;
    final coordinators = <InappifyCoordinator>[];
    setUp(() {
      original = InappifySdkPlatform.instance;
    });
    tearDown(() async {
      InappifySdkPlatform.instance = original;
      for (final coordinator in coordinators) {
        await coordinator.resetForTesting();
      }
      coordinators.clear();
    });
    InappifyCoordinator coordinator(_Backend legacy, [_Backend? go]) {
      final value = InappifyCoordinator(
        fallbackPlatform: legacy,
        goPlatformFactory: go == null ? null : () => go,
      );
      coordinators.add(value);
      return value;
    }

    test('default and explicit V2 reuse the same owner', () async {
      InappifySdkPlatform.instance = _Unavailable();
      final legacy = _Backend(), go = _Backend(go: true);
      final sdk = coordinator(legacy, go);
      expect(
        (await sdk.configure(
          const InappifyConfigureRequest(apiKey: 'fixture'),
        )).isSuccess,
        isTrue,
      );
      expect(
        (await sdk.configure(
          const InappifyConfigureRequest(
            apiKey: 'fixture',
            mobileProtocol: InappifyMobileProtocol.goV2,
          ),
        )).isSuccess,
        isTrue,
      );
      expect(legacy.configures, 0);
      expect(go.configures, 2);
    });

    test(
      'explicit Go selects the iOS factory once and never uses legacy owner',
      () async {
        InappifySdkPlatform.instance = _Unavailable();
        final legacy = _Backend(), go = _Backend(go: true);
        final sdk = coordinator(legacy, go);
        const request = InappifyConfigureRequest(
          apiKey: 'fixture',
          mobileProtocol: InappifyMobileProtocol.goV2,
        );
        final first = sdk.configure(request);
        expect(identical(first, sdk.configure(request)), isTrue);
        expect((await first).isSuccess, isTrue);
        expect(go.configures, 1);
        expect(legacy.configures, 0);
        expect(
          (await sdk.configure(
            const InappifyConfigureRequest(apiKey: 'fixture'),
          )).isSuccess,
          isTrue,
        );
      },
    );

    test(
      'old native adapter cannot silently treat Go configure as V1',
      () async {
        final native = _Backend(kind: InappifyBackendKind.methodChannel);
        InappifySdkPlatform.instance = native;
        final sdk = coordinator(_Backend(), _Backend(go: true));
        final result = await sdk.configure(
          const InappifyConfigureRequest(
            apiKey: 'fixture',
            mobileProtocol: InappifyMobileProtocol.goV2,
          ),
        );
        expect(result.failure!.code, InappifyFailureCode.unsupportedOperation);
        expect(native.configures, 0);
      },
    );

    test('a preconfigure read does not accidentally lock Go out', () async {
      InappifySdkPlatform.instance = _Unavailable();
      final legacy = _Backend(), go = _Backend(go: true);
      final sdk = coordinator(legacy, go);
      await sdk.getCustomerInfo();
      final result = await sdk.configure(
        const InappifyConfigureRequest(
          apiKey: 'fixture',
          mobileProtocol: InappifyMobileProtocol.goV2,
        ),
      );
      expect(result.isSuccess, isTrue);
      expect(go.configures, 1);
      expect(legacy.configures, 0);
    });

    test(
      'delayed lower revision cannot resurrect the prior mobile customer',
      () async {
        final native = _EventBackend();
        InappifySdkPlatform.instance = native;
        final sdk = coordinator(_Backend());
        final received = <InappifyPlatformEvent>[];
        final listener = sdk.events.listen(received.add);
        await sdk.configure(const InappifyConfigureRequest(apiKey: 'fixture'));
        native.controller.add(
          const InappifyPlatformEvent(
            type: InappifyPlatformEventType.authenticationChanged,
            snapshot: InappifySdkSnapshot(
              revision: 1,
              appUserIdentifier: 'previous',
            ),
          ),
        );
        await Future<void>.delayed(Duration.zero);
        expect(sdk.state.appUserIdentifier, 'current');
        expect(received, isEmpty);
        native.controller.add(
          const InappifyPlatformEvent(
            type: InappifyPlatformEventType.stateChanged,
            snapshot: InappifySdkSnapshot(
              revision: 3,
              appUserIdentifier: 'newer',
            ),
          ),
        );
        await Future<void>.delayed(Duration.zero);
        expect(sdk.state.appUserIdentifier, 'newer');
        expect(received, hasLength(1));
        await listener.cancel();
        await native.controller.close();
      },
    );

    test(
      'Web configuration ignores mobile selection and rejects mobile APIs',
      () async {
        final web = _Backend(kind: InappifyBackendKind.webJavaScript);
        InappifySdkPlatform.instance = web;
        final sdk = coordinator(_Backend());
        expect(
          (await sdk.configure(
            const InappifyConfigureRequest(apiKey: 'fixture'),
          )).isSuccess,
          isTrue,
        );
        expect(
          (await sdk.syncPendingConsumables()).failure!.code,
          InappifyFailureCode.unsupportedOperation,
        );
        expect(
          (await sdk.configure(
            const InappifyConfigureRequest(
              apiKey: 'fixture',
              mobileProtocol: InappifyMobileProtocol.goV2,
            ),
          )).isSuccess,
          isTrue,
        );
        expect(web.configures, 2);
        expect(web.syncs, 0);
      },
    );
  });
}

class _Unavailable extends InappifySdkPlatform {}

class _EventBackend extends _Backend {
  _EventBackend() : super(kind: InappifyBackendKind.methodChannel, go: true);
  final controller = StreamController<InappifyPlatformEvent>.broadcast(
    sync: true,
  );
  @override
  Stream<InappifyPlatformEvent> get events => controller.stream;
  @override
  Future<InappifySdkResult<void>> configure(
    InappifyConfigureRequest request,
  ) async => InappifySdkResult.success(
    snapshot: const InappifySdkSnapshot(
      revision: 2,
      appUserIdentifier: 'current',
    ),
  );
}

class _Backend extends InappifySdkPlatform {
  _Backend({this.go = false, this.kind = InappifyBackendKind.dart});
  final bool go;
  final InappifyBackendKind kind;
  int configures = 0, syncs = 0;
  @override
  Future<InappifyBackendCapabilities> getCapabilities() async =>
      InappifyBackendCapabilities(
        backendKind: kind,
        protocolVersion: 1,
        ownsSession: true,
        supportedOperations: InappifyOperation.values.toSet()
          ..removeWhere((value) => value == InappifyOperation.goV2 && !go),
      );
  @override
  Future<InappifySdkResult<void>> configure(
    InappifyConfigureRequest request,
  ) async {
    configures++;
    await Future<void>.delayed(Duration.zero);
    return InappifySdkResult.success(snapshot: const InappifySdkSnapshot());
  }

  @override
  Future<InappifySdkResult<InappifyConsumableSyncResult>>
  syncPendingConsumables() async {
    syncs++;
    return InappifySdkResult.success(snapshot: const InappifySdkSnapshot());
  }
}
