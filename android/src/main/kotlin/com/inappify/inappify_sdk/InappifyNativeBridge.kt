package com.inappify.inappify_sdk

import android.app.Activity
import com.inappify.sdk.InappifyAttribute
import com.inappify.sdk.InappifyAttributesRequest
import com.inappify.sdk.InappifyClient
import com.inappify.sdk.InappifyDeleteAttributesRequest
import com.inappify.sdk.InappifyDiscountCodeRequest
import com.inappify.sdk.InappifyLoginRequest
import com.inappify.sdk.InappifyMarket
import com.inappify.sdk.InappifyOfferingEvaluationContext
import com.inappify.sdk.InappifyOptions
import com.inappify.sdk.InappifyPurchaseRequest
import com.inappify.sdk.InappifyReservedAttribute
import com.inappify.sdk.InappifyReservedAttributeRequest
import com.inappify.sdk.InappifyResult
import com.inappify.sdk.InappifyV2Client
import com.inappify.sdk.InappifyFetchPolicy
import com.inappify.sdk.InappifyProductType
import com.inappify.sdk.confirmDelivery
import com.inappify.sdk.restorePurchases
import com.inappify.sdk.restoreCachedSession
import com.inappify.sdk.syncPendingConsumables
import com.inappify.sdk.isPaymentUrlAllowed
import com.inappify.sdk.verifiedSessionScope
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.sync.withLock

