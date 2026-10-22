import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inappify_sdk/inappify_sdk_method_channel.dart';
import 'package:inappify_sdk/inappify_sdk_platform_interface.dart';
import 'package:inappify_sdk/models/purchase_attempt.dart';
import 'package:inappify_sdk/src/application/inappify_coordinator.dart';
import 'package:inappify_sdk/src/platform/channel/channel_codec.dart';
import 'package:inappify_sdk/src/platform/channel/channel_contract.dart';

InappifySdkSnapshot scopedSnapshot(
  int revision, {
  String customer = 'customer',
}) => InappifySdkSnapshot(
  revision: revision,
  isConfigured: true,
  isAuthenticated: true,
  appId: 12,
  appUserIdentifier: customer,
  market: 'bazar',
  storePlatform: 10,
  mobileProtocol: InappifyMobileProtocol.goV2,
);

class _EventPlatform extends InappifySdkPlatform {
  final changes = StreamController<InappifyPlatformEvent>.broadcast(sync: true);
  @override
  Stream<InappifyPlatformEvent> get events => changes.stream;
  @override
  Future<InappifyBackendCapabilities> getCapabilities() async =>
      InappifyBackendCapabilities(
        backendKind: InappifyBackendKind.dart,
        protocolVersion: 1,
        ownsSession: true,
        supportedOperations: InappifyOperation.values.toSet(),
      );
  @override
  Future<InappifySdkResult<void>> configure(
    InappifyConfigureRequest request,
  ) async => InappifySdkResult.success(snapshot: scopedSnapshot(10));
}

