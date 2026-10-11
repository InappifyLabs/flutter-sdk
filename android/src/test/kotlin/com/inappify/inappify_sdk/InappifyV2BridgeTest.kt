package com.inappify.inappify_sdk

import com.inappify.sdk.*
import java.lang.reflect.Proxy
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import kotlin.test.*
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.async
import kotlinx.coroutines.Dispatchers

/** Synthetic boundary tests; no Android Keystore, billing UI, or live HTTP. */
class InappifyV2BridgeTest {
  @Test fun subscriptionRecoveryDefaultsAndOptOutReachNativeConfigureAndCacheRestore() = runBlocking {
    for (method in listOf("sdkConfigure", "sdkRestoreCachedSession")) {
      for (flag in listOf<Map<String, Any?>>(emptyMap(),
          mapOf("enableSubscriptionRecoveryWithoutPayload" to true),
          mapOf("enableSubscriptionRecoveryWithoutPayload" to false))) {
        val fake = FakeClient(cacheCapable = true)
        val bridge = InappifyNativeBridge(InappifyNativeSession { fake.client }, hostVersion)
        val result = bridge.invoke(method, "flag", configurePayload + flag, null)
        assertEquals(true, result["ok"])
        val called = if (method == "sdkConfigure") "configure" else "restoreCachedSessionInternal"
        val options = fake.arguments[called]!!.first() as InappifyOptions
        assertEquals(flag["enableSubscriptionRecoveryWithoutPayload"] ?: true,
          options.enableSubscriptionRecoveryWithoutPayload)
      }
    }
  }

  @Test fun invalidSubscriptionRecoveryFlagsAreRejectedBeforeClientCreation() = runBlocking {
    for (method in listOf("sdkConfigure", "sdkRestoreCachedSession")) {
      for (flag in listOf(null, "false", 0, emptyList<String>(), emptyMap<String, String>())) {
        val fake = FakeClient(cacheCapable = true)
        val created = mutableListOf<MobileProtocol>()
        val bridge = InappifyNativeBridge(InappifyNativeSession { mode ->
          created.add(mode); fake.client
        }, hostVersion)
        val result = bridge.invoke(method, "invalid-flag", configurePayload + mapOf(
          "enableSubscriptionRecoveryWithoutPayload" to flag), null)
        assertEquals(false, result["ok"])
        assertEquals("invalidConfiguration", (result["error"] as Map<*, *>)["code"])
        assertTrue(created.isEmpty())
        assertTrue(fake.calls.isEmpty())
      }
    }
  }

  @Test fun myketUsesNativeConfigurePurchaseAndRecoveryForBothProtocols() = runBlocking {
    for (protocol in MobileProtocol.values()) {
      val fake = FakeClient(go = protocol == MobileProtocol.GO_V2, storeCapable = true,
        nativeMarket = InappifyMarket.MYKET, ownedPurchases = true)
      val bridge = InappifyNativeBridge(InappifyNativeSession { fake.client }, hostVersion)
      val configured = bridge.invoke("sdkConfigure", "configure", configurePayload + mapOf(
        "market" to "myket", "marketKey" to "synthetic-myket-key", "mobileProtocol" to protocol.wireName,
      ), null)
      assertEquals(true, configured["ok"])
      val options = fake.arguments["configure"]!!.first() as InappifyOptions
      assertEquals(InappifyMarket.MYKET, options.market)
      assertEquals("synthetic-myket-key", options.marketKey)
      assertEquals("myket", (configured["snapshot"] as Map<*, *>)["market"])
      assertEquals(11, (configured["snapshot"] as Map<*, *>)["storePlatform"])
      for (type in listOf(null, "CONSUMABLE", "NON_CONSUMABLE")) {
        val payload = purchasePayload + mapOf("market" to "myket", "idempotencyKey" to "attempt-1") +
          if (type == null) emptyMap() else mapOf("productType" to type)
        val purchased = bridge.invoke("sdkPurchase", "attempt-1", payload, null)
        assertEquals(true, purchased["ok"])
        val request = fake.arguments["purchase"]!!.first() as InappifyPurchaseRequest
        assertEquals(InappifyMarket.MYKET, request.market)
        assertEquals(type, request.productType?.name)
        assertEquals("attempt-1", request.idempotencyKey)
        assertEquals("myket", ((purchased["data"] as Map<*, *>)["mobile"] as Map<*, *>)["market"])
      }
      val pending = bridge.invoke("sdkSyncPendingConsumables", "pending", emptyMap(), null)
      val deliveries = (pending["data"] as Map<*, *>)["pendingDeliveries"] as List<*>
      assertEquals("MYKET", (deliveries.single() as Map<*, *>)["source"])
      assertFalse(fake.calls.contains("confirmDeliveryV2"))
      val confirmed = bridge.invoke("sdkConfirmDelivery", "confirm", mapOf("deliveryId" to 9007199254740993L), null)
      assertEquals(9007199254740993L, fake.arguments["confirmDeliveryV2"]!!.first())
      assertEquals("myket", ((confirmed["data"] as Map<*, *>)["mobile"] as Map<*, *>)["market"])
      val synced = bridge.invoke("sdkSyncPurchases", "sync", emptyMap(), null)
      val purchases = (synced["data"] as Map<*, *>)["purchases"] as List<*>
      assertEquals("myket", ((purchases.single() as Map<*, *>)["mobile"] as Map<*, *>)["market"])
      assertEquals(true, bridge.invoke("sdkRestorePurchases", "restore", emptyMap(), null)["ok"])
    }
  }

