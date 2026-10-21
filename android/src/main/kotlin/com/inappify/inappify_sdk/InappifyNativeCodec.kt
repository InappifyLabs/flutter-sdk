package com.inappify.inappify_sdk

import com.inappify.sdk.InappifyMarket
import com.inappify.sdk.InappifyAttribute
import com.inappify.sdk.InappifyCondition
import com.inappify.sdk.InappifyCustomerInfo
import com.inappify.sdk.InappifyDiscountCodeResult
import com.inappify.sdk.InappifyEntitlement
import com.inappify.sdk.InappifyError
import com.inappify.sdk.InappifyErrorCode
import com.inappify.sdk.InappifyEvent
import com.inappify.sdk.InappifyEventType
import com.inappify.sdk.InappifyOffering
import com.inappify.sdk.InappifyOfferings
import com.inappify.sdk.InappifyPackage
import com.inappify.sdk.InappifyPlacement
import com.inappify.sdk.InappifyPlacementOffering
import com.inappify.sdk.InappifyPrice
import com.inappify.sdk.InappifyPurchase
import com.inappify.sdk.InappifyPurchaseLink
import com.inappify.sdk.InappifyRule
import com.inappify.sdk.InappifySnapshot
import com.inappify.sdk.InappifyStoreProduct
import com.inappify.sdk.InappifyTransaction
import com.inappify.sdk.InappifyConsumableDelivery
import com.inappify.sdk.InappifyConsumableSyncResult
import com.inappify.sdk.InappifyRestoreResult
import com.inappify.sdk.InappifyHttpTrace
import com.inappify.sdk.InappifyV2Client

/** Host metadata mirrored through the Flutter compatibility snapshot. */
internal data class HostApplicationVersion(
  val versionName: String,
  val versionCode: Long,
)

/** Converts native SDK values to protocol-v1 StandardMessageCodec values. */
internal object InappifyNativeCodec {
  fun withRuntimeState(
    envelope: Map<String, Any?>,
    session: InappifyNativeSession,
  ): Map<String, Any?> {
    val rawSnapshot = envelope[InappifyChannelContract.SNAPSHOT_KEY] as? Map<*, *> ?: return envelope
    val state = LinkedHashMap(codecMap(rawSnapshot))
    state["mobileProtocol"] = session.protocol?.wireName
    state["isLogoutPending"] = (session.currentClient as? InappifyV2Client)?.isLogoutPending ?: false
    return envelope + (InappifyChannelContract.SNAPSHOT_KEY to state)
  }

  fun successEnvelope(
    requestId: String,
    snapshot: InappifySnapshot,
    hostVersion: HostApplicationVersion,
    data: Map<String, Any?>? = emptyMap(),
  ): Map<String, Any?> = linkedMapOf(
    InappifyChannelContract.PROTOCOL_VERSION_KEY to
      InappifyChannelContract.PROTOCOL_VERSION,
    InappifyChannelContract.REQUEST_ID_KEY to requestId,
    InappifyChannelContract.OK_KEY to true,
    InappifyChannelContract.DATA_KEY to data,
    InappifyChannelContract.SNAPSHOT_KEY to snapshot(snapshot, hostVersion),
  )

  fun failureEnvelope(
    requestId: String,
    code: String,
    message: String,
    retryable: Boolean = false,
    details: Map<String, Any?> = emptyMap(),
    snapshot: InappifySnapshot? = null,
    hostVersion: HostApplicationVersion? = null,
  ): Map<String, Any?> {
    val envelope = linkedMapOf<String, Any?>(
      InappifyChannelContract.PROTOCOL_VERSION_KEY to
        InappifyChannelContract.PROTOCOL_VERSION,
      InappifyChannelContract.REQUEST_ID_KEY to requestId,
      InappifyChannelContract.OK_KEY to false,
      InappifyChannelContract.ERROR_KEY to linkedMapOf(
        InappifyChannelContract.ERROR_CODE_KEY to code,
        InappifyChannelContract.ERROR_MESSAGE_KEY to message,
        InappifyChannelContract.ERROR_RETRYABLE_KEY to retryable,
        InappifyChannelContract.ERROR_DETAILS_KEY to codecMap(details),
      ),
    )
    if (snapshot != null && hostVersion != null) {
      envelope[InappifyChannelContract.SNAPSHOT_KEY] = snapshot(snapshot, hostVersion)
    }
    return envelope
  }

  fun failureEnvelope(
    requestId: String,
    error: InappifyError,
    snapshot: InappifySnapshot,
    hostVersion: HostApplicationVersion,
  ): Map<String, Any?> {
    val details = LinkedHashMap<String, Any?>(error.details.size + 1)
    details.putAll(error.details)
    details.putIfAbsent("nativeCode", error.code.name)
    return failureEnvelope(
      requestId = requestId,
      code = failureCode(error.code),
      message = error.message,
      retryable = error.isRetryable,
      details = details,
      snapshot = snapshot,
      hostVersion = hostVersion,
    )
  }

