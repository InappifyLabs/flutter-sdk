package com.inappify.inappify_sdk

import android.content.Context
import com.inappify.sdk.InappifyClient
import com.inappify.sdk.InappifyV2Client
import kotlinx.coroutines.sync.Mutex
import java.util.concurrent.atomic.AtomicBoolean

internal enum class MobileProtocol(val wireName: String) {
  GO_V2("goV2");

  companion object {
    fun fromWire(value: Any?): MobileProtocol = when (value) {
      null, "goV2" -> GO_V2
      else -> throw NativeSessionException("invalidConfiguration", "Unknown mobile protocol.")
    }
  }
}

internal class NativeSessionException(
  val code: String,
  override val message: String,
) : IllegalStateException(message)

/**
 * Process-owned session. Protocol selection happens once, before Configure effects.
 * All engines observe the same client and operation ordering. A failed Configure
 * does not silently switch protocol or clear another engine's session.
 */
internal class InappifyNativeSession(
  private val factory: (MobileProtocol) -> InappifyClient,
) {
  private val lock = Any()
  val operationMutex = Mutex()
  private val purchaseInProgress = AtomicBoolean(false)
  private var selectedProtocol: MobileProtocol? = null
  private var selectedClient: InappifyClient? = null
  private var closed = false
  private val listeners = LinkedHashSet<ListenerBinding>()

  val protocol: MobileProtocol? get() = synchronized(lock) { selectedProtocol }
  val currentClient: InappifyClient? get() = synchronized(lock) { selectedClient }
  fun tryBeginPurchase(): Boolean = purchaseInProgress.compareAndSet(false, true)
  fun endPurchase() { purchaseInProgress.set(false) }

  fun requireClient(): InappifyClient = currentClient ?: throw NativeSessionException(
    "notConfigured", "Configure the native SDK before calling this operation.",
  )

  fun select(protocol: MobileProtocol): InappifyClient = synchronized(lock) {
    check(!closed) { "The native session is closed." }
    if (selectedProtocol != null && selectedProtocol != protocol) {
      throw NativeSessionException(
        "invalidConfiguration",
        "The mobile protocol is already selected. Create a new application session to change it.",
      )
    }
    selectedClient ?: factory(protocol).also { client ->
      selectedProtocol = protocol
      selectedClient = client
      listeners.forEach { it.registration = it.subscribe(client) }
    }
  }

  /** Subscriptions may start before Configure and are attached at first selection. */
  fun observe(
    subscribe: (InappifyClient) -> AutoCloseable,
  ):
    AutoCloseable = synchronized(lock) {
    check(!closed)
    val binding = ListenerBinding(subscribe)
    selectedClient?.let { binding.registration = subscribe(it) }
    listeners.add(binding)
    AutoCloseable {
      synchronized(lock) {
        listeners.remove(binding)
        binding.registration?.close()
        binding.registration = null
      }
    }
  }

  fun close() {
    val clients = synchronized(lock) {
      if (closed) return
      closed = true
      listeners.forEach {
        it.registration?.close(); it.registration = null
      }
      listeners.clear()
      listOfNotNull(selectedClient).also {
        selectedClient = null
      }
    }
    clients.forEach(InappifyClient::close)
  }

  private class ListenerBinding(
    val subscribe: (InappifyClient) -> AutoCloseable,
    var registration: AutoCloseable? = null,
  )
}

/** Reference-counts one process session without logging out on engine detach. */
internal object InappifyClientHolder {
  private val lock = Any()
  private var session: InappifyNativeSession? = null
  private var ownerCount = 0

  fun acquire(context: Context): InappifyNativeSession = synchronized(lock) {
    val current = session ?: InappifyNativeSession { protocol ->
      when (protocol) {
        MobileProtocol.GO_V2 -> InappifyV2Client.create(context.applicationContext)
      }
    }.also { session = it }
    ownerCount += 1
    current
  }

  fun release(ownedSession: InappifyNativeSession) {
    val toClose = synchronized(lock) {
      if (session !== ownedSession || ownerCount <= 0) return
      ownerCount -= 1
      if (ownerCount == 0) {
        session = null
        ownedSession
      } else null
    }
    toClose?.close()
  }
}
