import 'package:inappify_sdk/src/logging/sdk_logger.dart';
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:inappify_sdk/inappify_sdk_platform_interface.dart'
    show InappifySdkPlatform;
import 'package:inappify_sdk/models/attribute.dart';
import 'package:inappify_sdk/models/mobile_v2.dart';
import 'package:inappify_sdk/models/authentication_result.dart';
import 'package:inappify_sdk/models/captcha_challenge.dart';
import 'package:inappify_sdk/models/checkout_result.dart';
import 'package:inappify_sdk/models/customer_info.dart';
import 'package:inappify_sdk/models/inappify_configuration.dart';
import 'package:inappify_sdk/models/offering_model.dart';
import 'package:inappify_sdk/models/offerings_model.dart';
import 'package:inappify_sdk/models/otp_challenge.dart';
import 'package:inappify_sdk/models/purchase_result.dart';
import 'package:inappify_sdk/models/validate_discount_code_data.dart';
import 'package:inappify_sdk/request_cancellation.dart';
import 'package:inappify_sdk/src/application/inappify_sdk_state.dart';
import 'package:inappify_sdk/src/platform/contracts/backend_capabilities.dart';
import 'package:inappify_sdk/src/platform/contracts/platform_event.dart';
import 'package:inappify_sdk/src/platform/contracts/sdk_failure.dart';
import 'package:inappify_sdk/src/platform/contracts/sdk_requests.dart';
import 'package:inappify_sdk/src/platform/contracts/sdk_result.dart';

/// Coordinates backend selection, state mirroring, and legacy error semantics.
///
/// The platform candidate is accepted only when it can own the complete SDK
/// lifecycle. Otherwise all operations use [fallbackPlatform]. Selection is
/// process-stable so one session can never mix Dart, JavaScript, and native
/// authentication or persistence state.
class InappifyCoordinator {
  InappifyCoordinator({required this.fallbackPlatform, this.goPlatformFactory});

  final InappifySdkPlatform fallbackPlatform;

  /// Only the mobile composition root supplies an iOS Dart Go implementation.
  final InappifySdkPlatform? Function()? goPlatformFactory;
  final InappifySdkState state = InappifySdkState();
  final StreamController<InappifyPlatformEvent> _events =
      StreamController<InappifyPlatformEvent>.broadcast(sync: true);

  /// Ordered public event stream emitted by the selected backend.
  Stream<InappifyPlatformEvent> get events => _events.stream;

  InappifySdkPlatform? _selectedPlatform;
  Future<InappifySdkPlatform>? _selectionFuture;
  StreamSubscription<InappifyPlatformEvent>? _eventSubscription;
  StreamSubscription<InappifyHttpTrace>? _httpSubscription;
  InappifyMobileProtocol? _mobileProtocol;
  InappifyBackendCapabilities? _selectedCapabilities;
  late final StreamController<InappifyHttpTrace> _httpController =
      StreamController<InappifyHttpTrace>.broadcast(
        onListen: _attachHttpDiagnostics,
        onCancel: () {
          final subscription = _httpSubscription;
          _httpSubscription = null;
          if (subscription != null) unawaited(subscription.cancel());
        },
      );
  Stream<InappifyHttpTrace> get httpTraces => _httpController.stream;

  void _attachHttpDiagnostics() {
    if (!_httpController.hasListener ||
        _httpSubscription != null ||
        _selectedPlatform == null ||
        _selectedCapabilities?.backendKind ==
            InappifyBackendKind.webJavaScript) {
      return;
    }
    _httpSubscription = _selectedPlatform!.httpTraces.listen(
      _httpController.add,
      onError: (Object error, StackTrace stack) {
        // Do not leak native exception messages or disrupt lifecycle operations.
        SdkLogger.debug(
          'Inappify HTTP diagnostics unavailable: ${error.runtimeType}',
        );
      },
    );
  }

  final Map<Object, Future<InappifySdkResult<void>>> _configureOperations =
      <Object, Future<InappifySdkResult<void>>>{};
  Future<void> _operationTail = Future<void>.value();