  fun eventEnvelope(
    event: InappifyEvent,
    hostVersion: HostApplicationVersion,
  ): Map<String, Any?> = linkedMapOf(
    InappifyChannelContract.PROTOCOL_VERSION_KEY to
      InappifyChannelContract.PROTOCOL_VERSION,
    InappifyChannelContract.EVENT_TYPE_KEY to eventType(event.type),
    // Native lifecycle events can carry a server request id that is unrelated
    // to the MethodChannel envelope. Purchase updates use the caller-owned
    // attempt id and are therefore the only safely correlated event type.
    InappifyChannelContract.REQUEST_ID_KEY to if (
      event.type == InappifyEventType.PURCHASE_UPDATED
    ) {
      event.requestId
    } else {
      null
    },
    InappifyChannelContract.DATA_KEY to emptyMap<String, Any?>(),
    InappifyChannelContract.SNAPSHOT_KEY to snapshot(event.snapshot, hostVersion),
  )

  fun snapshot(
    value: InappifySnapshot,
    hostVersion: HostApplicationVersion,
  ): Map<String, Any?> = linkedMapOf(
    // Credentials remain private to the native SDK. These compatibility keys
    // are retained because the Dart snapshot contract requires their presence.
    "accessToken" to null,
    "apiKey" to null,
    "customerInfo" to value.customerInfo?.let(::customerInfo),
    "offerings" to value.offerings?.let(::offerings),
    "storeInfo" to value.storeInfo,
    "forceVersion" to null, // Existing snapshot wire key; ignored by the current native SDK.
    "appId" to value.appId,
    "country" to (value.country ?: DEFAULT_COUNTRY),
    "versionName" to hostVersion.versionName,
    "versionCode" to hostVersion.versionCode,
    "sdkVersion" to value.sdkVersion,
    "failedToLoadOfferings" to value.failedToLoadOfferings,
    "failedToLoadCustomerInfo" to value.failedToLoadCustomerInfo,
    "revision" to value.revision,
    "isConfigured" to value.isConfigured,
    "isAuthenticated" to value.isAuthenticated,
    "appUserIdentifier" to value.appUserIdentifier,
    "market" to value.market?.let(::market),
    "storePlatform" to storePlatformCode(value.storePlatform),
    "sessionState" to when {
      !value.isConfigured -> "unconfigured"
      value.isAuthenticated -> "authenticated"
      else -> "anonymous"
    },
    // A snapshot alone cannot prove the most recent disk write succeeded.
    "persistenceMode" to "unknown",
  )

  fun customerInfo(value: InappifyCustomerInfo): Map<String, Any?> = linkedMapOf(
    "originalAppUserId" to value.originalAppUserId,
    "firstSeen" to value.firstSeen,
    "requestDate" to value.requestDate,
    "latestExpirationDate" to value.latestExpirationDate,
    "entitlements" to value.entitlements.map(::entitlement),
    "entitlementEvaluationTimeMillis" to value.entitlements.evaluationTimeMillis,
    "transactions" to value.transactions?.map(::transaction),
    "attributes" to value.attributes?.map(::attribute),
    "hasUsedTrial" to value.hasUsedTrial,
  )

  fun offerings(value: InappifyOfferings): Map<String, Any?> = linkedMapOf(
    "offerings" to value.offerings?.map(::offering),
    "rules" to value.rules?.map(::rule),
    "fetchedAt" to value.fetchedAt,
  ).apply {
    if (value.usesServerTargeting) {
      put("currentOffering", value.currentOfferingIdentifier)
      put("placements", value.placements)
      put("usesServerTargeting", true)
    }
  }

  fun offering(value: InappifyOffering): Map<String, Any?> = linkedMapOf(
    "identifier" to value.identifier,
    "isDefault" to value.isDefault,
    "serverDescription" to value.serverDescription,
    "trialDays" to value.trialDays,
    "metadata" to codecValue(value.metadata),
    "packages" to value.packages?.map(::inappifyPackage),
    "paywall" to value.paywall?.let(::codecMap),
  )

  fun purchase(value: InappifyPurchase): Map<String, Any?> = linkedMapOf(
    "url" to value.url,
    "purchaseStatus" to value.purchaseStatus?.name,
    "checkoutId" to value.checkoutId,
    "checkoutStatus" to value.checkoutStatus,
    "nextActionType" to value.nextActionType,
    "mobile" to linkedMapOf(
      "storePurchaseStatus" to value.storePurchaseStatus?.name,
      "deliveryId" to value.deliveryId,
      "verificationRequestId" to value.verificationRequestId?.toString(),
      "alreadyProcessed" to value.alreadyProcessed,
      "productIdentifier" to value.productIdentifier,
      "offeringIdentifier" to value.offeringIdentifier,
      "packageIdentifier" to value.packageIdentifier,
      "idempotencyKey" to value.attemptId,
      "market" to market(value.market),
    ),
  )