/** Delegates version-one channel envelopes to the explicitly selected native protocol. */
internal class InappifyNativeBridge(
  private val session: InappifyNativeSession,
  private val hostVersion: HostApplicationVersion,
) {
  private val client: InappifyClient get() = session.requireClient()

  suspend fun invoke(
    method: String,
    requestId: String,
    payload: Map<String, Any?>,
    activity: Activity?,
  ): Map<String, Any?> {
    val purchase = method == InappifyChannelContract.PURCHASE_METHOD
    if (purchase && !session.tryBeginPurchase()) {
      return InappifyNativeCodec.withRuntimeState(InappifyNativeCodec.failureEnvelope(
        requestId, "unknown", "Another Inappify purchase is already in progress.",
        retryable = true, details = mapOf("operation" to "purchase", "nativeCode" to "PURCHASE_IN_PROGRESS"),
        snapshot = session.currentClient?.snapshot, hostVersion = hostVersion,
      ), session)
    }
    return try {
      invokeAdmitted(method, requestId, payload, activity)
    } finally {
      if (purchase) session.endPurchase()
    }
  }

  private suspend fun invokeAdmitted(
    method: String,
    requestId: String,
    payload: Map<String, Any?>,
    activity: Activity?,
  ): Map<String, Any?> = try { session.operationMutex.withLock {
    val reader = PayloadReader(payload)
    when (method) {
      InappifyChannelContract.CONFIGURE_METHOD -> {
        val options = reader.options()
        val selected = session.select(MobileProtocol.fromWire(payload["mobileProtocol"]))
        unitResult(requestId, selected.configure(options))
      }

      InappifyChannelContract.RESTORE_CACHED_SESSION_METHOD -> {
        val options = reader.options()
        val selected = session.select(MobileProtocol.fromWire(payload["mobileProtocol"]))
        result(requestId, selected.restoreCachedSession(options)) { mapOf("value" to it) }
      }

      InappifyChannelContract.LOGIN_METHOD -> unitResult(
        requestId,
        client.login(
          InappifyLoginRequest(
            apiKey = reader.requiredString("apiKey"),
            appUserIdentifier = reader.requiredString("appUserIdentifier"),
          ),
        ),
      )

      InappifyChannelContract.LOGOUT_METHOD -> unitResult(requestId, client.logout())

      InappifyChannelContract.PURCHASE_METHOD -> {
        val idempotencyKey = reader.requiredString("idempotencyKey")
        if (idempotencyKey != requestId || !idempotencyKey.isSafeCorrelationId()) {
          throw PayloadException(
            code = "invalidConfiguration",
            message = "The purchase correlation identifier is invalid.",
          )
        }
        val request = reader.purchaseRequest(idempotencyKey)
        val result = if (activity == null) {
          client.purchase(request)
        } else {
          client.purchase(activity, request)
        }
        result(requestId, result, InappifyNativeCodec::purchase)
      }

      InappifyChannelContract.VALIDATE_DISCOUNT_CODE_METHOD -> result(
        requestId,
        client.validateDiscountCode(
          InappifyDiscountCodeRequest(
            discountCode = reader.requiredString("discountCode"),
            offeringIdentifier = reader.optionalString("offeringIdentifier"),
          ),
        ),
        InappifyNativeCodec::discountCode,
      )

      InappifyChannelContract.GET_CUSTOMER_INFO_METHOD -> {
        val force = reader.requiredBoolean("force")
        val result = if (force) {
          client.refreshCustomerInfo()
        } else {
          client.getCustomerInfo(forceRefresh = false)
        }
        result(requestId, result, InappifyNativeCodec::customerInfo)
      }

      InappifyChannelContract.GET_OFFERINGS_METHOD -> {
        val result = if (reader.requiredBoolean("force")) {
          client.refreshOfferings()
        } else {
          client.getOfferings()
        }
        result(requestId, result, InappifyNativeCodec::offerings)
      }

      InappifyChannelContract.SET_TARGETING_CONTEXT_METHOD -> unitResult(
        requestId,
        client.setTargetingContext(
          country = reader.optionalString("country"),
          appVersion = reader.optionalString("appVersion"),
        ),
      )

      InappifyChannelContract.GET_CURRENT_OFFERING_METHOD -> result(
        requestId,
        client.getCurrentOffering(
          placementIdentifier = reader.optionalString("placementIdentifier"),
          forceRefresh = reader.requiredBoolean("forceRefresh"),
          context = reader.optionalEvaluationContext("context"),
        ),
      ) { offering -> offering?.let(InappifyNativeCodec::offering) }

      InappifyChannelContract.CHECK_ENTITLEMENT_METHOD -> result(
        requestId,
        client.checkEntitlement(
          identifier = reader.requiredString("identifier"),
          forceRefresh = reader.requiredBoolean("forceRefresh"),
        ),
        InappifyNativeCodec::boolean,
      )

      InappifyChannelContract.SET_ATTRIBUTES_METHOD -> result(
        requestId,
        client.setAttributes(reader.attributesRequest()),
        InappifyNativeCodec::attributes,
      )

      InappifyChannelContract.DELETE_ATTRIBUTES_METHOD -> result(
        requestId,
        client.deleteAttributes(
          InappifyDeleteAttributesRequest(reader.requiredStringList("keys")),
        ),
        InappifyNativeCodec::attributes,
      )

      InappifyChannelContract.SET_RESERVED_ATTRIBUTE_METHOD -> unitResult(
        requestId,
        client.setReservedAttribute(
          InappifyReservedAttributeRequest(
            attribute = reader.requiredReservedAttribute("attribute"),
            value = reader.requiredString("value"),
          ),
        ),
      )

      InappifyChannelContract.SYNC_ATTRIBUTES_METHOD -> result(
        requestId,
        client.syncAttributes(),
        InappifyNativeCodec::attributes,
      )

      InappifyChannelContract.SYNC_ATTRIBUTE_VALUES_METHOD -> result(
        requestId,
        client.syncAttributes(reader.attributesRequest()),
        InappifyNativeCodec::attributes,
      )

      InappifyChannelContract.CAN_SET_RESERVED_ATTRIBUTE_METHOD -> result(
        requestId,
        client.canSetReservedAttribute(reader.requiredString("key")),
        InappifyNativeCodec::boolean,
      )

      InappifyChannelContract.SYNC_PURCHASES_METHOD -> result(
        requestId, client.syncPurchases(),
      ) { values -> mapOf("purchases" to values.map(InappifyNativeCodec::purchase)) }

      InappifyChannelContract.RESTORE_PURCHASES_METHOD -> result(
        requestId, client.restorePurchases(), InappifyNativeCodec::restore,
      )

      InappifyChannelContract.SYNC_PENDING_CONSUMABLES_METHOD -> result(
        requestId, client.syncPendingConsumables(), InappifyNativeCodec::consumableSync,
      )

      InappifyChannelContract.CONFIRM_DELIVERY_METHOD -> {
        val deliveryId = reader.positiveIdentifier("deliveryId")
        result(requestId, client.confirmDelivery(deliveryId), InappifyNativeCodec::purchase)
      }

      InappifyChannelContract.V2_CUSTOMER_INFO_METHOD -> result(
        requestId, goClient().customerInfo(reader.fetchPolicy()), InappifyNativeCodec::customerInfo,
      )

      InappifyChannelContract.V2_OFFERINGS_METHOD -> result(
        requestId, goClient().offerings(reader.fetchPolicy()), InappifyNativeCodec::offerings,
      )

      InappifyChannelContract.QUEUE_ATTRIBUTES_METHOD -> unitResult(
        requestId, goClient().queueAttributes(reader.stringValues("values")),
      )

      InappifyChannelContract.FLUSH_ATTRIBUTES_METHOD -> unitResult(requestId, goClient().flushAttributes())
      InappifyChannelContract.RECOVER_METHOD -> unitResult(requestId, goClient().recover())

      InappifyChannelContract.SET_NETWORK_ENABLED_METHOD -> {
        goClient().setNetworkEnabled(reader.requiredBoolean("enabled"))
        unitResult(requestId, InappifyResult.Success(Unit, client.snapshot))
      }

      InappifyChannelContract.IS_PAYMENT_URL_ALLOWED_METHOD -> InappifyNativeCodec.successEnvelope(
        requestId, client.snapshot, hostVersion,
        InappifyNativeCodec.boolean(goClient().isPaymentUrlAllowed(reader.requiredString("url"))),
      )

      InappifyChannelContract.GET_CONFIGURATION_METHOD -> {
        val go = client as? InappifyV2Client
        InappifyNativeCodec.successEnvelope(requestId, client.snapshot, hostVersion, mapOf(
          "mobileProtocol" to session.protocol?.wireName,
          "hasForceUpdate" to (go?.hasForceUpdate ?: false),
          "isLogoutPending" to (go?.isLogoutPending ?: false),
          "verifiedSessionScope" to go?.verifiedSessionScope?.let { scope -> mapOf(
            "issuer" to scope.issuer, "appId" to scope.appId, "projectId" to scope.projectId,
          ) },
        ))
      }

      in InappifyChannelContract.UNSUPPORTED_ANDROID_METHODS -> unsupported(requestId, method)
      else -> unsupported(requestId, method)
    }
  }
  } catch (error: PayloadException) {
    InappifyNativeCodec.failureEnvelope(
      requestId = requestId,
      code = error.code,
      message = error.message,
      details = mapOf("operation" to method),
      snapshot = session.currentClient?.snapshot,
      hostVersion = hostVersion,
    )
  } catch (error: NativeSessionException) {
    InappifyNativeCodec.failureEnvelope(
      requestId, error.code, error.message, details = mapOf("operation" to method),
      snapshot = session.currentClient?.snapshot, hostVersion = hostVersion,
    )
  } catch (error: CancellationException) {
    throw error
  } catch (_: Exception) {
    InappifyNativeCodec.failureEnvelope(
      requestId = requestId,
      code = "unknown",
      message = "The native Inappify operation could not be completed.",
      details = mapOf("operation" to method),
      snapshot = session.currentClient?.snapshot,
      hostVersion = hostVersion,
    )
  }.let { InappifyNativeCodec.withRuntimeState(it, session) }

  private fun goClient(): InappifyV2Client = client as? InappifyV2Client
    ?: throw NativeSessionException("unsupportedOperation", "This operation requires explicit Go V2 configuration.")

  private fun unitResult(
    requestId: String,
    result: InappifyResult<Unit>,
  ): Map<String, Any?> = result(requestId, result) { emptyMap() }

  private fun <T> result(
    requestId: String,
    result: InappifyResult<T>,
    encode: (T) -> Map<String, Any?>?,
  ): Map<String, Any?> = when (result) {
    is InappifyResult.Success -> InappifyNativeCodec.successEnvelope(
      requestId = requestId,
      snapshot = result.snapshot,
      hostVersion = hostVersion,
      data = encode(result.data),
    )

    is InappifyResult.Failure -> InappifyNativeCodec.failureEnvelope(
      requestId = requestId,
      error = result.error,
      snapshot = result.snapshot ?: client.snapshot,
      hostVersion = hostVersion,
    )
  }

  private fun unsupported(requestId: String, method: String): Map<String, Any?> =
    InappifyNativeCodec.failureEnvelope(
      requestId = requestId,
      code = "unsupportedOperation",
      message = "This operation is not available in the Android SDK.",
      details = mapOf("operation" to method),
      snapshot = session.currentClient?.snapshot,
      hostVersion = hostVersion,
    )
}