  /// Configures the selected backend.
  ///
  /// Concurrent calls with the same input share one Future. Calls with
  /// different identities are serialized so a stale response cannot overwrite
  /// the newer customer's mirrored state.
  Future<InappifySdkResult<void>> configure(InappifyConfigureRequest request) {
    final fingerprint = (
      apiKey: request.apiKey,
      appUserIdentifier: request.appUserIdentifier,
      market: request.market,
      marketKey: request.marketKey,
      country: request.country,
      appVersion: request.appVersion,
      mobileProtocol: request.mobileProtocol,
      enableSubscriptionRecoveryWithoutPayload:
          request.enableSubscriptionRecoveryWithoutPayload,
    );

    final existing = _configureOperations[fingerprint];
    if (existing != null) return existing;

    final operation = _run<void>(
      (platform) {
        if (_mobileProtocol != null &&
            _mobileProtocol != request.mobileProtocol) {
          return Future.value(
            _mobileFailure<void>(
              'configure',
              'Mobile protocol is fixed for this process. Restart to switch protocols.',
            ),
          );
        }
        if (_selectedCapabilities?.backendKind !=
                InappifyBackendKind.webJavaScript &&
            request.mobileProtocol == InappifyMobileProtocol.goV2 &&
            !(_selectedCapabilities?.supportedOperations.contains(
                  InappifyOperation.goV2,
                ) ??
                false)) {
          return Future.value(
            _mobileFailure<void>(
              'configure',
              'This backend does not support Go V2. Update the native adapter or use iOS.',
            ),
          );
        }
        _mobileProtocol = request.mobileProtocol;
        return platform.configure(request);
      },
      operationName: 'configure',
      selectionProtocol: request.mobileProtocol,
    );
    _configureOperations[fingerprint] = operation;
    unawaited(
      operation.whenComplete(() {
        if (identical(_configureOperations[fingerprint], operation)) {
          _configureOperations.remove(fingerprint);
        }
      }),
    );
    return operation;
  }

  Future<InappifySdkResult<void>> login(InappifyLoginRequest request) {
    return _run<void>(
      (platform) => platform.login(request),
      operationName: 'login',
    );
  }

  Future<InappifySdkResult<bool>> restoreCachedSession(
    InappifyConfigureRequest request,
  ) => _run<bool>(
    (platform) async {
      if (kIsWeb ||
          (_mobileProtocol != null &&
              _mobileProtocol != request.mobileProtocol)) {
        return _mobileFailure<bool>(
          'restoreCachedSession',
          'Cache-only restore is unavailable for this platform.',
        );
      }
      _mobileProtocol = request.mobileProtocol;
      return platform.restoreCachedSession(request);
    },
    operationName: 'restoreCachedSession',
    selectionProtocol: request.mobileProtocol,
  );

  Future<InappifySdkResult<InappifyAuthenticationResult>>
  exchangeIdentityTicket(InappifyIdentityTicketRequest request) {
    return _run<InappifyAuthenticationResult>(
      (platform) => platform.exchangeIdentityTicket(request),
      operationName: 'exchangeIdentityTicket',
    );
  }

  Future<InappifySdkResult<InappifyOtpChallenge>> requestOtp(
    InappifyOtpRequest request,
  ) {
    return _run<InappifyOtpChallenge>(
      (platform) => platform.requestOtp(request),
      operationName: 'requestOtp',
    );
  }

  Future<InappifySdkResult<InappifyCaptchaChallenge>> createOtpCaptcha(
    InappifyNetworkRequest request,
  ) {
    return _run<InappifyCaptchaChallenge>(
      (platform) => platform.createOtpCaptcha(request),
      operationName: 'createOtpCaptcha',
    );
  }

  Future<InappifySdkResult<InappifyAuthenticationResult>> verifyOtp(
    InappifyOtpVerificationRequest request,
  ) {
    return _run<InappifyAuthenticationResult>(
      (platform) => platform.verifyOtp(request),
      operationName: 'verifyOtp',
    );
  }

