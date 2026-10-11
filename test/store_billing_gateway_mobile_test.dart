@TestOn('vm')
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inappify_sdk/models/enums/market.dart';
import 'package:inappify_sdk/src/billing/store_billing_gateway_mobile.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const poolakeyChannel = MethodChannel('ir.cafebazaar.flutter_poolakey');
  const myketChannel = MethodChannel('myket_iap');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  var marketplaceCalls = 0;

  setUp(() {
    marketplaceCalls = 0;
    for (final channel in [poolakeyChannel, myketChannel]) {
      messenger.setMockMethodCallHandler(channel, (_) async {
        marketplaceCalls++;
        return null;
      });
    }
  });

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    for (final channel in [poolakeyChannel, myketChannel]) {
      messenger.setMockMethodCallHandler(channel, null);
    }
  });

  test(
    'iOS preserves NONE success and its existing unsupported store behavior',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      final gateway = createStoreBillingGateway();
      for (final market in Market.values) {
        expect(
          await gateway.initialize(market: market, publicKey: 'synthetic-key'),
          market == Market.none,
        );
        expect(
          await gateway.purchase(
            market: market,
            publicKey: 'synthetic-key',
            productIdentifier: 'synthetic-product',
            payload: '{}',
          ),
          isNull,
        );
      }
      expect(marketplaceCalls, 0);
    },
  );

  test(
    'Android Bazaar cannot fall back to a second Dart receipt owner',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      final gateway = createStoreBillingGateway();
      expect(
        await gateway.initialize(market: Market.none, publicKey: ''),
        isTrue,
      );
      expect(
        await Future.wait([
          gateway.initialize(market: Market.bazar, publicKey: 'synthetic-key'),
          gateway.initialize(market: Market.bazar, publicKey: 'synthetic-key'),
        ]),
        [false, false],
      );
      expect(
        await gateway.purchase(
          market: Market.bazar,
          publicKey: 'synthetic-key',
          productIdentifier: 'synthetic-product',
          payload: '{}',
        ),
        isNull,
      );
      expect(marketplaceCalls, 0);
    },
  );

  test(
    'Myket remains unavailable without invoking a marketplace channel',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      final gateway = createStoreBillingGateway();
      expect(
        await gateway.initialize(
          market: Market.myket,
          publicKey: 'synthetic-key',
        ),
        isFalse,
      );
      expect(
        await gateway.purchase(
          market: Market.myket,
          publicKey: 'synthetic-key',
          productIdentifier: 'synthetic-product',
          payload: '{}',
        ),
        isNull,
      );
      expect(marketplaceCalls, 0);
    },
  );
}