Map<String, Object?> attempt({
  String id = 'attempt-1',
  String status = 'SUCCEEDED',
}) => {
  'attemptId': id,
  'productIdentifier': 'premium',
  'offeringIdentifier': 'main',
  'market': 'bazar',
  'status': status,
  'updatedAtEpochMillis': 123,
  'purchase': status == 'SUCCEEDED'
      ? {
          'purchaseStatus': 'DONE',
          'mobile': {
            'storePurchaseStatus': 'COMPLETED',
            'idempotencyKey': id,
            'productIdentifier': 'premium',
            'offeringIdentifier': 'main',
            'market': 'bazar',
          },
        }
      : null,
  'error': status == 'FAILED'
      ? {
          'code': 'purchaseCancelled',
          'message': 'Cancelled',
          'retryable': false,
          'details': <String, Object?>{},
        }
      : null,
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel(InappifyChannelContract.channelName);
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test(
    'decodes typed success, pending and definitive failure without treating pending as failed',
    () {
      final success = InappifyPurchaseAttempt.fromMap(attempt());
      expect(success.isFinal, isTrue);
      expect(success.purchase!.mobile!.idempotencyKey, 'attempt-1');
      expect(
        InappifyPurchaseAttempt.fromMap(attempt(status: 'PENDING')).isFinal,
        isFalse,
      );
      final failure = InappifyPurchaseAttempt.fromMap(
        attempt(status: 'FAILED'),
      );
      expect(failure.failure!.code, InappifyFailureCode.purchaseCancelled);
    },
  );

  test(
    'new purchase events carry a correlated result while old empty events remain valid',
    () {
      final current = InappifyChannelCodec.decodeEvent({
        'protocolVersion': 1,
        'type': 'purchaseUpdated',
        'requestId': 'attempt-1',
        'data': {'purchaseAttempt': attempt()},
      });
      expect(current.purchaseAttempt!.attemptId, 'attempt-1');
      expect(
        current.purchaseAttempt!.purchase!.mobile!.storePurchaseStatus!.name,
        'completed',
      );
      final legacy = InappifyChannelCodec.decodeEvent({
        'protocolVersion': 1,
        'type': 'purchaseUpdated',
        'requestId': 'attempt-1',
        'data': <String, Object?>{},
      });
      expect(legacy.purchaseAttempt, isNull);
    },
  );

  test(
    'rejects unrelated event or purchase identities instead of clearing another attempt',
    () {
      expect(
        () => InappifyChannelCodec.decodeEvent({
          'protocolVersion': 1,
          'type': 'purchaseUpdated',
          'requestId': 'different',
          'data': {'purchaseAttempt': attempt()},
        }),
        throwsFormatException,
      );
      final mismatched = attempt();
      mismatched['purchase'] = {
        'purchaseStatus': 'DONE',
        'mobile': {'idempotencyKey': 'different'},
      };
      expect(
        () => InappifyPurchaseAttempt.fromMap(mismatched),
        throwsFormatException,
      );
      final wrongOffering = attempt()..['offeringIdentifier'] = 'unrelated';
      expect(
        () => InappifyPurchaseAttempt.fromMap(wrongOffering),
        throwsFormatException,
      );
      final noResult = attempt()..['purchase'] = null;
      expect(
        () => InappifyPurchaseAttempt.fromMap(noResult),
        throwsFormatException,
      );
    },
  );

  test(
    'reads native history by exact attempt without issuing a purchase or sync command',
    () async {
      final calls = <MethodCall>[];
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        final request = Map<String, dynamic>.from(call.arguments as Map);
        return {
          'protocolVersion': 1,
          'requestId': request['requestId'],
          'ok': true,
          'snapshot': const InappifySdkSnapshot().toMap(),
          'data': call.method == InappifyChannelContract.getPurchaseAttempt
              ? attempt()
              : {
                  'attempts': [attempt()],
                },
        };
      });
      final platform = MethodChannelInappifySdk(methodChannel: channel);
      final result = await platform.getPurchaseAttempt('attempt-1');
      expect(result.isSuccess, isTrue);
      expect(result.data!.status, InappifyPurchaseAttemptStatus.succeeded);
      final payload = (calls.first.arguments as Map)['payload'] as Map;
      expect(payload, {'attemptId': 'attempt-1'});
      final list = await platform.getPurchaseAttempts();
      expect(list.data!.single.attemptId, 'attempt-1');
      expect(calls.map((call) => call.method), [
        'sdkGetPurchaseAttempt',
        'sdkGetPurchaseAttempts',
      ]);
    },
  );

  test(
    'late correlated outcomes survive newer cache revisions but never cross customer scope',
    () async {
      final original = InappifySdkPlatform.instance;
      final platform = _EventPlatform();
      InappifySdkPlatform.instance = platform;
      final coordinator = InappifyCoordinator(fallbackPlatform: original);
      final events = <InappifyPlatformEvent>[];
      final subscription = coordinator.events.listen(events.add);
      try {
        await coordinator.configure(
          const InappifyConfigureRequest(
            apiKey: 'fixture-key',
            appUserIdentifier: 'customer',
          ),
        );
        final result = InappifyPurchaseAttempt.fromMap(attempt());
        platform.changes.add(
          InappifyPlatformEvent(
            type: InappifyPlatformEventType.purchaseUpdated,
            requestId: result.attemptId,
            snapshot: scopedSnapshot(9),
            purchaseAttempt: result,
          ),
        );
        await Future<void>.delayed(Duration.zero);
        expect(
          events.where((event) => event.purchaseAttempt != null).length,
          1,
        );
        expect(coordinator.state.revision, 10);
        platform.changes.add(
          InappifyPlatformEvent(
            type: InappifyPlatformEventType.purchaseUpdated,
            requestId: result.attemptId,
            snapshot: scopedSnapshot(11, customer: 'different'),
            purchaseAttempt: result,
          ),
        );
        await Future<void>.delayed(Duration.zero);
        expect(
          events.where((event) => event.purchaseAttempt != null).length,
          1,
        );
        expect(coordinator.state.appUserIdentifier, 'customer');
        expect(coordinator.state.revision, 10);
      } finally {
        await subscription.cancel();
        await coordinator.resetForTesting();
        await platform.changes.close();
        InappifySdkPlatform.instance = original;
      }
    },
  );

  test(
    'Direct delivery uses the original attempt while pending until delivery acknowledgement',
    () {
      Map<String, dynamic> direct(bool delivered) => {
        'attemptId': 'direct-attempt',
        'productIdentifier': 'coins',
        'offeringIdentifier': 'main',
        'market': 'none',
        'status': delivered ? 'SUCCEEDED' : 'PENDING',
        'updatedAtEpochMillis': 123,
        'purchase': {
          'purchaseStatus': delivered ? 'DONE' : null,
          'mobile': {
            'idempotencyKey': 'direct-attempt',
            'productIdentifier': 'coins',
            'offeringIdentifier': 'main',
            'market': 'none',
            'deliveryId': 7,
            'storePurchaseStatus': delivered
                ? 'COMPLETED'
                : 'DELIVERY_REQUIRED',
          },
        },
      };
      final pending = InappifyPurchaseAttempt.fromMap(direct(false));
      expect(pending.isFinal, isFalse);
      expect(pending.purchase!.mobile!.deliveryId, 7);
      final completed = InappifyPurchaseAttempt.fromMap(direct(true));
      expect(completed.isFinal, isTrue);
      expect(completed.purchase!.mobile!.idempotencyKey, 'direct-attempt');
    },
  );

  test(
    'unknown history is successful null while older unsupported bridges remain failures',
    () async {
      var unsupported = false;
      messenger.setMockMethodCallHandler(channel, (call) async {
        final request = call.arguments as Map;
        return {
          'protocolVersion': 1,
          'requestId': request['requestId'],
          'ok': !unsupported,
          'snapshot': const InappifySdkSnapshot().toMap(),
          'data': null,
          if (unsupported)
            'error': {
              'code': 'unsupportedOperation',
              'message': 'Old bridge',
              'retryable': false,
              'details': <String, Object?>{},
            },
        };
      });
      final platform = MethodChannelInappifySdk(methodChannel: channel);
      final unknown = await platform.getPurchaseAttempt('unknown');
      expect(unknown.isSuccess, isTrue);
      expect(unknown.data, isNull);
      unsupported = true;
      final older = await platform.getPurchaseAttempt('unknown');
      expect(older.failure!.code, InappifyFailureCode.unsupportedOperation);
    },
  );
}