  Future<InappifySdkResult<void>> logout({
    InappifyRequestCancellation? cancellation,
  }) {
    return _run<void>(
      (platform) => platform.logoutWithRequest(
        InappifyNetworkRequest(cancellation: cancellation),
      ),
      operationName: 'logout',
    );
  }

  Future<InappifySdkResult<PurchaseResult>> purchase(
    InappifyPurchaseRequest request,
  ) {
    return _run<PurchaseResult>(
      (platform) => platform.purchase(request),
      operationName: 'purchase',
    );
  }

  Future<InappifySdkResult<InappifyCheckoutResult>> createCheckout(
    InappifyPurchaseRequest request,
  ) {
    return _run<InappifyCheckoutResult>(
      (platform) => platform.createCheckout(request),
      operationName: 'createCheckout',
    );
  }

  Future<InappifySdkResult<InappifyCheckoutResult>> getCheckoutStatus(
    InappifyCheckoutStatusRequest request,
  ) {
    return _run<InappifyCheckoutResult>(
      (platform) => platform.getCheckoutStatus(request),
      operationName: 'getCheckoutStatus',
    );
  }

  Future<InappifySdkResult<ValidateDiscountCodeData>> validateDiscountCode(
    InappifyDiscountCodeRequest request,
  ) {
    return _run<ValidateDiscountCodeData>(
      (platform) => platform.validateDiscountCode(request),
      operationName: 'validateDiscountCode',
    );
  }

  Future<InappifySdkResult<CustomerInfo>> getCustomerInfo({
    bool force = false,
    InappifyCacheFetchPolicy? fetchPolicy,
    InappifyRequestCancellation? cancellation,
  }) {
    return _run<CustomerInfo>(
      (platform) => platform.getCustomerInfo(
        InappifyRefreshRequest(
          force: force,
          cancellation: cancellation,
          fetchPolicy: fetchPolicy,
        ),
      ),
      operationName: 'getCustomerInfo',
    );
  }

  Future<InappifySdkResult<InappifyConfiguration>> getConfiguration() {
    return _run<InappifyConfiguration>(
      (platform) => platform.getConfiguration(),
      operationName: 'getConfiguration',
    );
  }

  Future<InappifySdkResult<OfferingsModel>> getOfferings({
    bool force = false,
    InappifyRequestCancellation? cancellation,
  }) {
    return _run<OfferingsModel>(
      (platform) => platform.getOfferings(
        InappifyRefreshRequest(force: force, cancellation: cancellation),
      ),
      operationName: 'getOfferings',
    );
  }

  Future<InappifySdkResult<OfferingModel>> getOffering(String identifier) =>
      _run(
        (platform) => platform.getOffering(identifier),
        operationName: 'getOffering',
      );
  Future<InappifySdkResult<OfferingsModel>>
  syncAttributesAndOfferingsIfNeeded() => _run(
    (platform) => platform.syncAttributesAndOfferingsIfNeeded(),
    operationName: 'syncAttributesAndOfferingsIfNeeded',
  );
  Future<InappifySdkResult<bool>> handleDeepLink(String url) =>
      _runMobile('handleDeepLink', (platform) => platform.handleDeepLink(url));
  Future<InappifySdkResult<void>> setConsumableDeliveryHandler(
    InappifyConsumableDeliveryHandler? handler,
  ) => _runMobile(
    'setConsumableDeliveryHandler',
    (platform) => platform.setConsumableDeliveryHandler(handler),
  );

  Future<InappifySdkResult<void>> setTargetingContext(
    InappifyTargetingContextRequest request,
  ) {
    return _run<void>(
      (platform) => platform.setTargetingContext(request),
      operationName: 'setTargetingContext',
    );
  }

  Future<InappifySdkResult<OfferingModel>> getCurrentOffering(
    InappifyCurrentOfferingRequest request,
  ) {
    return _run<OfferingModel>(
      (platform) => platform.getCurrentOffering(request),
      operationName: 'getCurrentOffering',
    );
  }

