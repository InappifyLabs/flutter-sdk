import 'package:flutter/foundation.dart';

/// Identifies the implementation that owns an Inappify session.
enum InappifyBackendKind { dart, webJavaScript, methodChannel, unknown }

/// Semantic operations that must be implemented by a full SDK backend.
enum InappifyOperation {
  setLogLevel,
  setLogHandler,
  getOffering,
  syncAttributesAndOfferingsIfNeeded,
  handleDeepLink,
  setConsumableDeliveryHandler,
  configure,
  login,
  logout,
  purchase,
  validateDiscountCode,
  getCustomerInfo,
  getOfferings,
  setAttributes,
  setReservedAttribute,
  syncAttributes,
  exchangeIdentityTicket,
  requestOtp,
  createOtpCaptcha,
  verifyOtp,
  setTargetingContext,
  getCurrentOffering,
  checkEntitlement,
  deleteAttributes,
  syncAttributeValues,
  canSetReservedAttribute,
  handlePaymentReturn,
  getPendingCheckoutId,
  createCheckout,
  getCheckoutStatus,
  getConfiguration,
  // Additive mobile capabilities; never part of the existing required sets.
  restoreCachedSession,
  goV2,
  syncStorePurchases,
  restoreStorePurchases,
  syncPendingConsumables,
  confirmDelivery,
  customerInfoWithPolicy,
  offeringsWithPolicy,
  queueAttributes,
  flushAttributes,
  setNetworkEnabled,
  isPaymentUrlAllowed,
}

/// Capability information returned before an SDK backend is selected.
///
/// A backend is selected once, during the first configuration attempt, and
/// remains the sole owner of session and persistence state. Mixing operations
/// from different backends in one session is deliberately unsupported because
/// it can split token, customer, and offering state across implementations.
@immutable
class InappifyBackendCapabilities {
  const InappifyBackendCapabilities({
    required this.backendKind,
    required this.protocolVersion,
    required this.ownsSession,
    required this.supportedOperations,
    this.sdkVersion,
  });

  /// Current Dart/native bridge protocol supported by this package.
  static const int currentProtocolVersion = 1;

  static const Set<InappifyOperation> _sharedRequiredOperations =
      <InappifyOperation>{
        InappifyOperation.configure,
        InappifyOperation.logout,
        InappifyOperation.purchase,
        InappifyOperation.validateDiscountCode,
        InappifyOperation.getCustomerInfo,
        InappifyOperation.getOfferings,
        InappifyOperation.setAttributes,
        InappifyOperation.setReservedAttribute,
        InappifyOperation.syncAttributes,
      };

  static const Set<InappifyOperation> _dartRequiredOperations =
      <InappifyOperation>{
        ..._sharedRequiredOperations,
        InappifyOperation.login,
      };

  static const Set<InappifyOperation> _nativeRequiredOperations =
      <InappifyOperation>{
        InappifyOperation.configure,
        InappifyOperation.login,
        InappifyOperation.logout,
        InappifyOperation.purchase,
        InappifyOperation.validateDiscountCode,
        InappifyOperation.getCustomerInfo,
        InappifyOperation.getOfferings,
        InappifyOperation.setAttributes,
        InappifyOperation.setReservedAttribute,
        InappifyOperation.getCurrentOffering,
        InappifyOperation.getOffering,
        InappifyOperation.syncAttributesAndOfferingsIfNeeded,
        InappifyOperation.setConsumableDeliveryHandler,
        InappifyOperation.handleDeepLink,
        InappifyOperation.canSetReservedAttribute,
      };

  static const Set<InappifyOperation> _webRequiredOperations =
      <InappifyOperation>{
        ..._sharedRequiredOperations,
        InappifyOperation.exchangeIdentityTicket,
        InappifyOperation.requestOtp,
        InappifyOperation.createOtpCaptcha,
        InappifyOperation.verifyOtp,
        InappifyOperation.setTargetingContext,
        InappifyOperation.getCurrentOffering,
        InappifyOperation.checkEntitlement,
        InappifyOperation.deleteAttributes,
        InappifyOperation.syncAttributeValues,
        InappifyOperation.canSetReservedAttribute,
        InappifyOperation.handlePaymentReturn,
        InappifyOperation.getPendingCheckoutId,
        InappifyOperation.createCheckout,
        InappifyOperation.getCheckoutStatus,
        InappifyOperation.getConfiguration,
      };

  /// Backend type selected by the adapter.
  final InappifyBackendKind backendKind;

  /// Wire protocol version used by the adapter.
  final int protocolVersion;

  /// Whether this implementation owns authentication and persistence state.
  final bool ownsSession;

  /// Operations implemented by this backend.
  final Set<InappifyOperation> supportedOperations;

  /// Optional implementation SDK version for diagnostics.
  final String? sdkVersion;

  /// Whether the backend can safely own an entire Inappify session.
  bool get supportsCompleteLifecycle {
    final requiredOperations = switch (backendKind) {
      InappifyBackendKind.webJavaScript => _webRequiredOperations,
      InappifyBackendKind.methodChannel => _nativeRequiredOperations,
      _ => _dartRequiredOperations,
    };
    return ownsSession &&
        protocolVersion == currentProtocolVersion &&
        supportedOperations.containsAll(requiredOperations);
  }

  /// Capability response used by stubs and unavailable bridges.
  factory InappifyBackendCapabilities.unavailable({
    InappifyBackendKind backendKind = InappifyBackendKind.unknown,
  }) {
    return InappifyBackendCapabilities(
      backendKind: backendKind,
      protocolVersion: currentProtocolVersion,
      ownsSession: false,
      supportedOperations: const <InappifyOperation>{},
    );
  }