/** Strict reader for payloads created by the Dart protocol-v1 request models. */
internal class PayloadReader(private val values: Map<String, Any?>) {
  fun options(): InappifyOptions = InappifyOptions(
    apiKey = requiredString("apiKey"),
    appUserIdentifier = optionalString("appUserIdentifier"),
    market = optionalMarket("market"),
    marketKey = optionalString("marketKey"),
    country = optionalString("country"),
    appVersion = optionalString("appVersion"),
    enableSubscriptionRecoveryWithoutPayload = booleanOrDefault(
      "enableSubscriptionRecoveryWithoutPayload", true,
    ),
  )

  fun stringMap(key: String): Map<String, Any?> {
    val raw = values[key] as? Map<*, *> ?: invalid(key, "must be a map")
    return raw.entries.associate { entry ->
      (entry.key as? String ?: invalid(key, "must have string keys")) to entry.value
    }
  }

  fun stringValues(key: String): Map<String, String?> = stringMap(key).mapValues { (_, value) ->
    if (value != null && value !is String) invalid(key, "must contain strings or null")
    value as String?
  }

  fun positiveIdentifier(key: String): Long {
    val raw = values[key]
    if (raw !is Byte && raw !is Short && raw !is Int && raw !is Long) {
      invalid(key, "must be an integer identifier")
    }
    return requiredLong(key).takeIf { it > 0 } ?: invalid(key, "must be positive")
  }