  Future<InappifySdkResult<bool>> checkEntitlement(
    InappifyEntitlementCheckRequest request,
  ) {
    return _run<bool>(
      (platform) => platform.checkEntitlement(request),
      operationName: 'checkEntitlement',
    );
  }

  Future<InappifySdkResult<List<Attribute>>> setAttributes(
    InappifyAttributesRequest request,
  ) {
    return _run<List<Attribute>>(
      (platform) => platform.setAttributes(request),
      operationName: 'setAttributes',
    );
  }

  Future<InappifySdkResult<List<Attribute>>> deleteAttributes(
    InappifyDeleteAttributesRequest request,
  ) {
    return _run<List<Attribute>>(
      (platform) => platform.deleteAttributes(request),
      operationName: 'deleteAttributes',
    );
  }

  Future<InappifySdkResult<void>> setReservedAttribute(
    InappifyReservedAttributeRequest request,
  ) {
    return _run<void>(
      (platform) => platform.setReservedAttribute(request),
      operationName: 'setReservedAttribute',
    );
  }

  Future<InappifySdkResult<List<Attribute>>> syncAttributes() {
    return _run<List<Attribute>>(
      (platform) => platform.syncAttributes(),
      operationName: 'syncAttributes',
    );
  }

  Future<InappifySdkResult<List<Attribute>>> syncAttributeValues(
    InappifyAttributesRequest request,
  ) {
    return _run<List<Attribute>>(
      (platform) => platform.syncAttributeValues(request),
      operationName: 'syncAttributeValues',
    );
  }

  Future<InappifySdkResult<bool>> canSetReservedAttribute(
    InappifyReservedAttributeCapabilityRequest request,
  ) {
    return _run<bool>(
      (platform) => platform.canSetReservedAttribute(request),
      operationName: 'canSetReservedAttribute',
    );
  }

  Future<InappifySdkResult<InappifyCheckoutResult>> handlePaymentReturn(
    InappifyPaymentReturnRequest request,
  ) {
    return _run<InappifyCheckoutResult>(
      (platform) => platform.handlePaymentReturn(request),
      operationName: 'handlePaymentReturn',
    );
  }

  Future<InappifySdkResult<String>> getPendingCheckoutId() {
    return _run<String>(
      (platform) => platform.getPendingCheckoutId(),
      operationName: 'getPendingCheckoutId',
    );
  }

  Future<InappifySdkResult<T>> _run<T>(
    Future<InappifySdkResult<T>> Function(InappifySdkPlatform platform)
    operation, {
    required String operationName,
    InappifyMobileProtocol? selectionProtocol,
  }) {
    final scheduled = _operationTail.then(
      (_) => _execute<T>(
        operation,
        operationName: operationName,
        selectionProtocol: selectionProtocol,
      ),
    );
    _operationTail = scheduled.then<void>((_) {}, onError: (_) {});
    return scheduled;
  }

  Future<InappifySdkResult<T>> _execute<T>(
    Future<InappifySdkResult<T>> Function(InappifySdkPlatform platform)
    operation, {
    required String operationName,
    InappifyMobileProtocol? selectionProtocol,
  }) async {
    try {
      final platform = await _selectPlatform(selectionProtocol);
      platform.synchronizeCompatibilityState(state.snapshot);
      final result = await operation(platform);
      if (result.isSuccess && result.snapshot == null) {
        return InappifySdkResult<T>.failure(
          const InappifyFailure(
            code: InappifyFailureCode.malformedResponse,
            message: 'SDK backend success response is missing snapshot.',
          ),
          snapshot: state.snapshot,
        );
      }
      final snapshot = result.snapshot;
      if (snapshot != null &&
          !(operationName == 'restoreCachedSession' &&
              (!result.isSuccess || result.data != true))) {
        state.apply(snapshot);
      }
      return result;
    } catch (error) {
      SdkLogger.error('Inappify $operationName failed: ${error.runtimeType}');
      return InappifySdkResult<T>.failure(
        InappifyFailure(
          code: InappifyFailureCode.unknown,
          message: 'Inappify $operationName failed.',
          details: <String, Object?>{'operation': operationName},
        ),
        snapshot: state.snapshot,
      );
    }
  }

