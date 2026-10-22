import 'package:flutter_test/flutter_test.dart';
import 'package:inappify_sdk/inappify_sdk.dart';
import 'package:inappify_sdk/inappify_sdk_platform_interface.dart';
import 'package:inappify_sdk/models/validate_discount_code_data.dart';
import 'package:inappify_sdk/src/bootstrap/inappify_sdk_runtime.dart';
import 'package:inappify_sdk/src/platform/mobile/go_v2_platform.dart';
import 'package:inappify_sdk/src/platform/web/web_inappify_bridge.dart';
import 'package:inappify_sdk/src/platform/web/web_inappify_platform.dart';

import 'mobile/go_commerce_fixture.dart' as direct;
import 'mobile/go_v2_platform_test.dart' as mobile;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late InappifySdkPlatform previous;
  late _DiscountBridge bridge;
  late WebInappifyPlatform platform;

  setUp(() async {
    previous = InappifySdkPlatform.instance;
    bridge = _DiscountBridge();
    platform = WebInappifyPlatform(bridge: bridge);
    await InappifySdkRuntime.coordinator.resetForTesting();
    InappifySdkPlatform.instance = platform;
    expect(await InappifySdk.configure(apiKey: 'public-fixture'), true);
    bridge.calls.clear();
  });

  tearDown(() async {
    await InappifySdkRuntime.coordinator.resetForTesting();
    InappifySdkPlatform.instance = previous;
    await platform.dispose();
  });

  for (final typed in [false, true]) {
    final api = typed ? 'Result' : 'simple';
    Future<ValidateDiscountCodeData?> validate([String? identifier]) async {
      if (typed) {
        final result = identifier == null
            ? await InappifySdk.getDiscountedPaymentLinksResult('SAVE20')
            : await InappifySdk.getDiscountedPaymentLinksResult(
                'SAVE20',
                offeringIdentifier: identifier,
              );
        return result.data;
      }
      return identifier == null
          ? InappifySdk.getDiscountedPaymentLinks('SAVE20')
          : InappifySdk.getDiscountedPaymentLinks(
              'SAVE20',
              offeringIdentifier: identifier,
            );
    }

    test(
      '$api forwards selected placement offering exactly and preserves catalog',
      () async {
        final original = InappifySdk.snapshot.offerings;
        final result = await validate('special');
        expect(result?.offering?.identifier, 'special');
        expect(
          result?.offering?.packages?.single.product?.prices?.single.price,
          190000,
        );
        expect(result?.code, 'SAVE20');
        expect(result?.isValid, true);
        expect(result?.errorCode, 0);
        expect(result?.paymentLinks?.single.offering, 'special');
        expect(
          result?.paymentLinks?.single.url,
          'https://pay.example.test/special',
        );
        expect(bridge.calls.single.method, 'validateDiscountCode');
        expect(bridge.calls.single.arguments, ['SAVE20', 'special']);
        expect(InappifySdk.snapshot.offerings, same(original));
        expect(InappifySdk.snapshot.offerings?.current?.identifier, 'main');
        expect(
          original
              ?.all['special']
              ?.packages
              ?.single
              .product
              ?.prices
              ?.single
              .price,
          250000,
        );
        expect(
          bridge.catalog['current'],
          same((bridge.catalog['all'] as List).first),
        );
      },
    );

    test('$api without identifier keeps current-offering behavior', () async {
      final result = await validate();
      expect(result?.offering?.identifier, 'main');
      expect(bridge.calls.map((call) => call.method), [
        'getCurrentOffering',
        'validateDiscountCode',
      ]);
      expect(bridge.calls.last.arguments, ['SAVE20', 'main']);
    });

    for (final identifier in ['', '   ', 'missing']) {
      test(
        '$api rejects invalid identifier "$identifier" without default fallback',
        () async {
          final original = InappifySdk.snapshot.offerings;
          expect(await validate(identifier), isNull);
          expect(InappifySdk.lastFailure, isNotNull);
          expect(InappifySdk.snapshot.offerings, same(original));
          if (identifier == 'missing') {
            expect(bridge.calls.single.method, 'validateDiscountCode');
            expect(bridge.calls.single.arguments, ['SAVE20', identifier]);
            expect(InappifySdk.lastFailure?.details['status'], 422);
          } else {
            expect(bridge.calls, isEmpty);
            expect(
              InappifySdk.lastFailure?.code,
              InappifyFailureCode.invalidConfiguration,
            );
          }
        },
      );
    }

    test('$api rejects a different offering returned by provider', () async {
      bridge.returnedIdentifier = 'main';
      expect(await validate('special'), isNull);
      expect(
        InappifySdk.lastFailure?.code,
        InappifyFailureCode.malformedResponse,
      );
      expect(bridge.calls.single.arguments, ['SAVE20', 'special']);
      expect(InappifySdk.snapshot.offerings?.current?.identifier, 'main');
    });

    test('$api keeps iOS discount wire request code-only', () async {
      final transport = mobile.FakeTransport();
      final backend = GoV2Platform(
        transport: transport,
        commerceTransport: mobile.FakeTransport(),
        storage: mobile.MemoryStore(),
        verifier: mobile.StateVerifier(),
        metadataProvider: () async => direct.metadata,
        now: () => mobile.now,
        anonymousIdFactory: () => mobile.anonymous,
        backgroundRecovery: false,
      );
      addTearDown(backend.close);
      await InappifySdkRuntime.coordinator.resetForTesting();
      InappifySdkPlatform.instance = backend;
      expect(await InappifySdk.configure(apiKey: 'public-fixture'), true);
      transport.calls.clear();
      transport.respond = (_, _) async => {
        'data': {'is_valid': true, 'error_code': 0, 'payment_links': []},
      };
      expect((await validate('special'))?.isValid, true);
      expect(transport.calls.single.endpoint, 'validateDiscountCode');
      expect(transport.calls.single.body, {'code': 'SAVE20'});
      expect((await validate())?.isValid, true);
      expect(transport.calls.last.body, {'code': 'SAVE20'});
    });
  }
}

