package com.inappify.inappify_sdk

/** Stable protocol identifiers shared with the Flutter MethodChannel adapter. */
internal object InappifyChannelContract {
  const val CHANNEL_NAME = "inappify_sdk"
  const val EVENT_CHANNEL_NAME = "inappify_sdk/events/v1"
  const val HTTP_EVENT_CHANNEL_NAME = "inappify_sdk/http/v2"
  const val PROTOCOL_VERSION = 1

  const val HANDSHAKE_METHOD = "sdkHandshake"
  const val SET_LOG_LEVEL_METHOD = "sdkSetLogLevel"
  const val SET_LOG_HANDLER_METHOD = "sdkSetLogHandler"
  const val LOG_CALLBACK = "sdkLog"
  const val CONFIGURE_METHOD = "sdkConfigure"
  const val RESTORE_CACHED_SESSION_METHOD = "sdkRestoreCachedSession"
  const val LOGIN_METHOD = "sdkLogin"
  const val LOGOUT_METHOD = "sdkLogout"
  const val PURCHASE_METHOD = "sdkPurchase"
  const val VALIDATE_DISCOUNT_CODE_METHOD = "sdkValidateDiscountCode"
  const val GET_CUSTOMER_INFO_METHOD = "sdkGetCustomerInfo"
  const val GET_OFFERINGS_METHOD = "sdkGetOfferings"
  const val SET_ATTRIBUTES_METHOD = "sdkSetAttributes"
  const val SET_RESERVED_ATTRIBUTE_METHOD = "sdkSetReservedAttribute"
  const val SYNC_ATTRIBUTES_METHOD = "sdkSyncAttributes"
  const val EXCHANGE_IDENTITY_TICKET_METHOD = "sdkExchangeIdentityTicket"
  const val REQUEST_OTP_METHOD = "sdkRequestOtp"
  const val CREATE_OTP_CAPTCHA_METHOD = "sdkCreateOtpCaptcha"
  const val VERIFY_OTP_METHOD = "sdkVerifyOtp"
  const val SET_TARGETING_CONTEXT_METHOD = "sdkSetTargetingContext"
  const val GET_OFFERING_METHOD = "sdkGetOffering"
  const val SYNC_ATTRIBUTES_AND_OFFERINGS_METHOD = "sdkSyncAttributesAndOfferingsIfNeeded"
  const val HANDLE_DEEP_LINK_METHOD = "sdkHandleDeepLink"
  const val SET_DELIVERY_HANDLER_METHOD = "sdkSetConsumableDeliveryHandler"
  const val CONSUMABLE_DELIVERY_CALLBACK = "sdkConsumableDelivery"
  const val GET_CURRENT_OFFERING_METHOD = "sdkGetCurrentOffering"
  const val CHECK_ENTITLEMENT_METHOD = "sdkCheckEntitlement"
  const val DELETE_ATTRIBUTES_METHOD = "sdkDeleteAttributes"
  const val SYNC_ATTRIBUTE_VALUES_METHOD = "sdkSyncAttributeValues"
  const val CAN_SET_RESERVED_ATTRIBUTE_METHOD = "sdkCanSetReservedAttribute"
  const val HANDLE_PAYMENT_RETURN_METHOD = "sdkHandlePaymentReturn"
  const val GET_PENDING_CHECKOUT_ID_METHOD = "sdkGetPendingCheckoutId"
  const val CREATE_CHECKOUT_METHOD = "sdkCreateCheckout"
  const val GET_CHECKOUT_STATUS_METHOD = "sdkGetCheckoutStatus"
  const val GET_CONFIGURATION_METHOD = "sdkGetConfiguration"
  const val SYNC_PURCHASES_METHOD = "sdkSyncPurchases"
  const val RESTORE_PURCHASES_METHOD = "sdkRestorePurchases"
  const val SYNC_PENDING_CONSUMABLES_METHOD = "sdkSyncPendingConsumables"
  const val CONFIRM_DELIVERY_METHOD = "sdkConfirmDelivery"
  const val V2_CUSTOMER_INFO_METHOD = "sdkV2CustomerInfo"
  const val V2_OFFERINGS_METHOD = "sdkV2Offerings"
  const val QUEUE_ATTRIBUTES_METHOD = "sdkQueueAttributes"
  const val FLUSH_ATTRIBUTES_METHOD = "sdkFlushAttributes"
  const val SET_NETWORK_ENABLED_METHOD = "sdkSetNetworkEnabled"
  const val IS_PAYMENT_URL_ALLOWED_METHOD = "sdkIsPaymentUrlAllowed"