  @Test fun myketCacheRestoreKeepsStoreIdentity() = runBlocking {
    val fake = FakeClient(cacheCapable = true, nativeMarket = InappifyMarket.MYKET)
    val bridge = InappifyNativeBridge(InappifyNativeSession { fake.client }, hostVersion)
    val restored = bridge.invoke("sdkRestoreCachedSession", "cache", configurePayload + mapOf(
      "market" to "myket", "marketKey" to "synthetic-myket-key",
    ), null)
    assertEquals(true, restored["ok"])
    assertEquals(InappifyMarket.MYKET,
      (fake.arguments["restoreCachedSessionInternal"]!!.first() as InappifyOptions).market)
    assertEquals("myket", (restored["snapshot"] as Map<*, *>)["market"])
    assertFalse(fake.calls.contains("configure"))
    assertFalse(fake.calls.contains("purchase"))
  }

  @Test fun removedLegacyBindingNeverCreatesOrConfiguresACompanion() = runBlocking {
    val fake = FakeClient(go = true)
    val created = mutableListOf<MobileProtocol>()
    val session = InappifyNativeSession { mode -> created.add(mode); fake.client }
    session.select(MobileProtocol.GO_V2)
    val result = InappifyNativeBridge(session, hostVersion).invoke(
      "sdkBindLegacyPurchaseClient", "bind", mapOf("legacyOptions" to configurePayload), null,
    )
    assertEquals(false, result["ok"])
    val error = result["error"] as Map<*, *>
    assertEquals("unsupportedOperation", error["code"])
    assertEquals(listOf(MobileProtocol.GO_V2), created)
    assertFalse(fake.calls.contains("configure"))
    assertFalse(fake.calls.contains("bindLegacyPurchaseClient"))
  }

  @Test fun go220PurchaseDelegatesWithoutConstructingALegacyCompanion() = runBlocking {
    val fake = FakeClient(go = true)
    val created = mutableListOf<MobileProtocol>()
    val session = InappifyNativeSession { mode -> created.add(mode); fake.client }
    session.select(MobileProtocol.GO_V2)
    val result = InappifyNativeBridge(session, hostVersion).invoke(
      "sdkPurchase", "attempt-1", purchasePayload + mapOf(
        "idempotencyKey" to "attempt-1", "paywallId" to 17L, "paywallRevision" to 2L,
      ), null,
    )
    assertEquals(true, result["ok"])
    assertEquals(listOf(MobileProtocol.GO_V2), created)
    assertFalse(fake.calls.contains("configure"))
    assertFalse(fake.calls.contains("bindLegacyPurchaseClient"))
    val request = fake.arguments["purchase"]?.first() as InappifyPurchaseRequest
    assertEquals(17L, request.paywallId)
    assertEquals(2L, request.paywallRevision)
  }