Map<String, Object?> _offering(String identifier, {int amount = 250000}) => {
  'identifier': identifier,
  'isDefault': identifier == 'main',
  'packages': [
    {
      'identifier': 'monthly',
      'product': {
        'identifier': 'subscription',
        'prices': [
          {'amount': amount, 'currency': 'IRR'},
        ],
      },
    },
  ],
};

class _DiscountBridge implements InappifyWebBridge {
  _DiscountBridge() {
    final main = _offering('main');
    catalog = {
      'all': [main, _offering('special')],
      'current': main,
    };
  }

  late final Map<String, Object?> catalog;
  final calls = <({String method, List<Object?> arguments})>[];
  String? returnedIdentifier;

  @override
  bool get isAvailable => true;
  @override
  String get sdkVersion => '0.2.0';
  @override
  Stream<InappifyWebBridgeEvent> get events => const Stream.empty();
  @override
  Future<Object?> configure(Map<String, Object?> options) async => null;

  @override
  Future<Object?> call(
    String method, {
    List<Object?> positionalArguments = const [],
    InappifyRequestCancellation? cancellation,
    bool injectAbortSignal = false,
  }) async {
    calls.add((method: method, arguments: List.of(positionalArguments)));
    if (method == 'getCurrentOffering') return catalog['current'];
    if (method == 'validateDiscountCode') {
      final identifier = positionalArguments[1] as String;
      if (identifier == 'missing') {
        throw const InappifyWebBridgeException(
          code: 'OFFERING_NOT_FOUND',
          status: 422,
        );
      }
      final selected = returnedIdentifier ?? identifier;
      return {
        'discount': {'code': 'SAVE20', 'isValid': true, 'percent': 20},
        'offering': _offering(selected, amount: 190000),
        'error_code': 0,
        'payment_links': [
          {'offering': selected, 'url': 'https://pay.example.test/$selected'},
        ],
      };
    }
    return null;
  }

  @override
  Object? readProperty(String name) => switch (name) {
    'offerings' => catalog,
    'sessionState' => 'anonymous',
    'persistenceMode' => 'durable',
    'customerInfo' => {'originalAppUserId': 'anonymous', 'entitlements': {}},
    _ => null,
  };
  @override
  void persistPendingCheckout(String checkoutId) {}
  @override
  void clearPendingCheckout() {}
  @override
  String? readPendingCheckout() => null;
  @override
  Future<void> dispose() async {}
}
