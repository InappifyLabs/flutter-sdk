/// Versioned wire contract shared with Android, iOS, and future EventChannels.
///
/// Published method names and keys are stable protocol identifiers. New fields
/// must be optional within a protocol version; breaking changes require a new
/// protocol version rather than changing the meaning of an existing key.
abstract final class InappifyChannelContract {
  /// Existing channel name retained so host applications do not need to
  /// register a second plugin during protocol-v1 migration.
  static const String channelName = 'inappify_sdk';

  /// Reserved channel for redirect callbacks and native state-change events.
  static const String eventChannelName = 'inappify_sdk/events/v1';

  /// Current exact-integer wire protocol version.
  static const int protocolVersion = 1;

  /// Capability negotiation method.
  static const String handshake = 'sdkHandshake';

  /// Session configuration method.
  static const String configure = 'sdkConfigure';
  static const String restoreCachedSession = 'sdkRestoreCachedSession';

  /// Customer login method.
  static const String login = 'sdkLogin';

  /// Customer logout method.
  static const String logout = 'sdkLogout';

  /// Purchase method.
  static const String purchase = 'sdkPurchase';

  /// Discount-code validation method.
  static const String validateDiscountCode = 'sdkValidateDiscountCode';

  /// Customer refresh method.
  static const String getCustomerInfo = 'sdkGetCustomerInfo';

  /// Offering refresh method.
  static const String getOfferings = 'sdkGetOfferings';

  /// Custom-attribute update method.
  static const String setAttributes = 'sdkSetAttributes';

  /// Reserved-attribute update method.
  static const String setReservedAttribute = 'sdkSetReservedAttribute';

  /// Attribute synchronization method.
  static const String syncAttributes = 'sdkSyncAttributes';

  /// One-time Identity Ticket exchange method.
  static const String exchangeIdentityTicket = 'sdkExchangeIdentityTicket';

  /// OTP challenge creation method.
  static const String requestOtp = 'sdkRequestOtp';

  /// Explicit OTP CAPTCHA challenge method.
  static const String createOtpCaptcha = 'sdkCreateOtpCaptcha';

  /// OTP challenge verification method.
  static const String verifyOtp = 'sdkVerifyOtp';

  /// Runtime offering-targeting context method.
  static const String setTargetingContext = 'sdkSetTargetingContext';

  /// Placement-aware current-offering method.
  static const String getCurrentOffering = 'sdkGetCurrentOffering';

  /// Entitlement verification method.
  static const String checkEntitlement = 'sdkCheckEntitlement';

  /// Custom-attribute deletion method.
  static const String deleteAttributes = 'sdkDeleteAttributes';

  /// Explicit attribute synchronization method.
  static const String syncAttributeValues = 'sdkSyncAttributeValues';

  /// Reserved-attribute allowlist query method.
  static const String canSetReservedAttribute = 'sdkCanSetReservedAttribute';

  /// Authoritative checkout-return polling method.
  static const String handlePaymentReturn = 'sdkHandlePaymentReturn';

  /// Non-secret pending checkout correlation query.
  static const String getPendingCheckoutId = 'sdkGetPendingCheckoutId';

  /// Checkout creation without navigation.
  static const String createCheckout = 'sdkCreateCheckout';

  /// One authoritative checkout-status read.
  static const String getCheckoutStatus = 'sdkGetCheckoutStatus';

  /// Token-free SDK configuration query method.
  static const String getConfiguration = 'sdkGetConfiguration';

  static const String httpEventChannelName = 'inappify_sdk/http/v2';
  static const String syncPurchases = 'sdkSyncPurchases';
  static const String restorePurchases = 'sdkRestorePurchases';
  static const String syncPendingConsumables = 'sdkSyncPendingConsumables';
  static const String confirmDelivery = 'sdkConfirmDelivery';
  static const String customerInfoWithPolicy = 'sdkV2CustomerInfo';
  static const String offeringsWithPolicy = 'sdkV2Offerings';
  static const String queueAttributes = 'sdkQueueAttributes';
  static const String flushAttributes = 'sdkFlushAttributes';
  static const String recover = 'sdkRecover';
  static const String setNetworkEnabled = 'sdkSetNetworkEnabled';
  static const String isPaymentUrlAllowed = 'sdkIsPaymentUrlAllowed';

  /// Exact integer protocol version carried by every envelope.
  static const String protocolVersionKey = 'protocolVersion';

  /// Correlation identifier shared by a request, response, and related events.
  static const String requestIdKey = 'requestId';

  /// Semantic request body containing only standard-codec values.
  static const String payloadKey = 'payload';

  /// Boolean marker distinguishing success and semantic failure envelopes.
  static const String okKey = 'ok';

  /// Operation-specific response or event body.
  static const String dataKey = 'data';

  /// Complete authoritative state returned by lifecycle operations.
  static const String snapshotKey = 'snapshot';

  /// Structured semantic failure body.
  static const String errorKey = 'error';

  /// Stable machine-readable failure category.
  static const String errorCodeKey = 'code';

  /// Sanitized developer-facing failure description.
  static const String errorMessageKey = 'message';

  /// Whether retrying the same semantic request may be safe.
  static const String errorRetryableKey = 'retryable';

  /// Non-sensitive, standard-codec diagnostic metadata.
  static const String errorDetailsKey = 'details';

  /// Stable asynchronous event category.
  static const String eventTypeKey = 'type';

  /// Wraps a semantic request in the protocol-v1 envelope.
  static Map<String, Object?> requestEnvelope({
    required String requestId,
    required Map<String, Object?> payload,
  }) {
    return <String, Object?>{
      protocolVersionKey: protocolVersion,
      requestIdKey: requestId,
      payloadKey: payload,
    };
  }
}