  @Test fun go220NullableForceVersionSurvivesProtocolOneCodec() {
    val state = InappifyNativeCodec.snapshot(snapshot(forceVersion = null), hostVersion)
    assertTrue(state.containsKey("forceVersion"))
    assertNull(state["forceVersion"])
    assertNull(state["accessToken"])
    assertEquals(1L, InappifyNativeCodec.snapshot(snapshot(), hostVersion)["forceVersion"])
  }

  @Test fun go220NumericAndUnicodeIdentitiesReachNativeWithoutRewriting() = runBlocking {
    for (identity in listOf("1", "123456789", "کاربر-۱۲۳", "😀".repeat(100))) {
      val fake = FakeClient(go = true)
      val session = InappifyNativeSession { fake.client }
      val result = InappifyNativeBridge(session, hostVersion).invoke(
        "sdkConfigure", "identity", configurePayload + mapOf(
          "mobileProtocol" to "goV2", "appUserIdentifier" to identity,
        ), null,
      )
      assertEquals(true, result["ok"])
      assertEquals(identity, (fake.arguments["configure"]!!.first() as InappifyOptions).appUserIdentifier)
    }
  }

  @Test fun cacheRestoreDelegatesToOptionalCapabilityWithoutConfigureOrBilling() = runBlocking {
    for (hit in listOf(true, false)) {
      val fake = FakeClient(cacheCapable = true, cacheHit = hit)
      val session = InappifyNativeSession { fake.client }
      val bridge = InappifyNativeBridge(session, hostVersion)
      val payload = configurePayload + mapOf("appUserIdentifier" to "fixture-user", "country" to "IR", "appVersion" to "2.1.0")
      val response = bridge.invoke("sdkRestoreCachedSession", "restore-1", payload, null)
      assertEquals(true, response["ok"])
      assertEquals(mapOf("value" to hit), response["data"])
      val options = fake.arguments["restoreCachedSessionInternal"]?.first() as InappifyOptions
      assertEquals("fixture-user", options.appUserIdentifier)
      assertEquals("IR", options.country)
      assertEquals("2.1.0", options.appVersion)
      assertFalse(fake.calls.contains("configure"))
      assertFalse(fake.calls.contains("purchase"))
      assertFalse(fake.calls.contains("syncPurchases"))
    }
    assertTrue(InappifyChannelContract.NATIVE_METHODS.contains("sdkRestoreCachedSession"))
    assertFalse(InappifyChannelContract.SUPPORTED_OPERATIONS.contains("restoreCachedSession"))
  }

  @Test fun v2CacheRestoreIsNotAdvertisedAndNeverFallsBackToConfigure() = runBlocking {
    assertFalse(InappifyChannelContract.SUPPORTED_OPERATIONS.contains("restoreCachedSession"))
    assertTrue(InappifyChannelContract.NATIVE_METHODS.contains("sdkRestoreCachedSession"))
    val fake = FakeClient(go = true)
    val bridge = InappifyNativeBridge(InappifyNativeSession { fake.client }, hostVersion)
    val response = bridge.invoke("sdkRestoreCachedSession", "r", configurePayload, null)
    assertEquals(false, response["ok"])
    assertEquals("unsupportedOperation", (response["error"] as Map<*, *>)["code"])
    assertFalse(fake.calls.contains("configure"))
    assertFalse(fake.calls.contains("purchase"))
    assertFalse(fake.calls.contains("recover"))
  }

  @Test fun omittedProtocolUsesV2FactoryAndReusesOneClient() {
    val fake = FakeClient()
    val created = mutableListOf<MobileProtocol>()
    val session = InappifyNativeSession { mode -> created.add(mode); fake.client }
    assertSame(fake.client, session.select(MobileProtocol.fromWire(null)))
    assertSame(fake.client, session.select(MobileProtocol.GO_V2))
    assertEquals(listOf(MobileProtocol.GO_V2), created)
    assertSame(fake.client, session.select(MobileProtocol.GO_V2))
    assertEquals(1, created.size)
  }

  @Test fun invalidProtocolNeverFallsBackToLegacy() {
    listOf("legacyV1", "", "v2", 2, true).forEach { value ->
      assertFailsWith<NativeSessionException> { MobileProtocol.fromWire(value) }
    }
  }

