@TestOn('vm')
library;

import 'dart:async';
import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inappify_sdk/models/mobile_v2.dart';
import 'package:inappify_sdk/src/platform/mobile/go_v2_infrastructure.dart';
import 'package:inappify_sdk/src/platform/mobile/go_v2_protocol.dart';

final _now = DateTime.utc(2026, 9, 17, 12);
const _user = r'$INAAnonymousID:550e8400-e29b-41d4-a716-446655440000';
const _scope = <String, Object?>{
  'issuer': 'https://example.test',
  'appId': 12,
  'projectId': 4,
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('strict JSON and date parsing', () {
    test('accepts nested JSON and escaped string punctuation', () {
      expect(
        strictGoV2Json(r'{"a":[true,null,2.5],"b":"a\"{},b"}')['b'],
        'a"{},b',
      );
    });
    for (final raw in <String>[
      '{"a":1,"a":2}',
      r'{"a":1,"\u0061":2}',
      '{"a":{"b":1,"b":2}}',
      '{}{}',
      '{"a":01}',
      '{"a":NaN}',
      '{"a":1e999}',
      '{"a":1.0000000000000001}',
      '{"a":9223372036854775809}',
      '{"a":1,}',
      '[]',
      '{"a":"line\nnewline"}',
    ]) {
      test(
        'rejects malformed or duplicate JSON: ${raw.length}/${raw.hashCode}',
        () {
          expect(() => strictGoV2Json(raw), throwsA(_error('INVALID_JSON')));
        },
      );
    }
    test('rejects oversized/deep/node-heavy JSON', () {
      expect(
        () => strictGoV2Json('{"a":"${'x' * 1048576}"}'),
        throwsA(_error('BODY_TOO_LARGE')),
      );
      expect(
        () => strictGoV2Json('{"a":${'[' * 40}0${']' * 40}}'),
        throwsA(_error('INVALID_JSON')),
      );
      expect(
        () => strictGoV2Json('{"a":[${List.filled(50001, '0').join(',')}]}'),
        throwsA(_error('INVALID_JSON')),
      );
    });
    test(
      'date parser rejects normalized invalid dates and missing timezone',
      () {
        for (final date in <String>[
          '2026-02-30T01:02:03Z',
          '2026-01-01',
          '2026-01-01T01:02:03',
          '2026-01-01T24:00:00Z',
          '2026-01-01T00:00:00+99:00',
        ]) {
          expect(() => goV2IsoDate(date), throwsA(_error('INVALID_DATE')));
        }
        expect(goV2IsoDate('2026-09-17T15:30:00+03:30'), _now);
      },
    );
    test('base64url must be canonical and unpadded', () {
      expect(goV2Base64Url('AQ'), <int>[1]);
      for (final value in <String>['AQ==', 'AR', 'A+', '', 'A']) {
        expect(
          () => goV2Base64Url(value),
          throwsA(_error('INVALID_BASE64URL')),
        );
      }
    });
  });

  group('signed CustomerInfo', () {
    late _Fixture fixture;
    late GoV2Verifier verifier;
    setUp(() async {
      fixture = await _Fixture.create();
      verifier = GoV2Verifier(pinnedSigningKeys: fixture.pins, now: () => _now);
    });

    test(
      'discovers scope and distinguishes public identity from internal subject',
      () async {
        final verified = await verifier.verify(
          await fixture.envelope(),
          expectedPublicUserId: _user,
        );
        expect(verified.scope, _scope);
        expect(verified.subject, '8675');
        expect(verified.info['originalAppUserId'], _user);
        expect(verified.info.containsKey('attributes'), isFalse);
        expect(verified.expiresAt, _now.add(const Duration(hours: 1)));
      },
    );
    test('supports explicit scope and validates every scope member', () async {
      for (final replacement in <Map<String, Object?>>[
        {..._scope, 'issuer': 'https://wrong.test'},
        {..._scope, 'appId': 8},
        {..._scope, 'projectId': 8},
      ]) {
        await expectLater(
          verifier.verify(
            await fixture.envelope(),
            expectedPublicUserId: _user,
            expectedScope: replacement,
          ),
          throwsA(_error('SCOPE_MISMATCH')),
        );
      }
    });
    test('rejects changed subject and mismatched public identity', () async {
      await expectLater(
        verifier.verify(
          await fixture.envelope(),
          expectedPublicUserId: _user,
          expectedSubject: 'other-internal-customer',
        ),
        throwsA(_error('SCOPE_MISMATCH')),
      );
      await expectLater(
        verifier.verify(
          await fixture.envelope(),
          expectedPublicUserId: 'another-public-user',
        ),
        throwsA(_error('CUSTOMER_MISMATCH')),
      );
    });
    test(
      'signature tampering and unsigned customer changes are rejected',
      () async {
        final tampered = await fixture.envelope();
        final verification = tampered['verification'] as Map<String, dynamic>;
        final parts = (verification['jws'] as String).split('.');
        final signature = goV2Base64Url(parts[2]);
        signature[0] ^= 1;
        parts[2] = _encode(signature);
        verification['jws'] = parts.join('.');
        await expectLater(
          verifier.verify(tampered, expectedPublicUserId: _user),
          throwsA(_error('INVALID_SIGNATURE')),
        );
        final outer = await fixture.envelope();
        (outer['customerInfo'] as Map)['hasUsedTrial'] = true;
        await expectLater(
          verifier.verify(outer, expectedPublicUserId: _user),
          throwsA(_error('CUSTOMER_INFO_MISMATCH')),
        );
      },
    );
    test(
      'rejects alg/typ/crit/b64 and fractional/inconsistent scope claims',
      () async {
        for (final header in <Map<String, Object?>>[
          {'alg': 'HS256'},
          {'typ': 'JWT'},
          {'crit': <String>[]},
          {'b64': true},
        ]) {
          await expectLater(
            verifier.verify(
              await fixture.envelope(header: header),
              expectedPublicUserId: _user,
            ),
            throwsA(_error('INVALID_HEADER')),
          );
        }
        for (final claims in <Map<String, Object?>>[
          {'aud': 'other'},
          {'ver': 1},
          {'app_id': 1.5},
          {'app_id': 0},
          {'project_id': -1},
          {'sub': ''},
          {'iss': '\u0000bad'},
        ]) {
          await expectLater(
            verifier.verify(
              await fixture.envelope(claims: claims),
              expectedPublicUserId: _user,
            ),
            throwsA(_error('SCOPE_MISMATCH')),
          );
        }
      },
    );
    test(
      'expiresAt and exp must match, nbf and requestDate are bounded',
      () async {
        final metadata = await fixture.envelope();
        (metadata['verification'] as Map)['expiresAt'] = '2030-01-01T00:00:00Z';
        await expectLater(
          verifier.verify(metadata, expectedPublicUserId: _user),
          throwsA(_error('EXPIRY_MISMATCH')),
        );
        await expectLater(
          verifier.verify(
            await fixture.envelope(
              claims: {'nbf': _now.millisecondsSinceEpoch ~/ 1000 + 1},
            ),
            expectedPublicUserId: _user,
          ),
          throwsA(_error('NOT_YET_VALID')),
        );
        await expectLater(
          verifier.verify(
            await fixture.envelope(
              info: {
                'requestDate': _now
                    .add(const Duration(hours: 1))
                    .toIso8601String(),
              },
            ),
            expectedPublicUserId: _user,
          ),
          throwsA(_error('INVALID_REQUEST_DATE')),
        );
      },
    );
    test(
      'expired signed cache allowed only explicitly and still checks identity',
      () async {
        final old = await fixture.envelope(
          claims: {'exp': _now.millisecondsSinceEpoch ~/ 1000 - 1},
          info: {
            'requestDate': _now
                .subtract(const Duration(hours: 1))
                .toIso8601String(),
          },
        );
        await expectLater(
          verifier.verify(old, expectedPublicUserId: _user),
          throwsA(_error('EXPIRED_SIGNATURE')),
        );
        expect(
          (await verifier.verify(
            old,
            expectedPublicUserId: _user,
            allowExpiredCache: true,
          )).subject,
          '8675',
        );
        await expectLater(
          verifier.verify(
            old,
            expectedPublicUserId: 'different',
            allowExpiredCache: true,
          ),
          throwsA(_error('CUSTOMER_MISMATCH')),
        );
      },
    );
    test(
      'rejects invalid entitlement expiration, accepts nullable entitlements',
      () async {
        await expectLater(
          verifier.verify(
            await fixture.envelope(
              info: {
                'entitlements': [
                  {'identifier': 'pro', 'expiration_date': 'not-a-date'},
                ],
              },
            ),
            expectedPublicUserId: _user,
          ),
          throwsA(_error('INVALID_DATE')),
        );
        expect(
          (await verifier.verify(
            await fixture.envelope(),
            expectedPublicUserId: _user,
          )).info['entitlements'],
          isNull,
        );
      },
    );
    test(
      'JWKS cannot introduce new material or overwrite a trusted key',
      () async {
        final other = await _Fixture.create(seed: 2);
        verifier.refresh({
          'keys': [
            fixture.jwk('alias'),
            other.jwk('attacker'),
            other.jwk('test-key'),
          ],
        });
        expect(verifier.known('alias'), isTrue);
        expect(verifier.known('attacker'), isFalse);
        await verifier.verify(
          await fixture.envelope(),
          expectedPublicUserId: _user,
        );
        await verifier.verify(
          await fixture.envelope(header: {'kid': 'alias'}),
          expectedPublicUserId: _user,
        );
      },
    );
    test('errors never include public identity or credentials', () async {
      try {
        await verifier.verify(
          await fixture.envelope(),
          expectedPublicUserId: 'private-user',
        );
        fail('expected verification error');
      } on GoV2ProtocolException catch (error) {
        expect('${error.details} $error', isNot(contains('private-user')));
        expect('${error.details} $error', isNot(contains(_user)));
      }
    });
  });

  group('isolated native infrastructure', () {
    const channel = MethodChannel('inappify_sdk');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    tearDown(() => messenger.setMockMethodCallHandler(channel, null));
    test('reads/writes V2 Keychain state and rejects old namespaces', () async {
      final documents = <String, String>{};
      messenger.setMockMethodCallHandler(channel, (call) async {
        final args = call.arguments as Map;
        final namespace = args['namespace'] as String;
        if (call.method == 'sdkReadGoState') return documents[namespace];
        expect(call.method, 'sdkWriteGoState');
        documents[namespace] = args['document'] as String;
        return null;
      });
      final go = MethodChannelGoV2Storage();
      await go.write('{"session":"go-secret"}');
      expect(await go.read(), '{"session":"go-secret"}');
      for (final namespace in ['directCompanion', 'legacyOfflineV1']) {
        expect(
          () => MethodChannelGoV2Storage(namespace: namespace),
          throwsA(_error('INVALID_STORAGE_NAMESPACE')),
        );
      }
      expect(
        () => MethodChannelGoV2Storage(namespace: 'token'),
        throwsA(_error('INVALID_STORAGE_NAMESPACE')),
      );
    });
    test(
      'storage errors discard provider details and never succeed silently',
      () async {
        messenger.setMockMethodCallHandler(channel, (_) async {
          throw PlatformException(
            code: 'secret-code',
            message: 'private-token',
            details: 'receipt',
          );
        });
        await expectLater(
          MethodChannelGoV2Storage().write('{}'),
          throwsA(_error('WRITE_FAILED')),
        );
        await expectLater(
          MethodChannelGoV2Storage().read(),
          throwsA(_error('READ_FAILED')),
        );
      },
    );
    test('metadata requires positive exact build and package', () async {
      var version = <String, Object?>{
        'identifierValue': 'example.test.app',
        'versionName': '1.0',
        'versionCode': 1,
      };
      messenger.setMockMethodCallHandler(channel, (call) async {
        expect(call.method, 'sdkGetMobileMetadata');
        return version;
      });
      expect((await readGoV2MobileMetadata()).versionCode, 1);
      version = {...version, 'versionCode': 1.5};
      await expectLater(
        readGoV2MobileMetadata(),
        throwsA(_error('INVALID_APP_METADATA')),
      );
    });
  });

  group('Go HTTP transport', () {
    test(
      'no redirects and safe typed diagnostic; credentials only on request',
      () async {
        final adapter = _Adapter(
          (options) => ResponseBody.fromString(
            '{"status":true,"sessionToken":"response-secret","customerInfo":{"originalAppUserId":"private-customer"}}',
            200,
          ),
        );
        final transport = DioGoV2Transport(
          dio: Dio()..httpClientAdapter = adapter,
        );
        final pendingTrace = transport.traces.first;
        final response = await transport.request(
          'configure',
          bearer: 'request-secret',
          body: {
            'appUserIdentifier': 'private-user',
            'identifierValue': 'example.app',
          },
        );
        final trace = await pendingTrace;
        expect(response['sessionToken'], 'response-secret');
        expect(adapter.requests.single.followRedirects, isFalse);
        expect(
          adapter.requests.single.headers['Authorization'],
          'Bearer request-secret',
        );
        for (final secret in [
          'request-secret',
          'response-secret',
          'private-customer',
          'private-user',
        ]) {
          expect(jsonEncode(trace), isNot(contains(secret)));
        }
        expect(InappifyHttpTrace.fromMap(trace).method, 'POST');
        await transport.close();
      },
    );
    test('public-keys uses GET and drops bearer/body', () async {
      final adapter = _Adapter(
        (_) => ResponseBody.fromString('{"keys":[]}', 200),
      );
      final transport = DioGoV2Transport(
        dio: Dio()..httpClientAdapter = adapter,
      );
      await transport.request('public-keys', bearer: 'not-sent');
      expect(adapter.requests.single.method, 'GET');
      expect(
        adapter.requests.single.headers.containsKey('Authorization'),
        isFalse,
      );
      expect(adapter.requests.single.data, isNull);
      await transport.close();
    });
    test(
      'retry honors server lower bounds and unsafe methods can disable retry',
      () async {
        var count = 0;
        final adapter = _Adapter(
          (_) => ++count == 1
              ? ResponseBody.fromString(
                  '{"status":false,"code":"RATE_LIMIT"}',
                  429,
                  headers: {
                    'retry-after': ['7'],
                    'X-RateLimit-Reset': [
                      '${_now.millisecondsSinceEpoch ~/ 1000 + 8}',
                    ],
                  },
                )
              : ResponseBody.fromString('{"status":true}', 200),
        );
        final waits = <Duration>[];
        final transport = DioGoV2Transport(
          dio: Dio()..httpClientAdapter = adapter,
          now: () => _now,
          jitterMilliseconds: () => 0,
          sleep: (duration) async {
            waits.add(duration);
          },
        );
        await transport.request('offerings', bearer: 'token');
        expect(waits, [const Duration(seconds: 8)]);
        count = 0;
        await expectLater(
          transport.request('login', retry: false),
          throwsA(_error('RATE_LIMIT')),
        );
        expect(count, 1);
        await transport.close();
      },
    );
    test('very large retry headers cannot overflow to a short retry', () async {
      var count = 0;
      final adapter = _Adapter(
        (_) => ++count == 1
            ? ResponseBody.fromString(
                '{"status":false}',
                429,
                headers: {
                  'retry-after': ['9223372036854775807'],
                },
              )
            : ResponseBody.fromString('{"status":true}', 200),
      );
      final waits = <Duration>[];
      final transport = DioGoV2Transport(
        dio: Dio()..httpClientAdapter = adapter,
        jitterMilliseconds: () => 0,
        sleep: (duration) async {
          waits.add(duration);
        },
      );
      await transport.request('offerings');
      expect(waits.single, greaterThan(const Duration(days: 36500)));
      await transport.close();
    });
    test(
      '204 attributes success, redirect and oversized response rejected',
      () async {
        var mode = 0;
        final adapter = _Adapter(
          (_) => switch (mode) {
            0 => ResponseBody.fromString('', 204),
            1 => ResponseBody.fromString(
              '',
              302,
              headers: {
                'location': ['https://evil.test/'],
              },
            ),
            _ => ResponseBody.fromString('x' * (1048576 + 1), 200),
          },
        );
        final transport = DioGoV2Transport(
          dio: Dio()..httpClientAdapter = adapter,
        );
        expect(await transport.request('attributes'), isEmpty);
        mode = 1;
        await expectLater(
          transport.request('configure'),
          throwsA(_error('HTTP_302')),
        );
        mode = 2;
        await expectLater(
          transport.request('customerInfo'),
          throwsA(_error('BODY_TOO_LARGE')),
        );
        await transport.close();
      },
    );
    test(
      'network disable and invalid URL/endpoint never call adapter',
      () async {
        final adapter = _Adapter((_) => throw StateError('must not call'));
        final transport = DioGoV2Transport(
          dio: Dio()..httpClientAdapter = adapter,
        )..enabled = false;
        await expectLater(
          transport.request('configure'),
          throwsA(_error('V2_DISABLED')),
        );
        transport.enabled = true;
        await expectLater(
          transport.request('../steal'),
          throwsA(_error('INVALID_ENDPOINT')),
        );
        expect(adapter.requests, isEmpty);
        expect(
          () => DioGoV2Transport(baseUrl: 'http://example.test/app/v2/'),
          throwsA(_error('INVALID_BASE_URL')),
        );
        await transport.close();
      },
    );
  });
}

