package com.inappify.inappify_sdk

import com.inappify.sdk.InappifyConsumableDelivery
import com.inappify.sdk.InappifyDeliveryResult
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.withTimeoutOrNull

/** An unavailable/detached Flutter engine can never acknowledge a delivery. */
internal class FlutterConsumableDeliveryRelay(
  private val dispatch: (InappifyConsumableDelivery, (Any?) -> Unit) -> Unit,
) : AutoCloseable {
  private val lock = Any()
  private var closed = false
  private val pending = mutableSetOf<CompletableDeferred<InappifyDeliveryResult>>()

  suspend fun deliver(delivery: InappifyConsumableDelivery): InappifyDeliveryResult {
    val response = CompletableDeferred<InappifyDeliveryResult>()
    synchronized(lock) {
      if (closed) return InappifyDeliveryResult.RETRY_LATER
      pending.add(response)
    }
    try {
      dispatch(delivery) { value ->
        response.complete(if (value == "delivered") InappifyDeliveryResult.DELIVERED
          else InappifyDeliveryResult.RETRY_LATER)
      }
      return withTimeoutOrNull(60_000) { response.await() } ?: InappifyDeliveryResult.RETRY_LATER
    } catch (cancelled: CancellationException) {
      throw cancelled
    } catch (_: Exception) {
      return InappifyDeliveryResult.RETRY_LATER
    } finally {
      synchronized(lock) { pending.remove(response) }
    }
  }

  override fun close() = synchronized(lock) {
    closed = true
    pending.forEach { it.complete(InappifyDeliveryResult.RETRY_LATER) }
    pending.clear()
  }
}