  @Test fun configureModeChangeFailsBeforeSecondFactoryOrConfigureCall() = runBlocking {
    val fake = FakeClient()
    var creations = 0
    val session = InappifyNativeSession { creations++; fake.client }
    val bridge = InappifyNativeBridge(session, hostVersion)
    assertEquals(true, bridge.invoke("sdkConfigure", "c1", configurePayload, null)["ok"])
    val switched = bridge.invoke("sdkConfigure", "c2", configurePayload + ("mobileProtocol" to "legacyV1"), null)
    assertEquals(false, switched["ok"])
    assertEquals("invalidConfiguration", (switched["error"] as Map<*, *>)["code"])
    assertEquals(1, creations)
    assertEquals(1, fake.calls.count { it == "configure" })
  }

  @Test fun engineObserversBeforeConfigureAttachOnceAndUnsubscribeIndependently() {
    val fake = FakeClient()
    val session = InappifyNativeSession { fake.client }
    var attached = 0
    var removed = 0
    fun subscribe(): AutoCloseable = session.observe {
      attached++
      AutoCloseable { removed++ }
    }
    val first = subscribe()
    val second = subscribe()
    assertEquals(0, attached)
    session.select(MobileProtocol.GO_V2)
    session.select(MobileProtocol.GO_V2)
    assertEquals(2, attached)
    first.close()
    assertEquals(1, removed)
    session.close()
    second.close()
    session.close()
    assertEquals(2, removed)
    assertEquals(1, fake.calls.count { it == "close" })
  }

  @Test fun observerRemovedBeforeSelectionNeverAttaches() {
    val session = InappifyNativeSession { FakeClient().client }
    var attached = false
    session.observe { attached = true; AutoCloseable {} }.close()
    session.select(MobileProtocol.GO_V2)
    assertFalse(attached)
  }

  @Test fun diagnosticsAndStateObserveOneV2Client() {
    val session = InappifyNativeSession { mode -> FakeClient(go = mode == MobileProtocol.GO_V2).client }
    var diagnosticSources = 0
    var stateSources = 0
    var removed = 0
    val diagnostics = session.observe {
      diagnosticSources++; AutoCloseable { removed++ }
    }
    session.observe { stateSources++; AutoCloseable {} }
    session.select(MobileProtocol.GO_V2)
    assertEquals(1, diagnosticSources)
    session.select(MobileProtocol.GO_V2)
    session.select(MobileProtocol.GO_V2)
    assertEquals(1, diagnosticSources)
    assertEquals(1, stateSources)
    diagnostics.close()
    session.close()
    assertEquals(1, removed)
  }

  @Test fun legacyPurchaseRequestKeepsNullProductTypeAndCallerMarket() {
    for (market in listOf("none", "bazar")) {
      val request = PayloadReader(purchasePayload + ("market" to market)).purchaseRequest("attempt-1")
      assertNull(request.productType)
      assertEquals(if (market == "none") InappifyMarket.NONE else InappifyMarket.BAZAAR, request.market)
      assertEquals("attempt-1", request.idempotencyKey)
    }
  }

  @Test fun allExplicitProductTypesUseTypedConstructorWithoutChangingRequestedFallback() {
    for (type in InappifyProductType.values()) {
      val request = PayloadReader(purchasePayload + ("productType" to type.name)).purchaseRequest("attempt-1")
      assertEquals(type, request.productType)
      assertEquals(InappifyMarket.NONE, request.market)
    }
    assertFailsWith<PayloadException> {
      PayloadReader(purchasePayload + ("productType" to "consumable")).purchaseRequest("attempt-1")
    }
  }

  @Test fun optionalAttributionMustBeAnExactPositivePairAndPreservesLegacyType() {
    val request = PayloadReader(purchasePayload + mapOf(
      "paywallId" to 17L, "paywallRevision" to 2, "dynamicPriceToken" to "synthetic-price-token",
    )).purchaseRequest("attempt-1")
    assertEquals(17L, request.paywallId)
    assertEquals(2L, request.paywallRevision)
    assertEquals("synthetic-price-token", request.dynamicPriceToken)
    assertNull(request.productType)
    for (values in listOf(
      mapOf("paywallId" to 1), mapOf("paywallRevision" to 1),
      mapOf("paywallId" to 0, "paywallRevision" to 1),
      mapOf("paywallId" to 1.5, "paywallRevision" to 1),
    )) assertFailsWith<PayloadException> { PayloadReader(purchasePayload + values).purchaseRequest("a") }
  }

