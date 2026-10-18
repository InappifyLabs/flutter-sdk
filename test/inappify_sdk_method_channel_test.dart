import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inappify_sdk/inappify_sdk_method_channel.dart';
import 'package:inappify_sdk/models/attribute.dart';
import 'package:inappify_sdk/models/enums/market.dart';
import 'package:inappify_sdk/models/enums/purchase_status.dart';
import 'package:inappify_sdk/src/platform/channel/channel_contract.dart';
import 'package:inappify_sdk/src/platform/contracts/backend_capabilities.dart';
import 'package:inappify_sdk/src/platform/contracts/sdk_failure.dart';
import 'package:inappify_sdk/src/platform/contracts/sdk_requests.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel(InappifyChannelContract.channelName);
  late MethodChannelInappifySdk platform;

  setUp(() {
    platform = MethodChannelInappifySdk(
      methodChannel: channel,
      requestIdGenerator: () => 'request-1',
    );
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('uses the legacy platform-version method', () async {
    MethodCall? capturedCall;
    _setHandler(channel, (call) async {
      capturedCall = call;
      return 'Android 16';
    });

    expect(await platform.getPlatformVersion(), 'Android 16');
    expect(capturedCall?.method, 'getPlatformVersion');
    expect(capturedCall?.arguments, isNull);
  });

  test(
    'encodes cache-only restore with configure options and strict boolean',
    () async {
      MethodCall? received;
      var value = true;
      _setHandler(channel, (call) async {
        received = call;
        return _successEnvelope(call, data: <String, Object?>{'value': value});
      });
      const request = InappifyConfigureRequest(
        apiKey: 'fixture-key',
        appUserIdentifier: 'fixture-user',
        country: 'IR',
        appVersion: '2.1.0',
      );
      expect((await platform.restoreCachedSession(request)).data, true);
      expect(received?.method, InappifyChannelContract.restoreCachedSession);
      expect((received?.arguments as Map)['payload'], request.toMap());
      value = false;
      expect((await platform.restoreCachedSession(request)).data, false);
      _setHandler(
        channel,
        (call) async =>
            _successEnvelope(call, data: <String, Object?>{'value': 'true'}),
      );
      expect(
        (await platform.restoreCachedSession(request)).failure?.code,
        InappifyFailureCode.malformedResponse,
      );
    },
  );

  test(
    'passes default and explicit subscription recovery flags over the channel',
    () async {
      MethodCall? received;
      _setHandler(channel, (call) async {
        received = call;
        return _successEnvelope(call, data: <String, Object?>{'value': true});
      });
      const defaultRequest = InappifyConfigureRequest(apiKey: 'fixture-key');
      expect(defaultRequest.enableSubscriptionRecoveryWithoutPayload, isTrue);
      for (final request in [
        defaultRequest,
        const InappifyConfigureRequest(
          apiKey: 'fixture-key',
          enableSubscriptionRecoveryWithoutPayload: true,
        ),
        const InappifyConfigureRequest(
          apiKey: 'fixture-key',
          enableSubscriptionRecoveryWithoutPayload: false,
        ),
      ]) {
        expect((await platform.configure(request)).isSuccess, isTrue);
        expect(
          (received!.arguments
              as Map)['payload']['enableSubscriptionRecoveryWithoutPayload'],
          request.enableSubscriptionRecoveryWithoutPayload,
        );
        expect((await platform.restoreCachedSession(request)).data, isTrue);
        expect(
          (received!.arguments
              as Map)['payload']['enableSubscriptionRecoveryWithoutPayload'],
          request.enableSubscriptionRecoveryWithoutPayload,
        );
      }
    },
  );

  test('decodes host application version information', () async {
    _setHandler(channel, (call) async {
      expect(call.method, 'getVersionInfo');
      return <String, Object?>{'versionName': '3.4.0', 'versionCode': '2034'};
    });

    final version = await platform.getAppVersionInfo();

    expect(version?.versionName, '3.4.0');
    expect(version?.versionCode, 2034);
  });

  test(
    'sends a versioned handshake and decodes complete capabilities',
    () async {
      MethodCall? capturedCall;
      _setHandler(channel, (call) async {
        capturedCall = call;
        return _successEnvelope(
          call,
          includeSnapshot: false,
          data: <String, Object?>{
            'backendKind': 'methodChannel',
            'protocolVersion': 1,
            'ownsSession': true,
            'supportedOperations': const <String>[
              'configure',
              'login',
              'logout',
              'purchase',
              'validateDiscountCode',
              'getCustomerInfo',
              'getOfferings',
              'setAttributes',
              'setReservedAttribute',
              'syncAttributes',
              'setTargetingContext',
              'getCurrentOffering',
              'checkEntitlement',
              'deleteAttributes',
              'syncAttributeValues',
              'canSetReservedAttribute',
            ],
            'sdkVersion': '1.2.0',
          },
        );
      });

      final capabilities = await platform.getCapabilities();

      expect(capturedCall?.method, InappifyChannelContract.handshake);
      expect(capturedCall?.arguments, <String, Object?>{
        'protocolVersion': 1,
        'requestId': 'request-1',
        'payload': const <String, Object?>{
          'clientProtocolVersions': <int>[1],
        },
      });
      expect(capabilities.backendKind, InappifyBackendKind.methodChannel);
      expect(capabilities.sdkVersion, '1.2.0');
      expect(capabilities.supportsCompleteLifecycle, isTrue);
    },
  );

  test('treats a malformed handshake as an unavailable backend', () async {
    _setHandler(channel, (_) async => 'not-an-envelope');

    final capabilities = await platform.getCapabilities();

    expect(capabilities.backendKind, InappifyBackendKind.methodChannel);
    expect(capabilities.supportsCompleteLifecycle, isFalse);
  });

  test('rejects fractional capability protocol versions', () async {
    _setHandler(channel, (call) async {
      return _successEnvelope(
        call,
        includeSnapshot: false,
        data: <String, Object?>{
          'backendKind': 'methodChannel',
          'protocolVersion': 1.9,
          'ownsSession': true,
          'supportedOperations': InappifyOperation.values
              .map((operation) => operation.name)
              .toList(growable: false),
        },
      );
    });

    final capabilities = await platform.getCapabilities();

    expect(capabilities.supportsCompleteLifecycle, isFalse);
  });

  test('encodes configure input and mirrors the returned snapshot', () async {
    const request = InappifyConfigureRequest(
      apiKey: 'api-key',
      appUserIdentifier: 'customer-1',
      market: Market.myket,
      marketKey: 'market-key',
    );
    MethodCall? capturedCall;
    _setHandler(channel, (call) async {
      capturedCall = call;
      return _successEnvelope(
        call,
        snapshot: _completeSnapshot(
          accessToken: 'access-token',
          apiKey: 'api-key',
          versionName: '3.4.0',
          versionCode: 2034,
        ),
      );
    });

    final result = await platform.configure(request);

    expect(capturedCall?.method, InappifyChannelContract.configure);
    expect(
      capturedCall?.arguments,
      InappifyChannelContract.requestEnvelope(
        requestId: 'request-1',
        payload: request.toMap(),
      ),
    );
    expect(result.isSuccess, isTrue);
    expect(result.snapshot?.accessToken, 'access-token');
    expect(result.snapshot?.versionCode, 2034);
  });

  test('uses the purchase idempotency key as the request id', () async {
    const request = InappifyPurchaseRequest(
      productIdentifier: 'premium-monthly',
      offeringIdentifier: 'main',
      idempotencyKey: 'purchase-attempt-1',
      discount: 15,
      isCrypto: true,
      market: Market.none,
    );
    MethodCall? capturedCall;
    _setHandler(channel, (call) async {
      capturedCall = call;
      return _successEnvelope(
        call,
        data: const <String, Object?>{
          'url': 'https://pay.example.test/session',
          'purchaseStatus': 'NEEDTOPAY',
        },
      );
    });

    final result = await platform.purchase(request);

    expect(capturedCall?.method, InappifyChannelContract.purchase);
    expect(
      capturedCall?.arguments,
      InappifyChannelContract.requestEnvelope(
        requestId: 'purchase-attempt-1',
        payload: request.toMap(),
      ),
    );
    expect(result.isSuccess, isTrue);
    expect(result.data?.purchaseStatus, PurchaseStatus.NEEDTOPAY);
    expect(result.data?.url, 'https://pay.example.test/session');
  });

  test('decodes attribute lists returned by the platform', () async {
    _setHandler(channel, (call) async {
      expect(call.method, InappifyChannelContract.setAttributes);
      return _successEnvelope(
        call,
        data: const <String, Object?>{
          'attributes': <Object?>[
            <String, Object?>{'key': 'tier', 'value': 'gold'},
          ],
        },
      );
    });

    final result = await platform.setAttributes(
      InappifyAttributesRequest(
        attributes: <Attribute>[Attribute(key: 'tier', value: 'gold')],
      ),
    );

    expect(result.isSuccess, isTrue);
    expect(result.data, hasLength(1));
    expect(result.data?.single.key, 'tier');
    expect(result.data?.single.value, 'gold');
  });

  test(
    'preserves structured domain failures returned in an envelope',
    () async {
      _setHandler(channel, (call) async {
        expect(call.method, InappifyChannelContract.login);
        expect((call.arguments as Map)['payload'], {
          'appUserIdentifier': 'customer-1',
        });
        return _failureEnvelope(
          call,
          code: 'unauthorized',
          message: 'The customer session expired.',
          retryable: false,
        );
      });

      final result = await platform.login(
        const InappifyLoginRequest(appUserIdentifier: 'customer-1'),
      );

      expect(result.isSuccess, isFalse);
      expect(result.failure?.code, InappifyFailureCode.unauthorized);
      expect(result.failure?.message, 'The customer session expired.');
      expect(result.failure?.isRetryable, isFalse);
    },
  );

  test(
    'maps PlatformException codes to platform-independent failures',
    () async {
      _setHandler(channel, (_) async {
        throw PlatformException(
          code: 'inappify/unsupported-protocol',
          message: 'Protocol mismatch.',
        );
      });

      final result = await platform.logout();

      expect(result.isSuccess, isFalse);
      expect(result.failure?.code, InappifyFailureCode.protocolMismatch);
      expect(result.failure?.details, <String, Object?>{
        'platformCode': 'inappify/unsupported-protocol',
      });
    },
  );

  test('maps invalid response envelopes to malformedResponse', () async {
    _setHandler(channel, (_) async => <String, Object?>{'ok': true});

    final result = await platform.logout();

    expect(result.isSuccess, isFalse);
    expect(result.failure?.code, InappifyFailureCode.malformedResponse);
  });

  test('rejects a successful lifecycle response without a snapshot', () async {
    _setHandler(channel, (call) async {
      final arguments = (call.arguments as Map).cast<Object?, Object?>();
      return <String, Object?>{
        'protocolVersion': 1,
        'requestId': arguments['requestId'],
        'ok': true,
      };
    });

    final result = await platform.logout();

    expect(result.isSuccess, isFalse);
    expect(result.failure?.code, InappifyFailureCode.malformedResponse);
  });
}

void _setHandler(
  MethodChannel channel,
  Future<Object?> Function(MethodCall call) handler,
) {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, handler);
}