  Future<InappifySdkPlatform> _selectPlatform([
    InappifyMobileProtocol? protocol,
  ]) async {
    final selected = _selectedPlatform;
    // Reading before Configure must not accidentally choose the mobile protocol.
    // Only a not-yet-configured fallback can be replaced; configured owners never mix.
    if (selected != null &&
        _mobileProtocol == null &&
        protocol == InappifyMobileProtocol.goV2 &&
        identical(selected, fallbackPlatform) &&
        goPlatformFactory != null) {
      await _eventSubscription?.cancel();
      await _httpSubscription?.cancel();
      _eventSubscription = null;
      _httpSubscription = null;
      _selectedPlatform = null;
      _selectionFuture = null;
    } else if (selected != null) {
      return selected;
    }
    return _selectionFuture ??= _resolvePlatform(
      protocol ?? InappifyMobileProtocol.goV2,
    );
  }

  Future<InappifySdkPlatform> _resolvePlatform(
    InappifyMobileProtocol protocol,
  ) async {
    final candidate = InappifySdkPlatform.instance;
    final fallback = protocol == InappifyMobileProtocol.goV2
        ? goPlatformFactory?.call() ?? fallbackPlatform
        : fallbackPlatform;
    InappifySdkPlatform selected = fallback;
    InappifyBackendCapabilities? candidateCapabilities;
    StreamSubscription<InappifyPlatformEvent>? subscription;

    try {
      final capabilities = await candidate.getCapabilities();
      candidateCapabilities = capabilities;
      if (capabilities.supportsCompleteLifecycle) {
        subscription = candidate.events.listen(
          (event) => _handleEvent(event, candidate),
          onError: _handleEventError,
        );
        selected = candidate;
      }
    } catch (error) {
      SdkLogger.error(
        'Inappify platform selection failed: ${error.runtimeType}',
      );
    }

    if (identical(selected, fallback)) {
      try {
        subscription = fallback.events.listen(
          (event) => _handleEvent(event, fallback),
          onError: _handleEventError,
        );
      } catch (error) {
        SdkLogger.debug(
          'Inappify fallback event stream failed: ${error.runtimeType}',
        );
      }
    }
    if (kDebugMode) {
      final candidateKind =
          candidateCapabilities?.backendKind.name ?? 'unavailable';
      final selectedKind = identical(selected, candidate)
          ? candidateKind
          : 'dartFallback';
      SdkLogger.debug(
        'Inappify backend selected: $selectedKind '
        '(candidate=$candidateKind, '
        'complete=${candidateCapabilities?.supportsCompleteLifecycle ?? false}).',
      );
    }
    _selectedPlatform = selected;
    _selectedCapabilities = identical(selected, candidate)
        ? candidateCapabilities
        : await selected.getCapabilities();
    _eventSubscription = subscription;
    _attachHttpDiagnostics();
    return selected;
  }

  void _handleEventError(Object error, StackTrace stackTrace) {
    SdkLogger.error('Inappify platform event failed: ${error.runtimeType}');
  }

  void _handleEvent(InappifyPlatformEvent event, InappifySdkPlatform source) {
    final barrier = event.snapshot;
    // A Go lifecycle attempt revokes local access before its HTTP finishes.
    // Do not queue this restrictive snapshot behind that same network operation.
    // Positive snapshots, V1 and Web keep their existing serialized ordering.
    if (barrier != null &&
        identical(source, _selectedPlatform) &&
        _mobileProtocol == InappifyMobileProtocol.goV2 &&
        barrier.mobileProtocol == InappifyMobileProtocol.goV2 &&
        barrier.isConfigured == false &&
        barrier.isAuthenticated == false &&
        barrier.customerInfo == null &&
        barrier.offerings == null &&
        barrier.appUserIdentifier == null &&
        barrier.revision != null &&
        (state.revision == null || barrier.revision! >= state.revision!)) {
      state.apply(barrier);
      _events.add(event);
      return;
    }
    _operationTail = _operationTail.then<void>((_) {
      if (!identical(source, _selectedPlatform)) return;
      final snapshot = event.snapshot;
      // A queued event from an earlier operation must not resurrect a previous
      // customer after a newer login/logout response. Web has no mobile revision.
      final incoming = snapshot?.revision;
      final current = state.revision;
      if (incoming != null && current != null && incoming < current) return;
      if (snapshot != null) state.apply(snapshot);
      _events.add(event);
    }, onError: (_) {});
  }