  @Test fun v2PurchaseMetadataIsNestedWithoutInventingLegacyDone() {
    val value = storePurchase(InappifyStorePurchaseStatus.DELIVERY_REQUIRED)
    val result = InappifyNativeCodec.purchase(value)
    assertNull(result["purchaseStatus"])
    val mobile = result["mobile"] as Map<*, *>
    assertEquals("DELIVERY_REQUIRED", mobile["storePurchaseStatus"])
    assertEquals(9_007_199_254_740_993L, mobile["deliveryId"])
    assertEquals("31", mobile["verificationRequestId"])
    assertEquals(false, mobile["alreadyProcessed"])
    assertEquals("attempt-1", mobile["idempotencyKey"])
    assertEquals("bazar", mobile["market"])
    assertFalse(result.containsKey("purchaseToken"))
  }

  @Test fun partialRestoreAndPendingDeliveriesRemainExplicit() {
    assertEquals(mapOf("restoredCount" to 2, "alreadyProcessedCount" to 1,
      "failedCount" to 3, "totalCount" to 6), InappifyNativeCodec.restore(InappifyRestoreResult(2, 1, 3)))
    val pending = InappifyConsumableDelivery(99, "coins", "transaction-1", InappifyDeliverySource.DIRECT)
    val encoded = InappifyNativeCodec.consumableSync(InappifyConsumableSyncResult(2, 1, listOf(pending)))
    assertEquals(2, encoded["discoveredCount"])
    assertEquals(1, encoded["completedCount"])
    assertEquals(listOf(InappifyNativeCodec.delivery(pending)), encoded["pendingDeliveries"])
  }

  @Test fun snapshotReportsNativeIdentityAndFlagsWithoutCredentialsOrDurabilityClaim() {
    val state = InappifyNativeCodec.snapshot(snapshot(), hostVersion)
    assertEquals(7L, state["revision"])
    assertEquals(true, state["isConfigured"])
    assertEquals(false, state["isAuthenticated"])
    assertEquals("anonymous", state["sessionState"])
    assertEquals("unknown", state["persistenceMode"])
    assertEquals(10, state["storePlatform"])
    assertNull(state["accessToken"])
    assertNull(state["apiKey"])
  }

  @Test fun cachePolicyMappingIsStrictAndComplete() {
    val names = listOf("cacheOnly", "cacheFirst", "networkFirst", "networkOnly")
    names.zip(InappifyFetchPolicy.values()).forEach { (name, expected) ->
      assertEquals(expected, PayloadReader(mapOf("policy" to name)).fetchPolicy())
    }
    assertFailsWith<PayloadException> { PayloadReader(mapOf("policy" to "NETWORK_ONLY")).fetchPolicy() }
  }

  @Test fun writeOnlyAttributesRejectUnexpectedValuesAndMapKeys() {
    assertEquals(mapOf("name" to "", "deleted" to null),
      PayloadReader(mapOf("values" to mapOf("name" to "", "deleted" to null))).stringValues("values"))
    assertFailsWith<PayloadException> { PayloadReader(mapOf("values" to mapOf("count" to 1))).stringValues("values") }
    assertFailsWith<PayloadException> { PayloadReader(mapOf("values" to mapOf(1 to "a"))).stringValues("values") }
  }

  @Test fun goOnlyOperationsFailClosedOnUnsupportedCustomClient() = runBlocking {
    val fake = FakeClient()
    val session = InappifyNativeSession { fake.client }
    session.select(MobileProtocol.GO_V2)
    val bridge = InappifyNativeBridge(session, hostVersion)
    for (method in listOf("sdkRecover", "sdkFlushAttributes", "sdkSetNetworkEnabled", "sdkV2CustomerInfo")) {
      val result = bridge.invoke(method, "r", mapOf("enabled" to false, "policy" to "cacheOnly"), null)
      assertEquals("unsupportedOperation", (result["error"] as Map<*, *>)["code"])
    }
    assertFalse(fake.calls.contains("configure"))
  }

