package com.inappify.inappify_sdk

import com.inappify.sdk.*
import kotlin.test.*
import kotlinx.coroutines.runBlocking

class CurrentApiBridgeTest {
  private val fake = InappifyV2BridgeTest.FakeClient(go = true)
  private val session = InappifyNativeSession { fake.client }
  private val bridge = InappifyNativeBridge(session, InappifyV2BridgeTest.hostVersion)

  private suspend fun invoke(method: String, payload: Map<String, Any?> = emptyMap(), id: String = "r") =
    bridge.invoke(method, id, payload, null)

  @Test fun identityUsesCurrentNamesAndArguments() = runBlocking {
    assertEquals(true, invoke("sdkConfigure", InappifyV2BridgeTest.configurePayload)["ok"])
    assertEquals(true, invoke("sdkLogin", mapOf("appUserIdentifier" to "customer-1"))["ok"])
    assertEquals("customer-1", fake.arguments["logIn"]!!.first())
    assertEquals(true, invoke("sdkLogout")["ok"])
    assertEquals(1, fake.arguments["logOut"]!!.size) // suspend continuation only
  }

  @Test fun allCustomerInfoPoliciesAndTheDefaultReachNative() = runBlocking {
    session.select(MobileProtocol.GO_V2)
    val policies = mapOf("cacheOnly" to InappifyCacheFetchPolicy.CACHE_ONLY,
      "fetchCurrent" to InappifyCacheFetchPolicy.FETCH_CURRENT,
      "notStaleCachedOrCurrent" to InappifyCacheFetchPolicy.NOT_STALE_CACHED_OR_CURRENT,
      "cachedOrFetched" to InappifyCacheFetchPolicy.CACHED_OR_FETCHED)
    for ((wire, policy) in policies) {
      assertEquals(true, invoke("sdkGetCustomerInfo", mapOf("fetchPolicy" to wire))["ok"])
      assertEquals(policy, fake.arguments["getCustomerInfo"]!!.first())
    }
    invoke("sdkGetCustomerInfo")
    assertEquals(InappifyCacheFetchPolicy.CACHED_OR_FETCHED, fake.arguments["getCustomerInfo"]!!.first())
    assertEquals(false, invoke("sdkGetCustomerInfo", mapOf("fetchPolicy" to "unknown"))["ok"])
  }

  @Test fun catalogAttributesAndDiscountUseCurrentNativeEntryPoints() = runBlocking {
    session.select(MobileProtocol.GO_V2)
    for ((method, payload) in listOf("sdkGetOfferings" to emptyMap(),
      "sdkGetCurrentOffering" to mapOf("placementIdentifier" to "home"),
      "sdkGetOffering" to mapOf("identifier" to "special"),
      "sdkSyncAttributesAndOfferingsIfNeeded" to emptyMap())) {
      assertEquals(true, invoke(method, payload)["ok"])
    }
    assertEquals("home", fake.arguments["getCurrentOffering"]!!.first())
    assertEquals("special", fake.arguments["getOffering"]!!.first())
    assertEquals(1, fake.calls.count { it == "syncAttributesAndOfferingsIfNeededInternal" })
    val attributes = mapOf("tier" to "gold", "remove" to null, "\$ip" to "1.2.3.4")
    assertEquals(true, invoke("sdkSetAttributes", mapOf("attributes" to attributes))["ok"])
    assertEquals(attributes, fake.arguments["setAttributes"]!!.first())
    invoke("sdkValidateDiscountCode", mapOf("discountCode" to "SALE"))
    assertEquals("SALE", fake.arguments["getDiscountedPaymentLinks"]!!.first())
    for (removed in listOf("sdkRecover", "sdkRestoreCachedSession", "sdkCheckEntitlement", "sdkSetTargetingContext",
      "sdkQueueAttributes", "sdkFlushAttributes", "sdkSyncAttributes", "sdkDeleteAttributes", "sdkSyncAttributeValues")) {
      assertFalse(removed in InappifyChannelContract.NATIVE_METHODS)
      assertEquals("unsupportedOperation", (invoke(removed)["error"] as Map<*, *>)["code"])
    }
  }

  @Test fun storePurchaseApiKeepsResultsAndDoesNotAdvertiseRecovery() = runBlocking {
    session.select(MobileProtocol.GO_V2)
    assertTrue("syncStorePurchases" in InappifyChannelContract.SUPPORTED_OPERATIONS)
    assertTrue("restoreStorePurchases" in InappifyChannelContract.SUPPORTED_OPERATIONS)
    assertFalse("recover" in InappifyChannelContract.SUPPORTED_OPERATIONS)
    assertFalse("syncPurchases" in InappifyChannelContract.SUPPORTED_OPERATIONS)
    assertFalse("restorePurchases" in InappifyChannelContract.SUPPORTED_OPERATIONS)
    assertEquals(true, invoke("sdkSyncPurchases")["ok"])
    assertEquals(true, invoke("sdkRestorePurchases")["ok"])
    assertEquals(2, fake.calls.count { it == "syncStorePurchases" }) // restore fallback
  }

  @Test fun purchasePreservesPackageContextAttributionAndAttempt() = runBlocking {
    session.select(MobileProtocol.GO_V2)
    val payload = InappifyV2BridgeTest.purchasePayload + mapOf(
      "idempotencyKey" to "attempt-1", "paywallId" to 9L, "paywallRevision" to 7L)
    assertEquals(true, invoke("sdkPurchase", payload, "attempt-1")["ok"])
    val params = fake.arguments["purchase"]!!.first() as InappifyPurchaseParams
    assertEquals("default", params.packageToPurchase.offeringIdentifier)
    assertEquals("coins-package", params.packageToPurchase.identifier)
    assertEquals(InappifyProductType.CONSUMABLE, params.packageToPurchase.product!!.productType)
    assertEquals("attempt-1", params.idempotencyKey)
    assertEquals(9L, params.paywallId); assertEquals(7L, params.paywallRevision)
    val before = fake.calls.count { it == "purchase" }
    assertEquals(false, invoke("sdkPurchase", payload, "different")["ok"])
    assertEquals(before, fake.calls.count { it == "purchase" })
    for (bad in listOf(mapOf("paywallId" to 1.5), mapOf("paywallId" to -1L), mapOf("paywallRevision" to 0L))) {
      assertFailsWith<PayloadException> {
        PayloadReader(InappifyV2BridgeTest.purchasePayload + bad).purchaseParams("a", null)
      }
    }
  }

  @Test fun deepLinksUseNativeMarkerValidation() = runBlocking {
    session.select(MobileProtocol.GO_V2)
    for ((url, accepted) in listOf("demo://ordinary" to false, "demo://return?inappify_payment_return=1" to true)) {
      val result = invoke("sdkHandleDeepLink", mapOf("url" to url))
      assertEquals(accepted, (result["data"] as Map<*, *>)["value"])
      assertEquals(url, fake.arguments["handleDeepLink"]!!.single())
    }
  }
}
