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
import 'package:inappify_sdk/src/platform/contracts/app_version_info.dart';
import 'package:inappify_sdk/src/platform/contracts/backend_capabilities.dart';
import 'package:inappify_sdk/src/platform/contracts/platform_event.dart';
import 'package:inappify_sdk/src/platform/contracts/sdk_failure.dart';
import 'package:inappify_sdk/src/platform/contracts/sdk_requests.dart';
import 'package:inappify_sdk/src/platform/contracts/sdk_result.dart';
import 'package:inappify_sdk/src/platform/contracts/sdk_snapshot.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'inappify_sdk_method_channel.dart';

export 'package:inappify_sdk/src/platform/contracts/app_version_info.dart';
export 'package:inappify_sdk/src/platform/contracts/backend_capabilities.dart';
export 'package:inappify_sdk/src/platform/contracts/platform_event.dart';
export 'package:inappify_sdk/src/platform/contracts/sdk_failure.dart';
export 'package:inappify_sdk/src/platform/contracts/sdk_requests.dart';
export 'package:inappify_sdk/src/platform/contracts/sdk_result.dart';
export 'package:inappify_sdk/src/platform/contracts/sdk_snapshot.dart';
export 'package:inappify_sdk/session_state.dart';
export 'package:inappify_sdk/models/mobile_v2.dart';

/// Semantic platform boundary for the Inappify SDK.
///
/// Implementations own the complete session, including authentication and
/// persistence. The SDK selects exactly one complete implementation during
/// configuration and never falls back operation-by-operation. This invariant
/// prevents token, customer, and offering state from being split across Dart,
/// JavaScript, and native SDKs. Every successful semantic operation must
/// include a complete [InappifySdkSnapshot].
abstract class InappifySdkPlatform extends PlatformInterface {
  /// Creates an Inappify platform implementation.
  InappifySdkPlatform() : super(token: _token);

  static final Object _token = Object();

  static InappifySdkPlatform _instance = MethodChannelInappifySdk();

  /// Active platform candidate used during backend capability negotiation.
  static InappifySdkPlatform get instance => _instance;

