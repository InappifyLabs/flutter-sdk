package com.inappify.inappify_sdk

import com.inappify.sdk.InappifyAttribute
import com.inappify.sdk.InappifyCustomerInfo
import com.inappify.sdk.InappifyDiscountCodeResult
import com.inappify.sdk.InappifyEntitlement
import com.inappify.sdk.InappifyMarket
import com.inappify.sdk.InappifyOffering
import com.inappify.sdk.InappifyPackage
import com.inappify.sdk.InappifyPrice
import com.inappify.sdk.InappifyPurchase
import com.inappify.sdk.InappifyPurchaseLink
import com.inappify.sdk.InappifyPurchaseStatus
import com.inappify.sdk.InappifyStoreProduct
import com.inappify.sdk.InappifyTransaction
import kotlin.test.Test
import kotlin.test.assertEquals

internal class InappifyNativeCodecTest {
  @Test
  fun serverOfferingSelectionSurvivesTheNativeBridge() {
    // Construct the SDK's immutable server model without exposing an extra SDK factory.
    val constructors = com.inappify.sdk.InappifyOfferings::class.java.declaredConstructors
    val current = constructors.firstOrNull { it.parameterCount == 6 && it.parameterTypes.last() == Boolean::class.javaPrimitiveType }
    val constructor = current ?: constructors.single { it.parameterCount == 7 && it.parameterTypes.last() == Boolean::class.javaPrimitiveType }
    val values = mutableListOf<Any?>(
      listOf(InappifyOffering(identifier = "default", isDefault = true),
        InappifyOffering(identifier = "family")),
      null, null, "family", mapOf("home" to "family", "empty" to null), true,
    )
    if (current == null) values.add(2, 77L)
    val value = constructor.apply { isAccessible = true }.newInstance(*values.toTypedArray()) as com.inappify.sdk.InappifyOfferings
    val encoded = InappifyNativeCodec.offerings(value)
    assertEquals("family", encoded["currentOffering"])
    assertEquals(mapOf("home" to "family", "empty" to null), encoded["placements"])
    assertEquals(true, encoded["usesServerTargeting"])
    assertEquals(null, encoded["forceVersion"])
  }

  @Test
  fun customerInfoPreservesTheFlutterCustomerWireFormat() {
    val customer = InappifyCustomerInfo(
      originalAppUserId = "customer-42",
      firstSeen = "2026-08-01T10:00:00Z",
      requestDate = "2026-08-30T12:00:00Z",
      latestExpirationDate = "2026-09-30T12:00:00Z",
      hasUsedTrial = true,
      entitlements = listOf(
        InappifyEntitlement(
          identifier = "premium",
          isActive = true,
          isSandbox = false,
          periodType = "NORMAL",
          purchaseDate = "2026-08-30T11:00:00Z",
          expirationDate = "2026-09-30T11:00:00Z",
          ownershipType = "PURCHASED",
          entitlementType = "SUBSCRIPTION",
          purchaseStoreRefHash = "store-ref-hash",
          purchaseStoreTime = 1_777_777_777_000L,
        ),
      ),
      transactions = listOf(
        InappifyTransaction(
          number = "transaction-7",
          status = 1L,
          amount = 120_000L,
          transactionDate = "2026-08-30T11:00:00Z",
          trackingNumber = "tracking-9",
          isCryptoGate = false,
          packageName = "monthly",
          storePurchaseRefId = "store-purchase-3",
          isTrial = true,
        ),
      ),
      attributes = listOf(InappifyAttribute(key = "segment", value = "loyal")),
    )

    assertEquals(
      linkedMapOf(
        "originalAppUserId" to "customer-42",
        "firstSeen" to "2026-08-01T10:00:00Z",
        "requestDate" to "2026-08-30T12:00:00Z",
        "latestExpirationDate" to "2026-09-30T12:00:00Z",
        "entitlements" to listOf(
          linkedMapOf(
            "identifier" to "premium",
            "is_active" to true,
            "is_sandbox" to false,
            "period_type" to "NORMAL",
            "purchase_date" to "2026-08-30T11:00:00Z",
            "expiration_date" to "2026-09-30T11:00:00Z",
            "ownership_type" to "PURCHASED",
            "entitlement_type" to "SUBSCRIPTION",
            "purchase_store_ref_hash" to "store-ref-hash",
            "purchase_store_time" to 1_777_777_777_000L,
          ),
        ),
        "transactions" to listOf(
          linkedMapOf(
            "number" to "transaction-7",
            "status" to 1L,
            "amount" to 120_000L,
            "transactionDate" to "2026-08-30T11:00:00Z",
            "trackingNumber" to "tracking-9",
            "isCryptoGate" to false,
            "packageName" to "monthly",
            "storePurchaseRefId" to "store-purchase-3",
            "isTrial" to true,
          ),
        ),
        "attributes" to listOf(
          linkedMapOf(
            "key" to "segment",
            "value" to "loyal",
          ),
        ),
        "hasUsedTrial" to true,
      ),
      InappifyNativeCodec.customerInfo(customer).filterKeys { it != "entitlementEvaluationTimeMillis" },
    )
  }