  @Test fun invalidDeliveryIdsFailBeforeAnyNativeConfirmation() = runBlocking {
    val fake = FakeClient()
    val session = InappifyNativeSession { fake.client }
    session.select(MobileProtocol.GO_V2)
    val bridge = InappifyNativeBridge(session, hostVersion)
    for (value in listOf(0, -1, 1.0, 1.5, Double.NaN, Long.MAX_VALUE.toDouble(), "1")) {
      val result = bridge.invoke("sdkConfirmDelivery", "r", mapOf("deliveryId" to value), null)
      assertEquals("invalidConfiguration", (result["error"] as Map<*, *>)["code"])
    }
  }

  @Test fun goResourceQueueAndNetworkCallsDelegateWithExactInputs() = runBlocking {
    val fake = FakeClient(go = true)
    val session = InappifyNativeSession { fake.client }
    session.select(MobileProtocol.GO_V2)
    val bridge = InappifyNativeBridge(session, hostVersion)
    assertEquals(true, bridge.invoke("sdkQueueAttributes", "r", mapOf("values" to mapOf("name" to "demo")), null)["ok"])
    assertEquals(mapOf("name" to "demo"), fake.arguments["queueAttributes"]?.first())
    assertEquals(true, bridge.invoke("sdkSetNetworkEnabled", "r", mapOf("enabled" to false), null)["ok"])
    assertEquals(false, fake.arguments["setNetworkEnabled"]?.first())
    assertEquals(true, bridge.invoke("sdkV2CustomerInfo", "r", mapOf("policy" to "cacheOnly"), null)["ok"])
    assertEquals(InappifyFetchPolicy.CACHE_ONLY, fake.arguments["customerInfo"]?.first())
  }

  @Test fun bindingMismatchedIdentityDoesNotCreateOrConfigureLegacyClient() = runBlocking {
    val fake = FakeClient(go = true)
    var creations = 0
    val session = InappifyNativeSession { creations++; fake.client }
    session.select(MobileProtocol.GO_V2)
    val bridge = InappifyNativeBridge(session, hostVersion)
    val result = bridge.invoke("sdkBindLegacyPurchaseClient", "r", mapOf(
      "legacyOptions" to (configurePayload + ("appUserIdentifier" to "different_customer")),
    ), null)
    assertEquals("unsupportedOperation", (result["error"] as Map<*, *>)["code"])
    assertEquals(1, creations)
    assertFalse(fake.calls.contains("configure"))
    assertFalse(fake.calls.contains("bindLegacyPurchaseClient"))
  }

  @Test fun newCapabilitiesAreAdditiveAndWireProtocolIsStillOne() {
    assertEquals(1, InappifyChannelContract.PROTOCOL_VERSION)
    assertEquals("inappify_sdk/events/v1", InappifyChannelContract.EVENT_CHANNEL_NAME)
    assertEquals("inappify_sdk/http/v2", InappifyChannelContract.HTTP_EVENT_CHANNEL_NAME)
    for (name in listOf("configure", "login", "purchase", "confirmDelivery", "restorePurchases", "customerInfoWithPolicy", "goV2"))
      assertTrue(InappifyChannelContract.SUPPORTED_OPERATIONS.contains(name))
  }

  @Test fun officialStorePlatformCodesMatchFlutterIntegerContract() {
    val codes = mapOf("DirectIos" to 1, "DirectAndroid" to 2, "DirectWeb" to 3,
      "PlayStore" to 5, "AppStore" to 6, "Bazar" to 10, "MyKet" to 11, "SibApp" to 12)
    codes.forEach { (name, code) -> assertEquals(code, InappifyNativeCodec.storePlatformCode(name)) }
    assertNull(InappifyNativeCodec.storePlatformCode(null))
    assertNull(InappifyNativeCodec.storePlatformCode("NewStore"))
  }

  @Test fun purchaseBridgePreservesTypedRequestAndRejectsCorrelationMismatchBeforePurchase() = runBlocking {
    val fake = FakeClient()
    val session = InappifyNativeSession { fake.client }
    session.select(MobileProtocol.GO_V2)
    val bridge = InappifyNativeBridge(session, hostVersion)
    val payload = purchasePayload + mapOf("productType" to "SUBSCRIPTION", "idempotencyKey" to "retry-7")
    assertEquals(true, bridge.invoke("sdkPurchase", "retry-7", payload, null)["ok"])
    val request = fake.arguments["purchase"]?.first() as InappifyPurchaseRequest
    assertEquals(InappifyProductType.SUBSCRIPTION, request.productType)
    assertEquals("retry-7", request.idempotencyKey)
    val failed = bridge.invoke("sdkPurchase", "different", payload, null)
    assertEquals("invalidConfiguration", (failed["error"] as Map<*, *>)["code"])
    assertEquals(1, fake.calls.count { it == "purchase" })
  }