  const val PROTOCOL_VERSION_KEY = "protocolVersion"
  const val REQUEST_ID_KEY = "requestId"
  const val PAYLOAD_KEY = "payload"
  const val OK_KEY = "ok"
  const val DATA_KEY = "data"
  const val SNAPSHOT_KEY = "snapshot"
  const val ERROR_KEY = "error"
  const val ERROR_CODE_KEY = "code"
  const val ERROR_MESSAGE_KEY = "message"
  const val ERROR_RETRYABLE_KEY = "retryable"
  const val ERROR_DETAILS_KEY = "details"
  const val EVENT_TYPE_KEY = "type"
  const val CLIENT_PROTOCOL_VERSIONS_KEY = "clientProtocolVersions"

  /** Operations fully owned by the Android SDK in protocol v1. */
  val SUPPORTED_OPERATIONS: List<String> = listOf(
    "goV2",
    "setLogLevel",
    "setLogHandler",
    "configure",
    "login",
    "logout",
    "purchase",
    "validateDiscountCode",
    "getCustomerInfo",
    "getOfferings",
    "setAttributes",
    "setReservedAttribute",
    "getCurrentOffering",
    "getOffering",
    "syncAttributesAndOfferingsIfNeeded",
    "handleDeepLink",
    "setConsumableDeliveryHandler",
    "canSetReservedAttribute",
    "syncStorePurchases",
    "restoreStorePurchases",
    "syncPendingConsumables",
    "confirmDelivery",
    "customerInfoWithPolicy",
    "offeringsWithPolicy",
    "setNetworkEnabled",
    "isPaymentUrlAllowed",
    "getConfiguration",
  )

  /** Methods known to protocol v1 but intentionally unavailable on Android. */
  val UNSUPPORTED_ANDROID_METHODS: Set<String> = setOf(
    EXCHANGE_IDENTITY_TICKET_METHOD,
    REQUEST_OTP_METHOD,
    CREATE_OTP_CAPTCHA_METHOD,
    VERIFY_OTP_METHOD,
    HANDLE_PAYMENT_RETURN_METHOD,
    GET_PENDING_CHECKOUT_ID_METHOD,
    CREATE_CHECKOUT_METHOD,
    GET_CHECKOUT_STATUS_METHOD,
  )

  val NATIVE_METHODS: Set<String> = setOf(
    CONFIGURE_METHOD,
    LOGIN_METHOD,
    LOGOUT_METHOD,
    PURCHASE_METHOD,
    VALIDATE_DISCOUNT_CODE_METHOD,
    GET_CUSTOMER_INFO_METHOD,
    GET_OFFERINGS_METHOD,
    SET_ATTRIBUTES_METHOD,
    SET_RESERVED_ATTRIBUTE_METHOD,
    GET_CURRENT_OFFERING_METHOD,
    GET_OFFERING_METHOD,
    SYNC_ATTRIBUTES_AND_OFFERINGS_METHOD,
    HANDLE_DEEP_LINK_METHOD,
    SET_DELIVERY_HANDLER_METHOD,
    CAN_SET_RESERVED_ATTRIBUTE_METHOD,
    SYNC_PURCHASES_METHOD,
    RESTORE_PURCHASES_METHOD,
    SYNC_PENDING_CONSUMABLES_METHOD,
    CONFIRM_DELIVERY_METHOD,
    V2_CUSTOMER_INFO_METHOD,
    V2_OFFERINGS_METHOD,
    SET_NETWORK_ENABLED_METHOD,
    IS_PAYMENT_URL_ALLOWED_METHOD,
    GET_CONFIGURATION_METHOD,
  )

  val SDK_METHODS: Set<String> = NATIVE_METHODS + UNSUPPORTED_ANDROID_METHODS
}

