import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inappify_sdk/src/platform/mobile/go_v2_infrastructure.dart';
import 'package:inappify_sdk/src/platform/mobile/go_v2_protocol.dart';

import 'http_fixture.dart' show DirectAdapter;

void main() {
  test(
    'separate SDK/commerce origins; Bearer and attempt headers are redacted',
    () async {
      final adapter = DirectAdapter(
        (_) => ResponseBody.fromString(
          '{"status":true,"data":{"purchaseStatus":"NEEDTOPAY","url":"https://pay.inappify.com/private-checkout"}}',
          200,
        ),
      );
      final sdk = DioGoV2Transport(dio: Dio()..httpClientAdapter = adapter);
      final commerce = DioGoV2Transport.commerce(
        dio: Dio()..httpClientAdapter = adapter,
      );
      final traces = <Map<String, Object?>>[];
      final subscriptions = [
        sdk.traces.listen(traces.add),
        commerce.traces.listen(traces.add),
      ];
      await sdk.request(
        'login',
        bearer: 'private-session',
        headers: {'X-Inappify-Login-Attempt': 'private-attempt'},
        body: {'appUserIdentifier': 'private-user'},
      );
      await commerce.request(
        'purchase',
        bearer: 'private-session',
        retry: false,
        body: {'productIdentifier': 'private-product', 'isCrypto': false},
      );
      await Future<void>.delayed(Duration.zero);
      expect(adapter.requests.map((r) => r.uri.toString()), [
        'https://service.inappify.com/app/v2/login',
        'https://api.inappify.com/app/v2/purchase',
      ]);
      expect(
        adapter.requests.first.headers['X-Inappify-Login-Attempt'],
        'private-attempt',
      );
      expect(
        adapter.requests.last.headers['Authorization'],
        'Bearer private-session',
      );
      expect(
        adapter.requests.last.headers['User-Agent'],
        'InAppify-Flutter-iOS/0.2.3',
      );
      expect(jsonEncode(traces), isNot(contains('private-')));
      expect(
        (traces.first['requestHeaders'] as Map)['X-Inappify-Login-Attempt'],
        '<redacted>',
      );
      for (final subscription in subscriptions) {
        await subscription.cancel();
      }
      await sdk.close();
      await commerce.close();
    },
  );

  test('stable login attempt header survives transport retries', () async {
    var requests = 0;
    final adapter = DirectAdapter(
      (_) => ++requests == 1
          ? ResponseBody.fromString('{"status":false,"code":"BUSY"}', 503)
          : ResponseBody.fromString('{"status":true}', 200),
    );
    final transport = DioGoV2Transport(
      dio: Dio()..httpClientAdapter = adapter,
      sleep: (_) async {},
      jitterMilliseconds: () => 0,
    );
    await transport.request(
      'login',
      bearer: 'fixture',
      headers: {'X-Inappify-Login-Attempt': 'same-attempt'},
    );
    expect(adapter.requests, hasLength(2));
    expect(
      adapter.requests.map((r) => r.headers['X-Inappify-Login-Attempt']),
      everyElement('same-attempt'),
    );
    await transport.close();
  });

  for (final status in [302, 429, 500, 502, 503, 504]) {
    test(
      'checkout failure $status never auto-retries or follows redirect',
      () async {
        final adapter = DirectAdapter(
          (_) => ResponseBody.fromString(
            '{"status":false}',
            status,
            headers: {
              'location': ['https://untrusted.example.test'],
            },
          ),
        );
        final transport = DioGoV2Transport.commerce(
          dio: Dio()..httpClientAdapter = adapter,
        );
        await expectLater(
          transport.request('purchase', bearer: 'fixture', retry: false),
          throwsA(isA<GoV2ProtocolException>()),
        );
        expect(adapter.requests, hasLength(1));
        expect(adapter.requests.single.followRedirects, false);
        await transport.close();
      },
    );
  }

  for (final status in [502, 504]) {
    test(
      'SDK resource transient $status retries with bounded attempts',
      () async {
        final adapter = DirectAdapter(
          (_) => ResponseBody.fromString('{"status":false}', status),
        );
        final transport = DioGoV2Transport(
          dio: Dio()..httpClientAdapter = adapter,
          sleep: (_) async {},
          jitterMilliseconds: () => 0,
        );
        await expectLater(
          transport.request('customerInfo', bearer: 'fixture'),
          throwsA(
            isA<GoV2ProtocolException>().having(
              (e) => e.retryable,
              'retryable',
              true,
            ),
          ),
        );
        expect(adapter.requests, hasLength(4));
        await transport.close();
      },
    );
  }

  for (final code in <Object>[42, -1, 1.5, '42']) {
    test(
      'commerce numeric errorCode ${code.runtimeType}/$code is exact and nonnegative',
      () async {
        final adapter = DirectAdapter(
          (_) => ResponseBody.fromString(
            jsonEncode({'status': false, 'errorCode': code}),
            400,
          ),
        );
        final transport = DioGoV2Transport.commerce(
          dio: Dio()..httpClientAdapter = adapter,
        );
        await expectLater(
          transport.request('purchase', retry: false),
          throwsA(
            isA<GoV2ProtocolException>().having(
              (e) => e.code,
              'code',
              code == 42 ? 'ERROR_CODE_42' : 'HTTP_400',
            ),
          ),
        );
        await transport.close();
      },
    );
  }

  test(
    'transport rejects cross-service endpoints and arbitrary attempt headers',
    () async {
      final adapter = DirectAdapter(
        (_) => throw StateError('HTTP must not run'),
      );
      final sdk = DioGoV2Transport(dio: Dio()..httpClientAdapter = adapter);
      final commerce = DioGoV2Transport.commerce(
        dio: Dio()..httpClientAdapter = adapter,
      );
      for (final invalid in [
        () => sdk.request('purchase'),
        () => commerce.request('configure'),
        () => commerce.request('../purchase'),
        () => sdk.request('login', headers: {'Authorization': 'override'}),
        () => sdk.request(
          'logout',
          headers: {'X-Inappify-Logout-Attempt': 'bad\r\nheader'},
        ),
      ]) {
        await expectLater(invalid(), throwsA(isA<GoV2ProtocolException>()));
      }
      expect(adapter.requests, isEmpty);
      await sdk.close();
      await commerce.close();
    },
  );

  for (final body in [
    '{"status":1}',
    '{"status":true,"data":{},"data":{}}',
    '{"status":true,"data":NaN}',
  ]) {
    test('commerce strict envelope rejects ${body.hashCode}', () async {
      final adapter = DirectAdapter((_) => ResponseBody.fromString(body, 200));
      final transport = DioGoV2Transport.commerce(
        dio: Dio()..httpClientAdapter = adapter,
      );
      await expectLater(
        transport.request('purchase', retry: false),
        throwsA(isA<GoV2ProtocolException>()),
      );
      expect(adapter.requests, hasLength(1));
      await transport.close();
    });
  }
}