  /// Resets process-stable backend selection for isolated tests only.
  @visibleForTesting
  Future<void> resetForTesting() async {
    await _eventSubscription?.cancel();
    _eventSubscription = null;
    _selectedPlatform = null;
    _selectionFuture = null;
    await _httpSubscription?.cancel();
    _httpSubscription = null;
    _selectedCapabilities = null;
    _mobileProtocol = null;
    _configureOperations.clear();
    _operationTail = Future<void>.value();
  }

  InappifySdkResult<T> _mobileFailure<T>(String operation, String message) =>
      InappifySdkResult.failure(
        InappifyFailure(
          code: InappifyFailureCode.unsupportedOperation,
          message: message,
          details: {'operation': operation},
        ),
        snapshot: state.snapshot,
      );

  Future<InappifySdkResult<T>> _runMobile<T>(
    String name,
    Future<InappifySdkResult<T>> Function(InappifySdkPlatform) operation,
  ) => _run((platform) {
    if (kIsWeb ||
        _selectedCapabilities?.backendKind ==
            InappifyBackendKind.webJavaScript) {
      return Future.value(
        _mobileFailure<T>(name, 'This operation is mobile-only.'),
      );
    }
    return operation(platform);
  }, operationName: name);

  Future<InappifySdkResult<List<PurchaseResult>>> syncStorePurchases() =>
      _runMobile(
        'syncStorePurchases',
        (platform) => platform.syncStorePurchases(),
      );
  Future<InappifySdkResult<InappifyRestoreResult>> restoreStorePurchases() =>
      _runMobile(
        'restoreStorePurchases',
        (platform) => platform.restoreStorePurchases(),
      );
  Future<InappifySdkResult<InappifyConsumableSyncResult>>
  syncPendingConsumables() => _runMobile(
    'syncPendingConsumables',
    (platform) => platform.syncPendingConsumables(),
  );
  Future<InappifySdkResult<PurchaseResult>> confirmDelivery(int deliveryId) =>
      _runMobile(
        'confirmDelivery',
        (platform) => platform.confirmDelivery(deliveryId),
      );
  Future<InappifySdkResult<CustomerInfo>> customerInfoWithPolicy(
    InappifyFetchPolicy policy,
  ) => _runMobile(
    'customerInfoWithPolicy',
    (platform) => platform.customerInfoWithPolicy(policy),
  );
  Future<InappifySdkResult<OfferingsModel>> offeringsWithPolicy(
    InappifyFetchPolicy policy,
  ) => _runMobile(
    'offeringsWithPolicy',
    (platform) => platform.offeringsWithPolicy(policy),
  );
  Future<InappifySdkResult<void>> queueAttributes(
    Map<String, String?> values,
  ) => _runMobile(
    'queueAttributes',
    (platform) => platform.queueAttributes(Map.unmodifiable(values)),
  );
  Future<InappifySdkResult<void>> flushAttributes() =>
      _runMobile('flushAttributes', (platform) => platform.flushAttributes());
  Future<InappifySdkResult<void>> setNetworkEnabled(bool enabled) => _runMobile(
    'setNetworkEnabled',
    (platform) => platform.setNetworkEnabled(enabled),
  );
  Future<InappifySdkResult<bool>> isPaymentUrlAllowed(String url) => _runMobile(
    'isPaymentUrlAllowed',
    (platform) => platform.isPaymentUrlAllowed(url),
  );
}
