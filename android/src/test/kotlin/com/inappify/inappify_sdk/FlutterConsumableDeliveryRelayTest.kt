package com.inappify.inappify_sdk

import com.inappify.sdk.*
import kotlin.test.*
import kotlinx.coroutines.*

class FlutterConsumableDeliveryRelayTest {
  private val delivery = InappifyConsumableDelivery(9_007_199_254_740_993L, "coins", null, InappifyDeliverySource.MYKET)

  @Test fun onlyAnExplicitDurableSuccessCanAcknowledge() = runBlocking {
    for (value in listOf(null, true, "DELIVERED", "retryLater", "delivered")) {
      val relay = FlutterConsumableDeliveryRelay { received, complete ->
        assertEquals(delivery, received); complete(value)
      }
      assertEquals(if (value == "delivered") InappifyDeliveryResult.DELIVERED
        else InappifyDeliveryResult.RETRY_LATER, relay.deliver(delivery))
    }
  }

  @Test fun DetachingWhileHostIsGrantingRetainsPendingDelivery() = runBlocking {
    var complete: ((Any?) -> Unit)? = null
    val relay = FlutterConsumableDeliveryRelay { _, callback -> complete = callback }
    val waiting = async(start = CoroutineStart.UNDISPATCHED) { relay.deliver(delivery) }
    assertFalse(waiting.isCompleted)
    relay.close()
    assertEquals(InappifyDeliveryResult.RETRY_LATER, waiting.await())
    complete!!("delivered") // late host result cannot turn an uncertain delivery into an acknowledgement
    assertEquals(InappifyDeliveryResult.RETRY_LATER, relay.deliver(delivery))
  }

  @Test fun callbackErrorsRetainPendingDelivery() = runBlocking {
    val relay = FlutterConsumableDeliveryRelay { _, _ -> error("Unavailable host") }
    assertEquals(InappifyDeliveryResult.RETRY_LATER, relay.deliver(delivery))
  }
}