  /// Platform-specific implementations should set this with their own
  /// platform-specific class that extends [InappifySdkPlatform] when
  /// they register themselves.
  static set instance(InappifySdkPlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  /// Reports whether this adapter can own a complete SDK session.
  ///
  /// The default implementation is intentionally unavailable so existing
  /// federated implementations continue to use the Dart backend until they
  /// explicitly implement the complete versioned contract.
  Future<InappifyBackendCapabilities> getCapabilities() async {
    return InappifyBackendCapabilities.unavailable();
  }

  /// Stream for redirect callbacks and out-of-band native SDK changes.
  Stream<InappifyPlatformEvent> get events =>
      const Stream<InappifyPlatformEvent>.empty();

  /// Mobile-only, filtered diagnostics; subscriptions opt in to tracing.
  Stream<InappifyHttpTrace> get httpTraces => const Stream.empty();

  Future<InappifySdkResult<List<PurchaseResult>>> syncStorePurchases() async =>
      _unsupported('syncStorePurchases');
  Future<InappifySdkResult<InappifyRestoreResult>>
  restoreStorePurchases() async => _unsupported('restoreStorePurchases');
  Future<InappifySdkResult<InappifyConsumableSyncResult>>
  syncPendingConsumables() async => _unsupported('syncPendingConsumables');

  /// Host must have durably granted this delivery once before calling.
  Future<InappifySdkResult<PurchaseResult>> confirmDelivery(
    int deliveryId,
  ) async => _unsupported('confirmDelivery');
  Future<InappifySdkResult<CustomerInfo>> customerInfoWithPolicy(
    InappifyFetchPolicy policy,
  ) async => _unsupported('customerInfoWithPolicy');
  Future<InappifySdkResult<OfferingsModel>> offeringsWithPolicy(
    InappifyFetchPolicy policy,
  ) async => _unsupported('offeringsWithPolicy');
  Future<InappifySdkResult<OfferingsModel>>
  syncAttributesAndOfferingsIfNeeded() async =>
      _unsupported('syncAttributesAndOfferingsIfNeeded');
  Future<InappifySdkResult<OfferingModel>> getOffering(
    String identifier,
  ) async {
    final result = await getOfferings(const InappifyRefreshRequest());
    if (!result.isSuccess)
      return InappifySdkResult.failure(
        result.failure!,
        snapshot: result.snapshot,
      );
    return InappifySdkResult.success(
      data: result.data?.getOffering(identifier),
      snapshot: result.snapshot,
    );
  }

  Future<InappifySdkResult<bool>> handleDeepLink(String url) async =>
      _unsupported('handleDeepLink');
  Future<InappifySdkResult<void>> setConsumableDeliveryHandler(
    InappifyConsumableDeliveryHandler? handler,
  ) async => _unsupported('setConsumableDeliveryHandler');

  Future<InappifySdkResult<void>> queueAttributes(
    Map<String, String?> values,
  ) async => _unsupported('queueAttributes');
  Future<InappifySdkResult<void>> flushAttributes() async =>
      _unsupported('flushAttributes');
  Future<InappifySdkResult<void>> setNetworkEnabled(bool enabled) async =>
      _unsupported('setNetworkEnabled');
  Future<InappifySdkResult<bool>> isPaymentUrlAllowed(String url) async =>
      _unsupported('isPaymentUrlAllowed');

  /// Synchronizes legacy mutable façade fields before a Dart fallback call.
  ///
  /// Native and JavaScript implementations should normally ignore this hook;
  /// their own SDK remains the authoritative session owner.
  void synchronizeCompatibilityState(InappifySdkSnapshot snapshot) {}

  /// Returns a diagnostic description of the host platform.
  Future<String?> getPlatformVersion() {
    throw UnimplementedError('platformVersion() has not been implemented.');
  }

  /// Returns host application version information when available.
  Future<InappifyAppVersionInfo?> getAppVersionInfo() async => null;

  /// Reads a matching mobile session without network access. A false result is
  /// a cache miss, never permission to reuse a different customer's snapshot.
  Future<InappifySdkResult<bool>> restoreCachedSession(
    InappifyConfigureRequest request,
  ) async => _unsupported<bool>('restoreCachedSession');

  /// Configures the selected backend and returns its authoritative snapshot.
  Future<InappifySdkResult<void>> configure(
    InappifyConfigureRequest request,
  ) async {
    return _unsupported<void>('configure');
  }

  /// Changes the customer identity owned by the selected backend.
  Future<InappifySdkResult<void>> login(InappifyLoginRequest request) async {
    return _unsupported<void>('login');
  }

  /// Exchanges a short-lived, single-use Identity Ticket.
  ///
  /// The result intentionally excludes access and refresh tokens. Session
  /// credentials remain private to the implementation that owns the session.
  Future<InappifySdkResult<InappifyAuthenticationResult>>
  exchangeIdentityTicket(InappifyIdentityTicketRequest request) async {
    return _unsupported<InappifyAuthenticationResult>('exchangeIdentityTicket');
  }

  /// Creates an OTP authentication challenge.
  Future<InappifySdkResult<InappifyOtpChallenge>> requestOtp(
    InappifyOtpRequest request,
  ) async {
    return _unsupported<InappifyOtpChallenge>('requestOtp');
  }

  /// Creates an explicit CAPTCHA challenge for an OTP request.
  Future<InappifySdkResult<InappifyCaptchaChallenge>> createOtpCaptcha(
    InappifyNetworkRequest request,
  ) async {
    return _unsupported<InappifyCaptchaChallenge>('createOtpCaptcha');
  }

  /// Verifies an OTP challenge and updates the authoritative session.
  Future<InappifySdkResult<InappifyAuthenticationResult>> verifyOtp(
    InappifyOtpVerificationRequest request,
  ) async {
    return _unsupported<InappifyAuthenticationResult>('verifyOtp');
  }

  /// Ends the current customer session.
  Future<InappifySdkResult<void>> logout() async {
    return _unsupported<void>('logout');
  }

  /// Cancellation-aware logout used by browser backends.
  ///
  /// Existing adapters inherit the legacy [logout] behavior. Implementations
  /// that accept request cancellation may override this additive method.
  Future<InappifySdkResult<void>> logoutWithRequest(
    InappifyNetworkRequest request,
  ) {
    return logout();
  }

  /// Starts a purchase after configuration.
  ///
  /// Cancellation is a domain result and must not be reported as a transport
  /// exception. Implementations must not both navigate and return a redirect
  /// URL unless their documented integration contract explicitly requires it.
  Future<InappifySdkResult<PurchaseResult>> purchase(
    InappifyPurchaseRequest request,
  ) async {
    return _unsupported<PurchaseResult>('purchase');
  }

  /// Creates a checkout without allowing the backend to navigate the page.
  Future<InappifySdkResult<InappifyCheckoutResult>> createCheckout(
    InappifyPurchaseRequest request,
  ) async {
    return _unsupported<InappifyCheckoutResult>('createCheckout');
  }

  /// Reads one authoritative checkout status.
  Future<InappifySdkResult<InappifyCheckoutResult>> getCheckoutStatus(
    InappifyCheckoutStatusRequest request,
  ) async {
    return _unsupported<InappifyCheckoutResult>('getCheckoutStatus');
  }

  /// Validates a discount code for the active customer.
  Future<InappifySdkResult<ValidateDiscountCodeData>> validateDiscountCode(
    InappifyDiscountCodeRequest request,
  ) async {
    return _unsupported<ValidateDiscountCodeData>('validateDiscountCode');
  }

  /// Refreshes customer information from the backend that owns the session.
  Future<InappifySdkResult<CustomerInfo>> getCustomerInfo(
    InappifyRefreshRequest request,
  ) async {
    return _unsupported<CustomerInfo>('getCustomerInfo');
  }

  /// Returns token-free capabilities and allowlists for the active backend.
  Future<InappifySdkResult<InappifyConfiguration>> getConfiguration() async {
    return _unsupported<InappifyConfiguration>('getConfiguration');
  }

  /// Refreshes offerings from the backend that owns the session.
  Future<InappifySdkResult<OfferingsModel>> getOfferings(
    InappifyRefreshRequest request,
  ) async {
    return _unsupported<OfferingsModel>('getOfferings');
  }

  /// Updates runtime country or app-version targeting inputs.
  Future<InappifySdkResult<void>> setTargetingContext(
    InappifyTargetingContextRequest request,
  ) async {
    return _unsupported<void>('setTargetingContext');
  }

  /// Resolves the current offering using backend-owned rules and placement.
  Future<InappifySdkResult<OfferingModel>> getCurrentOffering(
    InappifyCurrentOfferingRequest request,
  ) async {
    return _unsupported<OfferingModel>('getCurrentOffering');
  }

  /// Checks an entitlement, optionally refreshing customer information first.
  Future<InappifySdkResult<bool>> checkEntitlement(
    InappifyEntitlementCheckRequest request,
  ) async {
    return _unsupported<bool>('checkEntitlement');
  }

  /// Stores or removes custom customer attributes.
  Future<InappifySdkResult<List<Attribute>>> setAttributes(
    InappifyAttributesRequest request,
  ) async {
    return _unsupported<List<Attribute>>('setAttributes');
  }

  /// Deletes custom attributes by key.
  Future<InappifySdkResult<List<Attribute>>> deleteAttributes(
    InappifyDeleteAttributesRequest request,
  ) async {
    return _unsupported<List<Attribute>>('deleteAttributes');
  }

  /// Stores a reserved customer attribute.
  Future<InappifySdkResult<void>> setReservedAttribute(
    InappifyReservedAttributeRequest request,
  ) async {
    return _unsupported<void>('setReservedAttribute');
  }

  /// Synchronizes the complete attribute set for the active customer.
  Future<InappifySdkResult<List<Attribute>>> syncAttributes() async {
    return _unsupported<List<Attribute>>('syncAttributes');
  }

  /// Synchronizes an explicit attribute list for the active customer.
  Future<InappifySdkResult<List<Attribute>>> syncAttributeValues(
    InappifyAttributesRequest request,
  ) async {
    return _unsupported<List<Attribute>>('syncAttributeValues');
  }

  /// Reports whether the browser or native allowlist permits a reserved key.
  Future<InappifySdkResult<bool>> canSetReservedAttribute(
    InappifyReservedAttributeCapabilityRequest request,
  ) async {
    return _unsupported<bool>('canSetReservedAttribute');
  }

  /// Polls authoritative checkout state after a browser payment return.
  Future<InappifySdkResult<InappifyCheckoutResult>> handlePaymentReturn(
    InappifyPaymentReturnRequest request,
  ) async {
    return _unsupported<InappifyCheckoutResult>('handlePaymentReturn');
  }

  /// Returns the non-secret checkout id retained for a browser redirect.
  ///
  /// A successful result may contain null when no checkout is pending. Session
  /// credentials and payment status must never be returned by this method.
  Future<InappifySdkResult<String>> getPendingCheckoutId() async {
    return _unsupported<String>('getPendingCheckoutId');
  }

  InappifySdkResult<T> _unsupported<T>(String operation) {
    return InappifySdkResult<T>.failure(InappifyFailure.unsupported(operation));
  }
}