  fun fetchPolicy(): InappifyFetchPolicy = when (requiredString("policy")) {
    "cacheOnly" -> InappifyFetchPolicy.CACHE_ONLY
    "cacheFirst" -> InappifyFetchPolicy.CACHE_FIRST
    "networkFirst" -> InappifyFetchPolicy.NETWORK_FIRST
    "networkOnly" -> InappifyFetchPolicy.NETWORK_ONLY
    else -> invalid("policy", "is unsupported")
  }

  fun purchaseRequest(idempotencyKey: String): InappifyPurchaseRequest {
    val productType = optionalString("productType")?.let { name ->
      InappifyProductType.values().firstOrNull { it.name == name }
        ?: invalid("productType", "is unsupported")
    }
    val request = if (productType == null) InappifyPurchaseRequest(
      productIdentifier = requiredString("productIdentifier"),
      offeringIdentifier = requiredString("offeringIdentifier"),
      packageIdentifier = optionalString("packageIdentifier"),
      discountCode = optionalString("discountCode"),
      country = optionalString("country"),
      appVersion = optionalString("appVersion"),
      apiKey = optionalString("apiKey"),
      discount = requiredLong("discount"),
      isCrypto = requiredBoolean("isCrypto"),
      market = requiredMarket("market"),
      marketKey = optionalString("marketKey"),
      isLostPurchase = requiredBoolean("isLostPurchase"),
      lostPurchaseToken = optionalString("lostPurchaseToken"),
      lostPurchaseTime = optionalLong("lostPurchaseTime"),
      idempotencyKey = idempotencyKey,
      dynamicPriceToken = optionalString("dynamicPriceToken"),
    ) else InappifyPurchaseRequest(
      productIdentifier = requiredString("productIdentifier"),
      offeringIdentifier = requiredString("offeringIdentifier"),
      packageIdentifier = optionalString("packageIdentifier"),
      discountCode = optionalString("discountCode"),
      country = optionalString("country"),
      appVersion = optionalString("appVersion"),
      apiKey = optionalString("apiKey"),
      discount = requiredLong("discount"),
      isCrypto = requiredBoolean("isCrypto"),
      market = requiredMarket("market"),
      marketKey = optionalString("marketKey"),
      isLostPurchase = requiredBoolean("isLostPurchase"),
      lostPurchaseToken = optionalString("lostPurchaseToken"),
      lostPurchaseTime = optionalLong("lostPurchaseTime"),
      idempotencyKey = idempotencyKey,
      dynamicPriceToken = optionalString("dynamicPriceToken"),
      productType = productType,
    )
    val paywallId = optionalLong("paywallId")
    val paywallRevision = optionalLong("paywallRevision")
    if (paywallId == null && paywallRevision == null) return request
    if (paywallId == null || paywallRevision == null || paywallId <= 0 || paywallRevision <= 0) {
      invalid("paywallId/paywallRevision", "must be positive integers supplied together")
    }
    return request.withPaywallAttribution(paywallId, paywallRevision)
  }

  fun requiredString(key: String): String = values[key] as? String
    ?: invalid(key, "must be a string")

  fun optionalString(key: String): String? {
    val value = values[key] ?: return null
    return value as? String ?: invalid(key, "must be a string or null")
  }

  private fun booleanOrDefault(key: String, default: Boolean): Boolean =
    if (values.containsKey(key)) requiredBoolean(key) else default

  fun requiredBoolean(key: String): Boolean = values[key] as? Boolean
    ?: invalid(key, "must be a boolean")

  fun requiredLong(key: String): Long = exactLong(values[key])
    ?: invalid(key, "must be an integer")

  fun optionalLong(key: String): Long? {
    val value = values[key] ?: return null
    return exactLong(value) ?: invalid(key, "must be an integer or null")
  }

  fun optionalMarket(key: String): InappifyMarket? {
    val value = values[key] ?: return null
    return market(value as? String ?: invalid(key, "must be a string or null"))
  }

  fun requiredMarket(key: String): InappifyMarket = market(requiredString(key))

