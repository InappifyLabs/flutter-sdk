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

  @Test fun go220NullableForceVersionSurvivesProtocolOneCodec() {
    val state = InappifyNativeCodec.snapshot(snapshot(forceVersion = null), hostVersion)
    assertTrue(state.containsKey("forceVersion"))
    assertNull(state["forceVersion"])
    assertNull(state["accessToken"])
    assertNull(InappifyNativeCodec.snapshot(snapshot(), hostVersion)["forceVersion"])
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
    for (name in listOf("configure", "login", "purchase", "confirmDelivery", "restoreStorePurchases", "customerInfoWithPolicy", "goV2"))
      assertTrue(InappifyChannelContract.SUPPORTED_OPERATIONS.contains(name))
  }

  @Test fun officialStorePlatformCodesMatchFlutterIntegerContract() {
    val codes = mapOf("DirectIos" to 1, "DirectAndroid" to 2, "DirectWeb" to 3,
      "PlayStore" to 5, "AppStore" to 6, "Bazar" to 10, "MyKet" to 11, "SibApp" to 12)
    codes.forEach { (name, code) -> assertEquals(code, InappifyNativeCodec.storePlatformCode(name)) }
    assertNull(InappifyNativeCodec.storePlatformCode(null))
    assertNull(InappifyNativeCodec.storePlatformCode("NewStore"))
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
    assertFalse(data.containsKey("hasForceUpdate"))
    assertNull(data["verifiedSessionScope"])
    assertEquals("goV2", (result["snapshot"] as Map<*, *>)["mobileProtocol"])
    assertFalse(data.containsKey("apiKey"))
    assertFalse(data.containsKey("sessionToken"))
  }

  internal class FakeClient(go: Boolean = false, storeCapable: Boolean = false,
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
      add(Class.forName("com.inappify.sdk.TargetingSyncCapableClient"))
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
        "customerInfo", "getCustomerInfo" -> InappifyResult.Success(InappifyCustomerInfo(), snapshot(market = nativeMarket))
        "getOfferings", "syncAttributesAndOfferingsIfNeededInternal" -> InappifyResult.Success(InappifyOfferings(), snapshot(market = nativeMarket))
        "getOffering", "getCurrentOffering" -> InappifyResult.Success(null, snapshot(market = nativeMarket))
        "setAttributes" -> InappifyResult.Success(emptyList<InappifyAttribute>(), snapshot(market = nativeMarket))
        "getDiscountedPaymentLinks" -> InappifyResult.Success(InappifyDiscountCodeResult(isValid = true), snapshot(market = nativeMarket))
        "handleDeepLink" -> args!!.first() == "demo://return?inappify_payment_return=1"
        "syncStorePurchases" -> InappifyResult.Success(if (ownedPurchases) listOf(storePurchase(InappifyStorePurchaseStatus.DELIVERY_REQUIRED, nativeMarket)) else emptyList<InappifyPurchase>(), snapshot(market = nativeMarket))
        "restorePurchasesV2" -> InappifyResult.Success(InappifyRestoreResult(2, 3, 1), snapshot(market = nativeMarket))
        "purchase" -> {
          beforePurchase()
          InappifyResult.Success(storePurchase(InappifyStorePurchaseStatus.DELIVERY_REQUIRED, nativeMarket), snapshot(market = nativeMarket))
        }
        "confirmDeliveryV2" -> InappifyResult.Success(storePurchase(InappifyStorePurchaseStatus.DELIVERY_REQUIRED, nativeMarket), snapshot(market = nativeMarket))
        "syncPendingConsumablesInternal" -> InappifyResult.Success(InappifyConsumableSyncResult(
          1, 0, listOf(InappifyConsumableDelivery(55, "coins", null, if (nativeMarket == InappifyMarket.MYKET) InappifyDeliverySource.MYKET else InappifyDeliverySource.BAZAAR)),
        ), snapshot(market = nativeMarket))
        "configure", "logIn", "logOut" ->
          InappifyResult.Success(Unit, snapshot(market = nativeMarket))
        "toString" -> "SyntheticClient"
        else -> error("Unexpected native call: " + method.name)
      }
    } as InappifyClient
  }

  companion object {
    internal val hostVersion = HostApplicationVersion("1.2.0", 12)
    internal val configurePayload = mapOf<String, Any?>("apiKey" to "synthetic-public-key")
    internal val purchasePayload = mapOf<String, Any?>(
      "packageToPurchase" to mapOf("identifier" to "coins-package", "offeringIdentifier" to "default",
        "product" to mapOf("identifier" to "coins", "productType" to "CONSUMABLE")),
    )

    /** SDK state has no public constructor; reflect a synthetic value only in tests. */
    private fun snapshot(forceVersion: Long? = 1L, market: InappifyMarket = InappifyMarket.BAZAAR): InappifySnapshot {
      val values = mutableListOf<Any?>(7L, true, false, "\$INAAnonymousID:synthetic", market, "IR", "1.2.0",
        "0.1.1", null, 12L, null, null, false, false, if (market == InappifyMarket.MYKET) "MyKet" else "Bazar")
      // Exercise the current SDK and the published dependency without restoring retired state.
      val constructors = InappifySnapshot::class.java.declaredConstructors
      val current = constructors.firstOrNull { it.parameterCount == 15 &&
        it.parameterTypes[10].name == "com.inappify.sdk.InappifyCustomerInfo" }
      val constructor = current ?: constructors.first { it.parameterCount == 16 }.also { values.add(9, forceVersion) }
      return constructor.apply { isAccessible = true }.newInstance(*values.toTypedArray()) as InappifySnapshot
    }

    private fun storePurchase(status: InappifyStorePurchaseStatus, market: InappifyMarket = InappifyMarket.BAZAAR): InappifyPurchase =
      InappifyPurchase::class.java.declaredConstructors.first { it.parameterCount == 14 }
        .apply { isAccessible = true }.newInstance(
          "attempt-1", "coins", "default", market, null, "coins-package",
          null, null, null, null, 9_007_199_254_740_993L, 31L, false, status,
        ) as InappifyPurchase
  }
}