  /** Keep marketplace identity intact across snapshots, events and purchase results. */
  private fun market(value: InappifyMarket): String = when (value) {
    InappifyMarket.NONE -> "none"
    InappifyMarket.BAZAAR -> "bazar"
    InappifyMarket.MYKET -> "myket"
  }

  fun delivery(value: InappifyConsumableDelivery): Map<String, Any?> = linkedMapOf(
    "deliveryId" to value.deliveryId,
    "productIdentifier" to value.productIdentifier,
    "transactionIdentifier" to value.transactionIdentifier,
    "source" to value.source.name,
  )

  fun consumableSync(value: InappifyConsumableSyncResult): Map<String, Any?> = linkedMapOf(
    "discoveredCount" to value.discoveredCount,
    "completedCount" to value.completedCount,
    "pendingDeliveries" to value.pendingDeliveries.map(::delivery),
  )

  fun restore(value: InappifyRestoreResult): Map<String, Any?> = linkedMapOf(
    "restoredCount" to value.restoredCount,
    "alreadyProcessedCount" to value.alreadyProcessedCount,
    "failedCount" to value.failedCount,
    "totalCount" to value.totalCount,
  )

  /** Traces come only from the production SDK's bounded, filtered reporter. */
  fun httpTrace(value: InappifyHttpTrace): Map<String, Any?> = linkedMapOf(
    "method" to value.method,
    "endpoint" to value.endpoint,
    "requestHeaders" to value.requestHeaders,
    "requestBody" to value.requestBody,
    "statusCode" to value.statusCode,
    "responseHeaders" to value.responseHeaders,
    "responseBody" to value.responseBody,
    "requestId" to value.requestId,
    "durationMillis" to value.durationMillis,
    "failure" to value.failure?.name,
    "containsSensitiveData" to value.containsSensitiveData,
  )

  fun discountCode(value: InappifyDiscountCodeResult): Map<String, Any?> = linkedMapOf(
    "is_valid" to value.isValid,
    "error_code" to value.errorCode,
    "code" to value.code,
    "discount_id" to value.discountId,
    "discount_code_id" to value.discountCodeId,
    "percent" to value.percent,
    "message" to value.message,
    "payment_links" to value.paymentLinks?.map(::purchaseLink),
    "offering" to value.offering?.let(::offering),
  )

  fun attributes(values: List<InappifyAttribute>): Map<String, Any?> = linkedMapOf(
    "attributes" to values.map(::attribute),
  )

  fun boolean(value: Boolean): Map<String, Any?> = linkedMapOf("value" to value)

  private fun entitlement(value: InappifyEntitlement): Map<String, Any?> = linkedMapOf(
    "identifier" to value.identifier,
    "is_active" to value.isActive,
    "is_sandbox" to value.isSandbox,
    "period_type" to value.periodType,
    "purchase_date" to value.purchaseDate,
    "expiration_date" to value.expirationDate,
    "ownership_type" to value.ownershipType,
    "entitlement_type" to value.entitlementType,
    "purchase_store_ref_hash" to value.purchaseStoreRefHash,
    "purchase_store_time" to value.purchaseStoreTime,
  )

  private fun transaction(value: InappifyTransaction): Map<String, Any?> = linkedMapOf(
    "number" to value.number,
    "status" to value.status,
    "amount" to value.amount,
    "transactionDate" to value.transactionDate,
    "trackingNumber" to value.trackingNumber,
    "isCryptoGate" to value.isCryptoGate,
    "packageName" to value.packageName,
    "storePurchaseRefId" to value.storePurchaseRefId,
    "isTrial" to value.isTrial,
  )

  private fun attribute(value: InappifyAttribute): Map<String, Any?> = linkedMapOf(
    "key" to value.key,
    "value" to value.value,
  )

  private fun rule(value: InappifyRule): Map<String, Any?> = linkedMapOf(
    "default_offering" to value.defaultOffering,
    "sort" to value.sort,
    "conditions" to value.conditions?.map(::condition),
    "placements" to value.placements?.let(::placement),
  )

  private fun condition(value: InappifyCondition): Map<String, Any?> = linkedMapOf(
    "id" to value.id,
    "target_id" to value.targetId,
    "context" to value.context,
    "field" to value.field,
    "operator" to value.operator,
    "value" to value.value,
  )

