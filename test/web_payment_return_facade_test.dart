import 'package:flutter_test/flutter_test.dart';
import 'package:inappify_sdk/inappify_sdk.dart';
import 'package:inappify_sdk/inappify_sdk_platform_interface.dart';
import 'package:inappify_sdk/models/customer_info.dart';
import 'package:inappify_sdk/models/entitlement_model.dart';
import 'package:inappify_sdk/models/purchase_result.dart';
import 'package:inappify_sdk/src/bootstrap/inappify_sdk_runtime.dart';

void main() {
  late InappifySdkPlatform previousPlatform;
  late _PendingCheckoutPlatform candidate;

  setUp(() async {
    previousPlatform = InappifySdkPlatform.instance;
    candidate = _PendingCheckoutPlatform();
    await InappifySdkRuntime.coordinator.resetForTesting();
    InappifySdkPlatform.instance = candidate;
  });

  tearDown(() async {
    await InappifySdkRuntime.coordinator.resetForTesting();
    InappifySdkPlatform.instance = previousPlatform;
  });

  test('handlePaymentReturn falls back to the persisted checkout id', () async {
    expect(await InappifySdk.configure(apiKey: 'public-web-key'), isTrue);
    candidate.pendingCheckoutId = 'checkout-from-session-storage';

    final paid = await InappifySdk.handlePaymentReturnResult(
      timeoutMs: 45000,
      intervalMs: 1200,
    );

    expect(paid.isSuccess, isTrue);
    expect(paid.data?.isPaid, isTrue);
    expect(candidate.pendingCheckoutReadCount, 1);
    expect(candidate.paymentReturnRequests, hasLength(1));
    expect(candidate.paymentReturnRequests.single.toMap(), <String, Object?>{
      'checkoutId': 'checkout-from-session-storage',
      'timeoutMs': 45000,
      'intervalMs': 1200,
    });

    candidate.pendingCheckoutId = null;
    final missing = await InappifySdk.handlePaymentReturnResult();

    expect(missing.failure?.code, InappifyFailureCode.invalidConfiguration);
    expect(candidate.pendingCheckoutReadCount, 2);
    expect(candidate.paymentReturnRequests, hasLength(1));
  });

  test(
    'mirrored entitlement activity respects beta.1 expiration data',
    () async {
      candidate.snapshot = InappifySdkSnapshot(
        accessToken: null,
        apiKey: 'public-web-key',
        storeInfo: 'web',
        customerInfo: CustomerInfo(
          entitlements: <EntitlementModel>[
            EntitlementModel(identifier: 'no-expiration', isActive: true),
            EntitlementModel(
              identifier: 'invalid-expiration',
              isActive: true,
              expirationDate: 'not-an-iso-date',
            ),
            EntitlementModel(
              identifier: 'future-expiration',
              isActive: true,
              expirationDate: DateTime.now()
                  .toUtc()
                  .add(const Duration(days: 1))
                  .toIso8601String(),
            ),
            EntitlementModel(
              identifier: 'past-expiration',
              isActive: true,
              expirationDate: DateTime.now()
                  .toUtc()
                  .subtract(const Duration(days: 1))
                  .toIso8601String(),
            ),
            EntitlementModel(
              identifier: 'server-inactive',
              isActive: false,
              expirationDate: DateTime.now()
                  .toUtc()
                  .add(const Duration(days: 1))
                  .toIso8601String(),
            ),
          ],
        ),
      );

      expect(await InappifySdk.configure(apiKey: 'public-web-key'), isTrue);

      expect(InappifySdk.hasEntitlement('no-expiration'), isTrue);
      expect(InappifySdk.hasEntitlement('invalid-expiration'), isTrue);
      expect(InappifySdk.hasEntitlement('future-expiration'), isTrue);
      expect(InappifySdk.hasEntitlement('past-expiration'), isFalse);
      expect(InappifySdk.hasEntitlement('server-inactive'), isFalse);
      expect(
        InappifySdk.getEntitlement('future-expiration')?.identifier,
        'future-expiration',
      );
      expect(InappifySdk.getEntitlement('past-expiration'), isNull);
    },
  );

  test('typed checkout failures expose generated idempotency keys', () async {
    expect(await InappifySdk.configure(apiKey: 'public-web-key'), isTrue);

    final purchase = await InappifySdk.purchaseResult(
      productIdentifier: 'premium-monthly',
      offeringIdentifier: 'main',
      packageIdentifier: 'monthly',
    );
    final checkout = await InappifySdk.createCheckout(
      productIdentifier: 'premium-monthly',
      offeringIdentifier: 'main',
      packageIdentifier: 'monthly',
    );

    final purchaseKey = candidate.purchaseRequests.single.idempotencyKey;
    final checkoutKey = candidate.checkoutRequests.single.idempotencyKey;
    expect(purchase.failure?.code, InappifyFailureCode.network);
    expect(purchase.failure?.details['idempotencyKey'], purchaseKey);
    expect(purchaseKey, startsWith('purchase-'));
    expect(checkout.failure?.code, InappifyFailureCode.network);
    expect(checkout.failure?.details['idempotencyKey'], checkoutKey);
    expect(checkoutKey, startsWith('checkout-'));
    expect(checkoutKey, isNot(purchaseKey));
  });
}

