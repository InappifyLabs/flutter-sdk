import 'package:flutter_test/flutter_test.dart';
import 'package:inappify_sdk/src/platform/contracts/backend_capabilities.dart';

void main() {
  const nativeLifecycleOperations = <InappifyOperation>{
    InappifyOperation.configure,
    InappifyOperation.login,
    InappifyOperation.logout,
    InappifyOperation.purchase,
    InappifyOperation.validateDiscountCode,
    InappifyOperation.getCustomerInfo,
    InappifyOperation.getOfferings,
    InappifyOperation.setAttributes,
    InappifyOperation.setReservedAttribute,
    InappifyOperation.syncAttributes,
    InappifyOperation.setTargetingContext,
    InappifyOperation.getCurrentOffering,
    InappifyOperation.checkEntitlement,
    InappifyOperation.deleteAttributes,
    InappifyOperation.syncAttributeValues,
    InappifyOperation.canSetReservedAttribute,
  };

  test('method channel requires the complete Android lifecycle surface', () {
    final completeCapabilities = InappifyBackendCapabilities(
      backendKind: InappifyBackendKind.methodChannel,
      protocolVersion: InappifyBackendCapabilities.currentProtocolVersion,
      ownsSession: true,
      supportedOperations: nativeLifecycleOperations,
    );

    expect(completeCapabilities.supportsCompleteLifecycle, isTrue);

    for (final missingOperation in nativeLifecycleOperations) {
      final partialCapabilities = InappifyBackendCapabilities(
        backendKind: InappifyBackendKind.methodChannel,
        protocolVersion: InappifyBackendCapabilities.currentProtocolVersion,
        ownsSession: true,
        supportedOperations: <InappifyOperation>{...nativeLifecycleOperations}
          ..remove(missingOperation),
      );

      expect(
        partialCapabilities.supportsCompleteLifecycle,
        isFalse,
        reason: '${missingOperation.name} must be advertised by Android.',
      );
    }
  });

  test('legacy Dart keeps its existing lifecycle profile', () {
    final capabilities = InappifyBackendCapabilities.legacyDart();

    expect(capabilities.supportsCompleteLifecycle, isTrue);
    expect(capabilities.supportedOperations, const <InappifyOperation>{
      InappifyOperation.configure,
      InappifyOperation.login,
      InappifyOperation.logout,
      InappifyOperation.purchase,
      InappifyOperation.validateDiscountCode,
      InappifyOperation.getCustomerInfo,
      InappifyOperation.getOfferings,
      InappifyOperation.setAttributes,
      InappifyOperation.setReservedAttribute,
      InappifyOperation.syncAttributes,
    });
  });
}
