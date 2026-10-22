package com.inappify.inappify_sdk

import android.app.Activity
import com.inappify.sdk.*
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

      InappifyChannelContract.LOGIN_METHOD -> unitResult(
        requestId, client.logIn(reader.requiredString("appUserIdentifier")),
      )
      InappifyChannelContract.LOGOUT_METHOD -> unitResult(requestId, client.logOut())

      InappifyChannelContract.PURCHASE_METHOD -> {
        val idempotencyKey = reader.requiredString("idempotencyKey")
        if (idempotencyKey != requestId || !idempotencyKey.isSafeCorrelationId()) {
          throw PayloadException(
            code = "invalidConfiguration",
            message = "The purchase correlation identifier is invalid.",
          )
        }
        val params = reader.purchaseParams(idempotencyKey, activity)
        result(requestId, client.purchase(params), InappifyNativeCodec::purchase)
      }

      InappifyChannelContract.VALIDATE_DISCOUNT_CODE_METHOD -> result(
        requestId, client.getDiscountedPaymentLinks(reader.requiredString("discountCode")),
        InappifyNativeCodec::discountCode,
      )

      InappifyChannelContract.GET_CUSTOMER_INFO_METHOD -> result(
        requestId, client.getCustomerInfo(reader.customerInfoPolicy()), InappifyNativeCodec::customerInfo,
      )
      InappifyChannelContract.GET_OFFERINGS_METHOD -> result(
        requestId, client.getOfferings(), InappifyNativeCodec::offerings,
      )
      InappifyChannelContract.SYNC_ATTRIBUTES_AND_OFFERINGS_METHOD -> result(
        requestId, client.syncAttributesAndOfferingsIfNeeded(), InappifyNativeCodec::offerings,
      )
      InappifyChannelContract.GET_OFFERING_METHOD -> result(
        requestId, client.getOffering(reader.requiredString("identifier")),
      ) { offering -> offering?.let(InappifyNativeCodec::offering) }
      InappifyChannelContract.GET_CURRENT_OFFERING_METHOD -> result(
        requestId, client.getCurrentOffering(reader.optionalString("placementIdentifier")),
      ) { offering -> offering?.let(InappifyNativeCodec::offering) }
      InappifyChannelContract.SET_ATTRIBUTES_METHOD -> result(
        requestId, client.setAttributes(reader.stringValues("attributes")), InappifyNativeCodec::attributes,
      )
      InappifyChannelContract.HANDLE_DEEP_LINK_METHOD -> InappifyNativeCodec.successEnvelope(
        requestId, client.snapshot, hostVersion,
        InappifyNativeCodec.boolean(goClient().handleDeepLink(reader.requiredString("url"))),
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

      InappifyChannelContract.CAN_SET_RESERVED_ATTRIBUTE_METHOD -> result(
        requestId,
        client.canSetReservedAttribute(reader.requiredString("key")),
        InappifyNativeCodec::boolean,
      )

      InappifyChannelContract.SYNC_PURCHASES_METHOD -> result(
        requestId, client.syncStorePurchases(),
      ) { values -> mapOf("purchases" to values.map(InappifyNativeCodec::purchase)) }

      InappifyChannelContract.GET_PURCHASE_ATTEMPT_METHOD -> result(
        requestId, client.getPurchaseAttempt(reader.requiredString("attemptId")),
      ) { value -> value?.let(InappifyNativeCodec::purchaseAttempt) }
      InappifyChannelContract.GET_PURCHASE_ATTEMPTS_METHOD -> result(
        requestId, client.getPurchaseAttempts(),
      ) { values -> mapOf("attempts" to values.map(InappifyNativeCodec::purchaseAttempt)) }

      InappifyChannelContract.RESTORE_PURCHASES_METHOD -> result(
        requestId, client.restoreStorePurchases(), InappifyNativeCodec::restore,
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

  fun customerInfoPolicy(): InappifyCacheFetchPolicy = when (optionalString("fetchPolicy")) {
    null, "cachedOrFetched" -> InappifyCacheFetchPolicy.CACHED_OR_FETCHED
    "cacheOnly" -> InappifyCacheFetchPolicy.CACHE_ONLY
    "fetchCurrent" -> InappifyCacheFetchPolicy.FETCH_CURRENT
    "notStaleCachedOrCurrent" -> InappifyCacheFetchPolicy.NOT_STALE_CACHED_OR_CURRENT
    else -> invalid("fetchPolicy", "is unsupported")
  }

  fun purchaseParams(idempotencyKey: String, activity: Activity?): InappifyPurchaseParams {
    val catalog = PayloadReader(stringMap("packageToPurchase"))
    val product = PayloadReader(catalog.stringMap("product"))
    val type = product.optionalString("productType")?.let { name ->
      InappifyProductType.values().firstOrNull { it.name == name }
        ?: invalid("productType", "is unsupported")
    }
    // The public Offering constructor attaches its parent context to the package.
    val selected = InappifyOffering(
      identifier = catalog.requiredString("offeringIdentifier"),
      packages = listOf(InappifyPackage(
        identifier = catalog.requiredString("identifier"),
        product = InappifyStoreProduct(identifier = product.requiredString("identifier"), productType = type),
      )),
    ).packages!!.single()
    val builder = if (activity == null) InappifyPurchaseParams.Builder(selected)
      else InappifyPurchaseParams.Builder(activity, selected)
    builder.idempotencyKey(idempotencyKey)
    val paywallId = optionalLong("paywallId")
    val revision = optionalLong("paywallRevision")
    if (paywallId != null || revision != null) {
      if (paywallId == null || revision == null || paywallId <= 0 || revision <= 0)
        invalid("paywallId/paywallRevision", "must be positive integers supplied together")
      builder.paywallAttribution(paywallId, revision)
    }
    return builder.build()
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