Matcher _error(String code) =>
    isA<GoV2ProtocolException>().having((e) => e.code, 'code', code);
String _encode(List<int> bytes) => base64Url.encode(bytes).replaceAll('=', '');

class _Fixture {
  _Fixture(this.key, this.publicKey);
  final SimpleKeyPair key;
  final SimplePublicKey publicKey;
  static Future<_Fixture> create({int seed = 1}) async {
    final key = await Ed25519().newKeyPairFromSeed(List<int>.filled(32, seed));
    return _Fixture(key, await key.extractPublicKey());
  }

  Map<String, String> get pins => {'test-key': _encode(publicKey.bytes)};
  Map<String, dynamic> jwk(String kid) => {
    'kty': 'OKP',
    'crv': 'Ed25519',
    'alg': 'EdDSA',
    'use': 'sig',
    'kid': kid,
    'x': _encode(publicKey.bytes),
  };

  Future<Map<String, dynamic>> envelope({
    Map<String, Object?> claims = const {},
    Map<String, Object?> info = const {},
    Map<String, Object?> header = const {},
  }) async {
    final customer = <String, Object?>{
      'originalAppUserId': _user,
      'requestDate': _now.toIso8601String(),
      'entitlements': null,
      'attributes': <Object?>[],
      'hasUsedTrial': false,
      ...info,
    };
    final payload = <String, Object?>{
      'iss': _scope['issuer'],
      'app_id': 12,
      'project_id': 4,
      'aud': 'inappify-sdk',
      'ver': 2,
      'sub': '8675',
      'exp': _now.add(const Duration(hours: 1)).millisecondsSinceEpoch ~/ 1000,
      'customer_info': customer,
      ...claims,
    };
    final jwsHeader = <String, Object?>{
      'alg': 'EdDSA',
      'typ': 'INA-CUSTOMER-INFO',
      'kid': 'test-key',
      ...header,
    };
    final input =
        '${_encode(utf8.encode(jsonEncode(jwsHeader)))}.${_encode(utf8.encode(jsonEncode(payload)))}';
    final signature = await Ed25519().sign(ascii.encode(input), keyPair: key);
    return <String, dynamic>{
      'customerInfo': jsonDecode(jsonEncode(customer)),
      'verification': <String, dynamic>{
        'algorithm': 'EdDSA',
        'keyId': jwsHeader['kid'],
        'jws': '$input.${_encode(signature.bytes)}',
        'expiresAt': DateTime.fromMillisecondsSinceEpoch(
          (payload['exp'] as int) * 1000,
          isUtc: true,
        ).toIso8601String(),
      },
    };
  }
}

class _Adapter implements HttpClientAdapter {
  _Adapter(this.respond);
  final ResponseBody Function(RequestOptions options) respond;
  final List<RequestOptions> requests = [];
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    return respond(options);
  }

  @override
  void close({bool force = false}) {}
}