  @Test fun concurrentEnginesCannotQueueASecondPaidPurchaseBehindTheFirst() = runBlocking {
    val entered = CountDownLatch(1)
    val release = CountDownLatch(1)
    val fake = FakeClient(beforePurchase = {
      entered.countDown()
      check(release.await(5, TimeUnit.SECONDS))
    })
    val session = InappifyNativeSession { fake.client }
    session.select(MobileProtocol.GO_V2)
    val firstBridge = InappifyNativeBridge(session, hostVersion)
    val secondBridge = InappifyNativeBridge(session, hostVersion)
    val first = async(Dispatchers.Default) {
      firstBridge.invoke("sdkPurchase", "p1", purchasePayload + ("idempotencyKey" to "p1"), null)
    }
    try {
      assertTrue(entered.await(5, TimeUnit.SECONDS))
      val rejected = secondBridge.invoke("sdkPurchase", "p2", purchasePayload + ("idempotencyKey" to "p2"), null)
      assertEquals(false, rejected["ok"])
      val error = rejected["error"] as Map<*, *>
      assertEquals("PURCHASE_IN_PROGRESS", (error["details"] as Map<*, *>)["nativeCode"])
    } finally { release.countDown() }
    assertEquals(true, first.await()["ok"])
    assertEquals(1, fake.calls.count { it == "purchase" })
  }

  @Test fun manualFulfillmentAndRestoreDelegateWithoutGrantingOrRewritingDeliveryId() = runBlocking {
    val fake = FakeClient(storeCapable = true)
    val session = InappifyNativeSession { fake.client }
    session.select(MobileProtocol.GO_V2)
    val bridge = InappifyNativeBridge(session, hostVersion)
    val pending = bridge.invoke("sdkSyncPendingConsumables", "sync", emptyMap(), null)
    assertEquals(true, pending["ok"])
    assertEquals(1, (pending["data"] as Map<*, *>)["discoveredCount"])
    assertFalse(fake.calls.contains("confirmDeliveryV2"))
    val confirmed = bridge.invoke("sdkConfirmDelivery", "ack", mapOf("deliveryId" to 9_007_199_254_740_993L), null)
    assertEquals(true, confirmed["ok"])
    assertEquals(9_007_199_254_740_993L, fake.arguments["confirmDeliveryV2"]?.first())
    val restored = bridge.invoke("sdkRestorePurchases", "restore", emptyMap(), null)
    assertEquals(1, (restored["data"] as Map<*, *>)["failedCount"])
    val synced = bridge.invoke("sdkSyncPurchases", "sync", emptyMap(), null)
    assertEquals(emptyList<Any>(), (synced["data"] as Map<*, *>)["purchases"])
  }

  @Test fun goConfigurationAndSnapshotExposeOnlyNonSecretRuntimeFlags() = runBlocking {
    val fake = FakeClient(go = true)
    val session = InappifyNativeSession { fake.client }
    session.select(MobileProtocol.GO_V2)
    val result = InappifyNativeBridge(session, hostVersion).invoke("sdkGetConfiguration", "r", emptyMap(), null)
    val data = result["data"] as Map<*, *>
    assertEquals("goV2", data["mobileProtocol"])
    assertEquals(false, data["isLogoutPending"])
    assertEquals(false, data["hasForceUpdate"])
    assertNull(data["verifiedSessionScope"])
    assertEquals("goV2", (result["snapshot"] as Map<*, *>)["mobileProtocol"])
    assertFalse(data.containsKey("apiKey"))
    assertFalse(data.containsKey("sessionToken"))
  }