class _PendingCheckoutPlatform extends InappifySdkPlatform {
  String? pendingCheckoutId;
  int pendingCheckoutReadCount = 0;
  final List<InappifyPaymentReturnRequest> paymentReturnRequests =
      <InappifyPaymentReturnRequest>[];
  final List<InappifyPurchaseRequest> purchaseRequests =
      <InappifyPurchaseRequest>[];
  final List<InappifyPurchaseRequest> checkoutRequests =
      <InappifyPurchaseRequest>[];

  InappifySdkSnapshot snapshot = const InappifySdkSnapshot(
    accessToken: null,
    apiKey: 'public-web-key',
    storeInfo: 'web',
  );

  @override
  Future<InappifyBackendCapabilities> getCapabilities() async {
    return InappifyBackendCapabilities(
      backendKind: InappifyBackendKind.webJavaScript,
      protocolVersion: InappifyBackendCapabilities.currentProtocolVersion,
      ownsSession: true,
      supportedOperations: Set<InappifyOperation>.of(InappifyOperation.values),
    );
  }

  @override
  Future<InappifySdkResult<void>> configure(
    InappifyConfigureRequest request,
  ) async {
    return InappifySdkResult<void>.success(snapshot: snapshot);
  }

  @override
  Future<InappifySdkResult<String>> getPendingCheckoutId() async {
    pendingCheckoutReadCount += 1;
    return InappifySdkResult<String>.success(
      data: pendingCheckoutId,
      snapshot: snapshot,
    );
  }

  @override
  Future<InappifySdkResult<InappifyCheckoutResult>> handlePaymentReturn(
    InappifyPaymentReturnRequest request,
  ) async {
    paymentReturnRequests.add(request);
    return InappifySdkResult<InappifyCheckoutResult>.success(
      data: const InappifyCheckoutResult(
        checkout: InappifyCheckout(
          id: 'checkout-from-session-storage',
          status: 'Paid',
        ),
        nextAction: InappifyCheckoutNextAction(type: 'none'),
      ),
      snapshot: snapshot,
    );
  }

  @override
  Future<InappifySdkResult<PurchaseResult>> purchase(
    InappifyPurchaseRequest request,
  ) async {
    purchaseRequests.add(request);
    return InappifySdkResult<PurchaseResult>.failure(
      const InappifyFailure(
        code: InappifyFailureCode.network,
        message: 'Synthetic Web network failure.',
      ),
      snapshot: snapshot,
    );
  }

  @override
  Future<InappifySdkResult<InappifyCheckoutResult>> createCheckout(
    InappifyPurchaseRequest request,
  ) async {
    checkoutRequests.add(request);
    return InappifySdkResult<InappifyCheckoutResult>.failure(
      const InappifyFailure(
        code: InappifyFailureCode.network,
        message: 'Synthetic Web network failure.',
      ),
      snapshot: snapshot,
    );
  }
}