/** A decoded protocol-v1 request whose correlation identifier can be echoed. */
internal data class InappifyChannelRequest(
  val requestId: String,
  val payload: Map<String, Any?>,
)

/** Result of validating a MethodChannel request envelope. */
internal sealed interface InappifyChannelRequestResult {
  data class Valid(val request: InappifyChannelRequest) : InappifyChannelRequestResult

  data class SemanticFailure(
    val requestId: String,
    val code: String,
    val message: String,
    val details: Map<String, Any?> = emptyMap(),
  ) : InappifyChannelRequestResult

  data class TransportFailure(val message: String) : InappifyChannelRequestResult
}

/** Strictly validates the common request envelope without truncating numbers. */
internal fun decodeChannelRequest(arguments: Any?): InappifyChannelRequestResult {
  val envelope = arguments as? Map<*, *>
    ?: return InappifyChannelRequestResult.TransportFailure(
      "The Inappify request envelope must be a map.",
    )
  val requestId = envelope[InappifyChannelContract.REQUEST_ID_KEY] as? String
    ?: return InappifyChannelRequestResult.TransportFailure(
      "The Inappify request envelope has no valid request identifier.",
    )
  val protocolVersion = exactInt(
    envelope[InappifyChannelContract.PROTOCOL_VERSION_KEY],
  )
  if (protocolVersion != InappifyChannelContract.PROTOCOL_VERSION) {
    return InappifyChannelRequestResult.SemanticFailure(
      requestId = requestId,
      code = "protocolMismatch",
      message = "Unsupported Inappify protocol version.",
      details = mapOf(
        InappifyChannelContract.PROTOCOL_VERSION_KEY to
          InappifyChannelContract.PROTOCOL_VERSION,
      ),
    )
  }
  val rawPayload = envelope[InappifyChannelContract.PAYLOAD_KEY]
  if (rawPayload !is Map<*, *>) {
    return InappifyChannelRequestResult.SemanticFailure(
      requestId = requestId,
      code = "invalidConfiguration",
      message = "The Inappify request payload must be a map.",
    )
  }
  val payload = LinkedHashMap<String, Any?>(rawPayload.size)
  rawPayload.forEach { (key, value) ->
    if (key !is String) {
      return InappifyChannelRequestResult.SemanticFailure(
        requestId = requestId,
        code = "invalidConfiguration",
        message = "The Inappify request payload must use string keys.",
      )
    }
    payload[key] = value
  }
  return InappifyChannelRequestResult.Valid(
    InappifyChannelRequest(requestId = requestId, payload = payload),
  )
}

/** Returns an exact integer without accepting a fractional codec number. */
internal fun exactInt(value: Any?): Int? = when (value) {
  is Byte -> value.toInt()
  is Short -> value.toInt()
  is Int -> value
  is Long -> value.takeIf { it in Int.MIN_VALUE..Int.MAX_VALUE }?.toInt()
  is Float -> value.toDouble().exactIntOrNull()
  is Double -> value.exactIntOrNull()
  else -> null
}

/** Returns an exact long without accepting a fractional codec number. */
internal fun exactLong(value: Any?): Long? = when (value) {
  is Byte -> value.toLong()
  is Short -> value.toLong()
  is Int -> value.toLong()
  is Long -> value
  is Float -> value.toDouble().exactLongOrNull()
  is Double -> value.exactLongOrNull()
  else -> null
}

private fun Double.exactIntOrNull(): Int? = takeIf {
  isFinite() && this % 1.0 == 0.0 && this in Int.MIN_VALUE.toDouble()..Int.MAX_VALUE.toDouble()
}?.toInt()

private fun Double.exactLongOrNull(): Long? = takeIf {
  isFinite() && this % 1.0 == 0.0 && this >= LONG_MIN_AS_DOUBLE &&
    this < LONG_MAX_EXCLUSIVE_AS_DOUBLE
}?.toLong()

private const val LONG_MIN_AS_DOUBLE = -9.223372036854776E18
private const val LONG_MAX_EXCLUSIVE_AS_DOUBLE = 9.223372036854776E18
