import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inappify_sdk/src/platform/mobile/go_v2_infrastructure.dart';
import 'package:inappify_sdk/src/platform/mobile/go_v2_protocol.dart';
import 'http_fixture.dart' show DirectAdapter;

void main() {
  test(
    'iOS Direct V2 endpoints have Bearer, empty delivery bodies and redacted traces',
    () async {
      final adapter = DirectAdapter(
        (_) => ResponseBody.fromString(
          jsonEncode({
            'status': true,
            'data': {
              'deliveryId': 87654321,
              'transactionId': 'private-transaction',
              'productIdentifier': 'private-product',
              'status': 'COMPLETED',
            },
          }),
          200,
        ),
      );
      final transport = DioGoV2Transport.commerce(
        dio: Dio()..httpClientAdapter = adapter,
      );
      final traces = <Map<String, Object?>>[];
      final subscription = transport.traces.listen(traces.add);
      for (final endpoint in [
        'purchase',
        'consumable-deliveries/pending',
        'consumable-deliveries/87654321/delivered',
      ]) {
        await transport.request(
          endpoint,
          bearer: 'private-session',
          retry: false,
          body: endpoint == 'purchase'
              ? {
                  'productIdentifier': 'private-product',
                  'offeringIdentifier': 'main',
                  'isCrypto': false,
                }
              : {},
        );
      }
      await Future<void>.delayed(Duration.zero);
      expect(adapter.requests.map((r) => r.uri.toString()), [
        'https://api.inappify.com/app/v2/purchase',
        'https://api.inappify.com/app/v2/consumable-deliveries/pending',
        'https://api.inappify.com/app/v2/consumable-deliveries/87654321/delivered',
      ]);
      for (final request in adapter.requests) {
        expect(request.headers['Authorization'], 'Bearer private-session');
        expect(request.headers['Accept'], 'application/json');
        expect(request.followRedirects, false);
        final body = jsonDecode(request.data as String) as Map;
        expect(
          body.keys.toSet().intersection({
            'apikey',
            'token',
            'appIdentifier',
            'country',
            'appVersion',
            'forceVersion',
          }),
          isEmpty,
        );
      }
      expect(adapter.requests.skip(1).map((r) => r.data), everyElement('{}'));
      expect(jsonEncode(traces), isNot(contains('private-')));
      expect(jsonEncode(traces), isNot(contains('87654321')));
      await subscription.cancel();
      await transport.close();
    },
  );
  for (final endpoint in [
    'consumable-deliveries/0/delivered',
    'consumable-deliveries/../delivered',
    'store/purchases',
  ]) {
    test('iOS rejects unsupported endpoint $endpoint before HTTP', () async {
      final adapter = DirectAdapter((_) => throw StateError('No HTTP'));
      final transport = DioGoV2Transport.commerce(
        dio: Dio()..httpClientAdapter = adapter,
      );
      await expectLater(
        transport.request(endpoint),
        throwsA(isA<GoV2ProtocolException>()),
      );
      expect(adapter.requests, isEmpty);
      await transport.close();
    });
  }
}