  @Test
  fun offeringPreservesPackagesPricesMetadataAndOpaquePaywall() {
    val metadata = linkedMapOf<String, Any?>(
      "campaign" to "summer",
      "segments" to listOf(1L, "new", mapOf("score" to 1.5)),
    )
    val paywall = linkedMapOf<String, Any?>(
      "template" to "hero",
      "sections" to listOf(mapOf("title" to "Upgrade", "order" to 2L)),
      "enabled" to true,
      "footer" to null,
    )
    val offering = InappifyOffering(
      identifier = "main",
      isDefault = true,
      serverDescription = "Main subscription offering",
      trialDays = 7L,
      metadata = metadata,
      packages = listOf(
        InappifyPackage(
          identifier = "monthly-package",
          packageType = 2L,
          description = "Monthly access",
          entitlement = "premium",
          name = "Monthly",
          discountPercent = 25L,
          product = InappifyStoreProduct(
            identifier = "monthly-product",
            name = "Premium Monthly",
            prices = listOf(
              InappifyPrice(
                id = 11L,
                appProductId = 12L,
                currency = "IRR",
                amount = 120_000L,
                originalAmount = 160_000L,
                discountAmount = 40_000.5,
                price = 120_000L,
                createdAt = "2026-08-01T00:00:00Z",
                updatedAt = "2026-08-30T00:00:00Z",
                originPrice = 160_000L,
              ),
            ),
            dollarPrice = 1.25,
            trialDays = 7L,
          ),
        ),
      ),
      paywall = paywall,
    )

    assertEquals(
      linkedMapOf(
        "identifier" to "main",
        "isDefault" to true,
        "serverDescription" to "Main subscription offering",
        "trialDays" to 7L,
        "metadata" to metadata,
        "packages" to listOf(
          linkedMapOf(
            "identifier" to "monthly-package",
            "packageType" to 2L,
            "offeringIdentifier" to "main",
            "description" to "Monthly access",
            "entitlement" to "premium",
            "name" to "Monthly",
            "discountPercent" to 25L,
            "product" to linkedMapOf(
              "identifier" to "monthly-product",
              "productType" to null,
              "name" to "Premium Monthly",
              "prices" to listOf(
                linkedMapOf(
                  "id" to 11L,
                  "app_product_id" to 12L,
                  "currency" to "IRR",
                  "amount" to 120_000L,
                  "originalAmount" to 160_000L,
                  "discountAmount" to 40_000.5,
                  "price" to 120_000L,
                  "created_at" to "2026-08-01T00:00:00Z",
                  "updated_at" to "2026-08-30T00:00:00Z",
                  "originPrice" to 160_000L,
                ),
              ),
              "dollarPrice" to 1.25,
              "trialDays" to 7L,
            ),
          ),
        ),
        "paywall" to paywall,
      ),
      InappifyNativeCodec.offering(offering),
    )
  }

  @Test
  fun purchaseExposesOnlyTheFlutterPurchaseResultFields() {
    val purchase = InappifyPurchase(
      attemptId = "attempt-1",
      productIdentifier = "monthly-product",
      offeringIdentifier = "main",
      market = InappifyMarket.BAZAAR,
      purchaseStatus = InappifyPurchaseStatus.NEEDTOPAY,
      packageIdentifier = "monthly-package",
      url = "https://checkout.example/pay",
      checkoutId = "checkout-8",
      checkoutStatus = "PENDING",
      nextActionType = "REDIRECT",
    )

    assertEquals(
      linkedMapOf(
        "url" to "https://checkout.example/pay",
        "purchaseStatus" to "NEEDTOPAY",
        "checkoutId" to "checkout-8",
        "checkoutStatus" to "PENDING",
        "nextActionType" to "REDIRECT",
      ),
      InappifyNativeCodec.purchase(purchase).filterKeys { it != "mobile" },
    )
  }

  @Test
  fun discountCodePreservesSnakeCaseKeysLinksAndNestedOffering() {
    val result = InappifyDiscountCodeResult(
      isValid = true,
      errorCode = 0L,
      code = "SUMMER25",
      discountId = 31L,
      discountCodeId = 32L,
      percent = 25L,
      message = "Discount applied",
      paymentLinks = listOf(
        InappifyPurchaseLink(
          offering = "main",
          url = "https://checkout.example/discount",
        ),
      ),
      offering = InappifyOffering(
        identifier = "discount-offering",
        isDefault = false,
        trialDays = 3L,
      ),
    )

    assertEquals(
      linkedMapOf(
        "is_valid" to true,
        "error_code" to 0L,
        "code" to "SUMMER25",
        "discount_id" to 31L,
        "discount_code_id" to 32L,
        "percent" to 25L,
        "message" to "Discount applied",
        "payment_links" to listOf(
          linkedMapOf(
            "offering" to "main",
            "url" to "https://checkout.example/discount",
          ),
        ),
        "offering" to linkedMapOf(
          "identifier" to "discount-offering",
          "isDefault" to false,
          "serverDescription" to null,
          "trialDays" to 3L,
          "metadata" to null,
          "packages" to null,
          "paywall" to null,
        ),
      ),
      InappifyNativeCodec.discountCode(result),
    )
  }
}