  private class FakeClient(go: Boolean = false, storeCapable: Boolean = false,
    cacheCapable: Boolean = false, cacheHit: Boolean = true,
    nativeMarket: InappifyMarket = InappifyMarket.BAZAAR, ownedPurchases: Boolean = false, beforePurchase: () -> Unit = {}) {
    val calls = mutableListOf<String>()
    val arguments = mutableMapOf<String, List<Any?>>()
    private val interfaces = buildList<Class<*>> {
      add(if (go) InappifyV2Client::class.java else InappifyClient::class.java)
      if (storeCapable) {
        add(Class.forName("com.inappify.sdk.StoreV2CapableClient"))
        add(Class.forName("com.inappify.sdk.ConsumableFulfillmentCapableClient"))
      }
      if (cacheCapable) add(Class.forName("com.inappify.sdk.CachedSessionCapableClient"))
    }
    val client = Proxy.newProxyInstance(InappifyClient::class.java.classLoader,
      interfaces.toTypedArray()) { _, method, args ->
      calls.add(method.name)
      arguments[method.name] = args?.toList().orEmpty()
      when (method.name) {
        "getSnapshot" -> snapshot(market = nativeMarket)
        "restoreCachedSessionInternal" -> InappifyResult.Success(cacheHit, snapshot(market = nativeMarket))
        "close", "setNetworkEnabled" -> null
        "getHasForceUpdate", "isLogoutPending", "getIsLogoutPending" -> false
        "customerInfo" -> InappifyResult.Success(InappifyCustomerInfo(), snapshot(market = nativeMarket))
        "syncPurchases" -> InappifyResult.Success(if (ownedPurchases) listOf(storePurchase(InappifyStorePurchaseStatus.DELIVERY_REQUIRED, nativeMarket)) else emptyList<InappifyPurchase>(), snapshot(market = nativeMarket))
        "restorePurchasesV2" -> InappifyResult.Success(InappifyRestoreResult(2, 3, 1), snapshot(market = nativeMarket))
        "purchase" -> {
          beforePurchase()
          InappifyResult.Success(storePurchase(InappifyStorePurchaseStatus.DELIVERY_REQUIRED, nativeMarket), snapshot(market = nativeMarket))
        }
        "confirmDeliveryV2" -> InappifyResult.Success(storePurchase(InappifyStorePurchaseStatus.DELIVERY_REQUIRED, nativeMarket), snapshot(market = nativeMarket))
        "syncPendingConsumablesInternal" -> InappifyResult.Success(InappifyConsumableSyncResult(
          1, 0, listOf(InappifyConsumableDelivery(55, "coins", null, if (nativeMarket == InappifyMarket.MYKET) InappifyDeliverySource.MYKET else InappifyDeliverySource.BAZAAR)),
        ), snapshot(market = nativeMarket))
        "configure", "queueAttributes", "flushAttributes", "recover" ->
          InappifyResult.Success(Unit, snapshot(market = nativeMarket))
        "toString" -> "SyntheticClient"
        else -> error("Unexpected native call: " + method.name)
      }
    } as InappifyClient
  }

  companion object {
    private val hostVersion = HostApplicationVersion("1.2.0", 12)
    private val configurePayload = mapOf<String, Any?>("apiKey" to "synthetic-public-key")
    private val purchasePayload = mapOf<String, Any?>(
      "productIdentifier" to "coins", "offeringIdentifier" to "default", "discount" to 0,
      "isCrypto" to false, "market" to "none", "isLostPurchase" to false,
    )

    /** SDK state has no public constructor; reflect a synthetic value only in tests. */
    private fun snapshot(forceVersion: Long? = 1L, market: InappifyMarket = InappifyMarket.BAZAAR): InappifySnapshot = InappifySnapshot::class.java.declaredConstructors
      .first { it.parameterCount == 16 }.apply { isAccessible = true }.newInstance(
        7L, true, false, "\$INAAnonymousID:synthetic", market, "IR", "1.2.0",
        "0.1.0", null, forceVersion, 12L, null, null, false, false, if (market == InappifyMarket.MYKET) "MyKet" else "Bazar",
      ) as InappifySnapshot

    private fun storePurchase(status: InappifyStorePurchaseStatus, market: InappifyMarket = InappifyMarket.BAZAAR): InappifyPurchase =
      InappifyPurchase::class.java.declaredConstructors.first { it.parameterCount == 14 }
        .apply { isAccessible = true }.newInstance(
          "attempt-1", "coins", "default", market, null, "coins-package",
          null, null, null, null, 9_007_199_254_740_993L, 31L, false, status,
        ) as InappifyPurchase
  }
}
