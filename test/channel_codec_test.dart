import 'package:flutter_test/flutter_test.dart';
import 'package:inappify_sdk/src/platform/channel/channel_codec.dart';
import 'package:inappify_sdk/src/platform/channel/channel_contract.dart';
import 'package:inappify_sdk/src/platform/contracts/platform_event.dart';
import 'package:inappify_sdk/src/platform/contracts/sdk_failure.dart';
import 'package:inappify_sdk/session_state.dart';

void main() {
  group('InappifyChannelContract', () {
    test('creates a protocol-v1 request envelope', () {
      expect(
        InappifyChannelContract.requestEnvelope(
          requestId: 'request-1',
          payload: const <String, Object?>{'productIdentifier': 'premium'},
        ),
        <String, Object?>{
          'protocolVersion': 1,
          'requestId': 'request-1',
          'payload': const <String, Object?>{'productIdentifier': 'premium'},
        },
      );
    });
  });

  group('InappifyChannelCodec.normalize', () {
    test('recursively converts platform maps to string-keyed maps', () {
      final normalized =
          InappifyChannelCodec.normalize(<Object?, Object?>{
                'items': <Object?>[
                  <Object?, Object?>{7: 'seven'},
                ],
              })
              as Map<String, Object?>;

      final items = normalized['items'] as List<Object?>;
      expect(items.single, <String, Object?>{'7': 'seven'});
    });
  });

  group('InappifyChannelCodec.decodeResponse', () {
    test('decodes a successful response and complete snapshot', () {
      final response = InappifyChannelCodec.decodeResponse(<Object?, Object?>{
        'protocolVersion': 1,
        'requestId': 'request-1',
        'ok': true,
        'data': <Object?, Object?>{'configured': true},
        'snapshot': _completeSnapshot(
          accessToken: 'token',
          apiKey: 'api-key',
          versionName: '2.4.0',
          versionCode: 20400,
          sessionState: 'authenticated',
          persistenceMode: 'durable',
        ),
        'futureOptionalField': 'ignored',
      }, expectedRequestId: 'request-1');

      expect(response.isSuccess, isTrue);
      expect(response.requestId, 'request-1');
      expect(response.data, <String, Object?>{'configured': true});
      expect(response.snapshot?.accessToken, 'token');
      expect(response.snapshot?.versionName, '2.4.0');
      expect(response.snapshot?.versionCode, 20400);
      expect(
        response.snapshot?.sessionState,
        InappifySessionState.authenticated,
      );
      expect(
        response.snapshot?.persistenceMode,
        InappifySessionPersistenceMode.durable,
      );
      expect(response.failure, isNull);
    });

    test('decodes a structured failure and retry metadata', () {
      final response = InappifyChannelCodec.decodeResponse(<String, Object?>{
        'protocolVersion': 1,
        'requestId': 'request-2',
        'ok': false,
        'error': <Object?, Object?>{
          'code': 'network',
          'message': 'Connection failed.',
          'retryable': true,
          'details': <Object?, Object?>{'statusCode': 503},
        },
      }, expectedRequestId: 'request-2');

      expect(response.isSuccess, isFalse);
      expect(response.failure?.code, InappifyFailureCode.network);
      expect(response.failure?.message, 'Connection failed.');
      expect(response.failure?.isRetryable, isTrue);
      expect(response.failure?.details, <String, Object?>{'statusCode': 503});
    });

    test('maps an unknown wire failure code to unknown', () {
      final response = InappifyChannelCodec.decodeResponse(<String, Object?>{
        'protocolVersion': 1,
        'requestId': 'request-3',
        'ok': false,
        'error': <String, Object?>{
          'code': 'introducedByANewerSdk',
          'message': 'A newer failure.',
          'retryable': false,
        },
      }, expectedRequestId: 'request-3');

      expect(response.failure?.code, InappifyFailureCode.unknown);
    });

    test('decodes session recovery failure codes additively', () {
      final response = InappifyChannelCodec.decodeResponse(<String, Object?>{
        'protocolVersion': 1,
        'requestId': 'request-recovery',
        'ok': false,
        'error': <String, Object?>{
          'code': 'sessionRecoveryRequired',
          'message': 'Recovery required.',
          'retryable': false,
        },
      }, expectedRequestId: 'request-recovery');

      expect(
        response.failure?.code,
        InappifyFailureCode.sessionRecoveryRequired,
      );
    });

    test('rejects a non-map response', () {
      expect(
        () => InappifyChannelCodec.decodeResponse(
          'invalid',
          expectedRequestId: 'request-1',
        ),
        throwsA(isA<FormatException>()),
      );
    });

    test('rejects an unsupported protocol version', () {
      expect(
        () => InappifyChannelCodec.decodeResponse(<String, Object?>{
          'protocolVersion': 2,
          'requestId': 'request-1',
          'ok': true,
        }, expectedRequestId: 'request-1'),
        throwsA(isA<FormatException>()),
      );
    });

    test('does not truncate a fractional protocol version', () {
      expect(
        () => InappifyChannelCodec.decodeResponse(<String, Object?>{
          'protocolVersion': 1.9,
          'requestId': 'request-1',
          'ok': true,
        }, expectedRequestId: 'request-1'),
        throwsA(isA<FormatException>()),
      );
    });

    test('rejects a response for a different request', () {
      expect(
        () => InappifyChannelCodec.decodeResponse(<String, Object?>{
          'protocolVersion': 1,
          'requestId': 'another-request',
          'ok': true,
        }, expectedRequestId: 'request-1'),
        throwsA(isA<FormatException>()),
      );
    });

    test('requires a boolean success marker', () {
      expect(
        () => InappifyChannelCodec.decodeResponse(<String, Object?>{
          'protocolVersion': 1,
          'requestId': 'request-1',
          'ok': 'true',
        }, expectedRequestId: 'request-1'),
        throwsA(isA<FormatException>()),
      );
    });

    test('requires an error map for failed responses', () {
      expect(
        () => InappifyChannelCodec.decodeResponse(<String, Object?>{
          'protocolVersion': 1,
          'requestId': 'request-1',
          'ok': false,
        }, expectedRequestId: 'request-1'),
        throwsA(isA<FormatException>()),
      );
    });

    test('rejects a partial snapshot', () {
      expect(
        () => InappifyChannelCodec.decodeResponse(<String, Object?>{
          'protocolVersion': 1,
          'requestId': 'request-1',
          'ok': true,
          'snapshot': <String, Object?>{'accessToken': 'token'},
        }, expectedRequestId: 'request-1'),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('InappifyChannelCodec.decodeEvent', () {
    test('decodes a correlated state-change event', () {
      final event = InappifyChannelCodec.decodeEvent(<String, Object?>{
        'protocolVersion': 1,
        'type': 'purchaseUpdated',
        'requestId': 'purchase-1',
        'snapshot': _completeSnapshot(accessToken: 'token'),
        'data': <String, Object?>{'status': 'pending'},
      });

      expect(event.type, InappifyPlatformEventType.purchaseUpdated);
      expect(event.requestId, 'purchase-1');
      expect(event.snapshot?.accessToken, 'token');
      expect(event.data, <String, Object?>{'status': 'pending'});
    });

    test('decodes a session-state event', () {
      final event = InappifyChannelCodec.decodeEvent(<String, Object?>{
        'protocolVersion': 1,
        'type': 'sessionStateChanged',
        'data': <String, Object?>{
          'state': 'recovery-required',
          'retryable': false,
        },
      });

      expect(event.type, InappifyPlatformEventType.sessionStateChanged);
    });

    test('rejects an unknown event type', () {
      expect(
        () => InappifyChannelCodec.decodeEvent(<String, Object?>{
          'protocolVersion': 1,
          'type': 'unknownFutureEvent',
        }),
        throwsA(isA<FormatException>()),
      );
    });
  });
}

Map<String, Object?> _completeSnapshot({
  String? accessToken = '',
  String? apiKey = '',
  String versionName = '',
  int? versionCode,
  String? sessionState,
  String? persistenceMode,
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
    if (sessionState != null) 'sessionState': sessionState,
    if (persistenceMode != null) 'persistenceMode': persistenceMode,
    'failedToLoadOfferings': false,
    'failedToLoadCustomerInfo': false,
  };
}