  /// Capability response for the current Dart implementation.
  factory InappifyBackendCapabilities.legacyDart() {
    return const InappifyBackendCapabilities(
      backendKind: InappifyBackendKind.dart,
      protocolVersion: currentProtocolVersion,
      ownsSession: true,
      supportedOperations: _dartRequiredOperations,
    );
  }

  /// Decodes a capability map returned by JavaScript or MethodChannel.
  factory InappifyBackendCapabilities.fromMap(Map<String, dynamic> map) {
    final backendName = map['backendKind'];
    final protocolVersion = _exactInteger(map['protocolVersion']);
    final ownsSession = map['ownsSession'];
    final operationsValue = map['supportedOperations'];
    final sdkVersion = map['sdkVersion'];
    if (backendName is! String ||
        protocolVersion == null ||
        ownsSession is! bool ||
        (sdkVersion != null && sdkVersion is! String)) {
      throw const FormatException(
        'Backend capability fields have invalid types.',
      );
    }
    final operations = <InappifyOperation>{};

    if (operationsValue is List) {
      for (final value in operationsValue) {
        if (value is! String) {
          throw const FormatException(
            'Backend operation names must be strings.',
          );
        }
        final operation = _operationFromWireName(value);
        if (operation != null) operations.add(operation);
      }
    } else if (operationsValue is Map) {
      for (final entry in operationsValue.entries) {
        if (entry.value == true || entry.value == 1) {
          final operation = _operationFromWireName(entry.key.toString());
          if (operation != null) operations.add(operation);
        }
      }
    } else {
      throw const FormatException(
        'Backend supportedOperations must be a list or map.',
      );
    }

    return InappifyBackendCapabilities(
      backendKind: switch (backendName) {
        'dart' => InappifyBackendKind.dart,
        'webJavaScript' => InappifyBackendKind.webJavaScript,
        'methodChannel' => InappifyBackendKind.methodChannel,
        _ => InappifyBackendKind.unknown,
      },
      protocolVersion: protocolVersion,
      ownsSession: ownsSession,
      supportedOperations: Set<InappifyOperation>.unmodifiable(operations),
      sdkVersion: sdkVersion as String?,
    );
  }

  static InappifyOperation? _operationFromWireName(String? name) {
    return switch (name) {
      'getOffering' => InappifyOperation.getOffering,
      'syncAttributesAndOfferingsIfNeeded' =>
        InappifyOperation.syncAttributesAndOfferingsIfNeeded,
      'setConsumableDeliveryHandler' =>
        InappifyOperation.setConsumableDeliveryHandler,
      'handleDeepLink' => InappifyOperation.handleDeepLink,
      'configure' => InappifyOperation.configure,
      'login' => InappifyOperation.login,
      'logout' => InappifyOperation.logout,
      'purchase' => InappifyOperation.purchase,
      'validateDiscountCode' => InappifyOperation.validateDiscountCode,
      'getCustomerInfo' => InappifyOperation.getCustomerInfo,
      'getOfferings' => InappifyOperation.getOfferings,
      'setAttributes' => InappifyOperation.setAttributes,
      'setReservedAttribute' => InappifyOperation.setReservedAttribute,
      'syncAttributes' => InappifyOperation.syncAttributes,
      'exchangeIdentityTicket' => InappifyOperation.exchangeIdentityTicket,
      'requestOtp' => InappifyOperation.requestOtp,
      'createOtpCaptcha' => InappifyOperation.createOtpCaptcha,
      'verifyOtp' => InappifyOperation.verifyOtp,
      'setTargetingContext' => InappifyOperation.setTargetingContext,
      'getCurrentOffering' => InappifyOperation.getCurrentOffering,
      'checkEntitlement' => InappifyOperation.checkEntitlement,
      'deleteAttributes' => InappifyOperation.deleteAttributes,
      'syncAttributeValues' => InappifyOperation.syncAttributeValues,
      'canSetReservedAttribute' => InappifyOperation.canSetReservedAttribute,
      'handlePaymentReturn' => InappifyOperation.handlePaymentReturn,
      'getPendingCheckoutId' => InappifyOperation.getPendingCheckoutId,
      'createCheckout' => InappifyOperation.createCheckout,
      'getCheckoutStatus' => InappifyOperation.getCheckoutStatus,
      'getConfiguration' => InappifyOperation.getConfiguration,
      'goV2' => InappifyOperation.goV2,
      'setLogLevel' => InappifyOperation.setLogLevel,
      'setLogHandler' => InappifyOperation.setLogHandler,
      'syncStorePurchases' => InappifyOperation.syncStorePurchases,
      'restoreStorePurchases' => InappifyOperation.restoreStorePurchases,
      'syncPendingConsumables' => InappifyOperation.syncPendingConsumables,
      'confirmDelivery' => InappifyOperation.confirmDelivery,
      'customerInfoWithPolicy' => InappifyOperation.customerInfoWithPolicy,
      'offeringsWithPolicy' => InappifyOperation.offeringsWithPolicy,
      'queueAttributes' => InappifyOperation.queueAttributes,
      'flushAttributes' => InappifyOperation.flushAttributes,
      'setNetworkEnabled' => InappifyOperation.setNetworkEnabled,
      'isPaymentUrlAllowed' => InappifyOperation.isPaymentUrlAllowed,
      _ => null,
    };
  }

  static int? _exactInteger(Object? value) {
    if (value is! num || !value.isFinite || value != value.toInt()) {
      return null;
    }
    return value.toInt();
  }
}