  fun requiredReservedAttribute(key: String): InappifyReservedAttribute =
    when (requiredString(key)) {
      "email" -> InappifyReservedAttribute.EMAIL
      "apnsToken" -> InappifyReservedAttribute.APNS_TOKEN
      "displayName" -> InappifyReservedAttribute.DISPLAY_NAME
      "fcmToken" -> InappifyReservedAttribute.FCM_TOKEN
      "idfa" -> InappifyReservedAttribute.IDFA
      "idfv" -> InappifyReservedAttribute.IDFV
      "ip" -> InappifyReservedAttribute.IP
      "phoneNumber" -> InappifyReservedAttribute.PHONE_NUMBER
      "campaign" -> InappifyReservedAttribute.CAMPAIGN
      "keyword" -> InappifyReservedAttribute.KEYWORD
      else -> invalid(key, "contains an unsupported reserved attribute")
    }

  fun requiredStringList(key: String): List<String> {
    val list = values[key] as? List<*> ?: invalid(key, "must be a list")
    return list.map { value ->
      value as? String ?: invalid(key, "must contain only strings")
    }
  }

  fun attributesRequest(): InappifyAttributesRequest {
    val list = values["attributes"] as? List<*>
      ?: invalid("attributes", "must be a list")
    val attributes = list.map { item ->
      val map = item as? Map<*, *> ?: invalid("attributes", "must contain maps")
      val key = nullableMapString(map, "key", "attributes")
      val value = nullableMapString(map, "value", "attributes")
      InappifyAttribute(key = key, value = value)
    }
    return InappifyAttributesRequest(
      attributes = attributes,
      idempotencyKey = optionalString("idempotencyKey"),
    )
  }

  fun optionalEvaluationContext(key: String): InappifyOfferingEvaluationContext? {
    val raw = values[key] ?: return null
    val map = raw as? Map<*, *> ?: invalid(key, "must be a map or null")
    val country = requiredMapString(map, "country", key)
    val platform = requiredMapString(map, "platform", key)
    val appVersion = requiredMapString(map, "appVersion", key)
    val sdkVersion = optionalMapString(map, "sdkVersion", key) ?: ""
    val rawAppId = map["appId"]
    val appId = if (rawAppId == null) null else exactLong(rawAppId)
      ?: invalid(key, "appId must be an integer or null")
    val rawAttributes = map["customAttributes"]
    val attributes = if (rawAttributes == null) {
      emptyMap()
    } else {
      val attributeMap = rawAttributes as? Map<*, *>
        ?: invalid(key, "customAttributes must be a map")
      attributeMap.entries.associate { entry ->
        val attributeKey = entry.key as? String
          ?: invalid(key, "customAttributes must use string keys")
        val attributeValue = entry.value
        if (attributeValue != null && attributeValue !is String) {
          invalid(key, "customAttributes values must be strings or null")
        }
        attributeKey to (attributeValue as String?)
      }
    }
    return InappifyOfferingEvaluationContext(
      country = country,
      platform = platform,
      appVersion = appVersion,
      sdkVersion = sdkVersion,
      appId = appId,
      customAttributes = attributes,
    )
  }

  private fun market(value: String): InappifyMarket = when (value) {
    "none" -> InappifyMarket.NONE
    "bazar" -> InappifyMarket.BAZAAR
    "myket" -> InappifyMarket.MYKET
    else -> throw PayloadException(
      code = "invalidConfiguration",
      message = "The requested marketplace is invalid.",
    )
  }

  private fun requiredMapString(
    map: Map<*, *>,
    field: String,
    parent: String,
  ): String = map[field] as? String ?: invalid(parent, "$field must be a string")

  private fun optionalMapString(
    map: Map<*, *>,
    field: String,
    parent: String,
  ): String? {
    val value = map[field] ?: return null
    return value as? String ?: invalid(parent, "$field must be a string or null")
  }

  private fun nullableMapString(
    map: Map<*, *>,
    field: String,
    parent: String,
  ): String? {
    val value = map[field] ?: return null
    return value as? String ?: invalid(parent, "$field must be a string or null")
  }

  private fun invalid(key: String, requirement: String): Nothing = throw PayloadException(
    code = "invalidConfiguration",
    message = "The $key field $requirement.",
  )
}

internal class PayloadException(
  val code: String,
  override val message: String,
) : IllegalArgumentException(message)

private fun String.isSafeCorrelationId(): Boolean =
  isNotEmpty() &&
    length <= 128 &&
    all { character ->
      character.isLetterOrDigit() ||
        character == '-' ||
        character == '_' ||
        character == '.' ||
        character == ':'
    }