Map<String, Object?> _successEnvelope(
  MethodCall call, {
  Map<String, Object?>? data,
  Map<String, Object?>? snapshot,
  bool includeSnapshot = true,
}) {
  final arguments = (call.arguments as Map).cast<Object?, Object?>();
  return <String, Object?>{
    'protocolVersion': 1,
    'requestId': arguments['requestId'],
    'ok': true,
    if (data != null) 'data': data,
    if (includeSnapshot) 'snapshot': snapshot ?? _completeSnapshot(),
  };
}

Map<String, Object?> _completeSnapshot({
  String? accessToken = '',
  String? apiKey = '',
  String versionName = '',
  int? versionCode,
}) {
  return <String, Object?>{
    'accessToken': accessToken,
    'apiKey': apiKey,
    'customerInfo': null,
    'offerings': null,
    'storeInfo': null,
    'forceVersion': 1,
    'appId': null,
    'country': 'IR',
    'versionName': versionName,
    'versionCode': versionCode,
    'failedToLoadOfferings': false,
    'failedToLoadCustomerInfo': false,
  };
}

Map<String, Object?> _failureEnvelope(
  MethodCall call, {
  required String code,
  required String message,
  required bool retryable,
}) {
  final arguments = (call.arguments as Map).cast<Object?, Object?>();
  return <String, Object?>{
    'protocolVersion': 1,
    'requestId': arguments['requestId'],
    'ok': false,
    'error': <String, Object?>{
      'code': code,
      'message': message,
      'retryable': retryable,
    },
  };
}