  private fun placement(value: InappifyPlacement): Map<String, Any?> = linkedMapOf(
    "fallback_offering_id" to value.fallbackOfferingId,
    "placement_offerings" to value.placementOfferings?.map(::placementOffering),
  )

  private fun placementOffering(
    value: InappifyPlacementOffering,
  ): Map<String, Any?> = linkedMapOf(
    "placement_identifier" to value.placementIdentifier,
    "offering_identifier" to value.offeringIdentifier,
  )

  private fun inappifyPackage(value: InappifyPackage): Map<String, Any?> = linkedMapOf(
    "identifier" to value.identifier,
    "packageType" to value.packageType,
    "offeringIdentifier" to value.offeringIdentifier,
    "description" to value.description,
    "entitlement" to value.entitlement,
    "name" to value.name,
    "discountPercent" to value.discountPercent,
    "product" to value.product?.let(::product),
  )

  private fun product(value: InappifyStoreProduct): Map<String, Any?> = linkedMapOf(
    "identifier" to value.identifier,
    "productType" to value.productType?.name,
    "name" to value.name,
    "prices" to value.prices?.map(::price),
    "dollarPrice" to value.dollarPrice,
    "trialDays" to value.trialDays,
  )

  private fun price(value: InappifyPrice): Map<String, Any?> = linkedMapOf(
    "id" to value.id,
    "app_product_id" to value.appProductId,
    "currency" to value.currency,
    "amount" to codecValue(value.amount),
    "originalAmount" to codecValue(value.originalAmount),
    "discountAmount" to codecValue(value.discountAmount),
    "price" to value.price,
    "created_at" to value.createdAt,
    "updated_at" to value.updatedAt,
    "originPrice" to value.originPrice,
  )

  private fun purchaseLink(value: InappifyPurchaseLink): Map<String, Any?> = linkedMapOf(
    "offering" to value.offering,
    "url" to value.url,
  )

  private fun eventType(value: InappifyEventType): String = when (value) {
    InappifyEventType.STATE_CHANGED -> "stateChanged"
    InappifyEventType.CUSTOMER_INFO_CHANGED -> "customerInfoChanged"
    InappifyEventType.OFFERINGS_CHANGED -> "offeringsChanged"
    InappifyEventType.AUTHENTICATION_CHANGED -> "authenticationChanged"
    InappifyEventType.PURCHASE_UPDATED -> "purchaseUpdated"
  }

  private fun failureCode(value: InappifyErrorCode): String = when (value) {
    InappifyErrorCode.INVALID_CONFIGURATION -> "invalidConfiguration"
    InappifyErrorCode.NOT_CONFIGURED -> "notConfigured"
    InappifyErrorCode.UNAUTHORIZED -> "unauthorized"
    InappifyErrorCode.NETWORK -> "network"
    InappifyErrorCode.REQUEST_CANCELLED -> "requestCancelled"
    InappifyErrorCode.TIMEOUT -> "timeout"
    InappifyErrorCode.STORE_UNAVAILABLE -> "storeUnavailable"
    InappifyErrorCode.PURCHASE_CANCELLED -> "purchaseCancelled"
    InappifyErrorCode.UNSUPPORTED_OPERATION -> "unsupportedOperation"
    InappifyErrorCode.MALFORMED_RESPONSE -> "malformedResponse"
    InappifyErrorCode.PURCHASE_IN_PROGRESS,
    InappifyErrorCode.PURCHASE_VERIFICATION_FAILED,
    InappifyErrorCode.UNKNOWN,
    -> "unknown"
  }

  private fun codecMap(value: Map<*, *>): Map<String, Any?> = buildMap(value.size) {
    value.forEach { (key, item) ->
      if (key is String) put(key, codecValue(item))
    }
  }

  private fun codecValue(value: Any?): Any? = when (value) {
    null, is String, is Boolean, is Int, is Long, is Double -> value
    is Byte, is Short -> (value as Number).toInt()
    is Float -> value.toDouble()
    is Number -> value.toDouble()
    is Map<*, *> -> codecMap(value)
    is Iterable<*> -> value.map(::codecValue)
    is Array<*> -> value.map(::codecValue)
    // SDK metadata is JSON-compatible. Drop an unexpected object instead of
    // invoking an application-defined toString that could expose private data.
    else -> null
  }

  private const val DEFAULT_COUNTRY = "IR"

  /** SDK snapshots use canonical names; Flutter mirrors official backend integers. */
  internal fun storePlatformCode(value: String?): Int? = when (value) {
    "DirectIos" -> 1
    "DirectAndroid" -> 2
    "DirectWeb" -> 3
    "PlayStore" -> 5
    "AppStore" -> 6
    "Bazar" -> 10
    "MyKet" -> 11
    "SibApp" -> 12
    else -> null
  }
}
