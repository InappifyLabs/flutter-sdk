package com.inappify.inappify_sdk

import com.inappify.sdk.*

/** One native handler for all attached Flutter engines; never retains an Activity. */
internal object FlutterLogRelay : InappifyLogHandler {
  private val lock = Any()
  private val callbacks = linkedMapOf<Any, (InappifyLogLevel, String) -> Unit>()
  private var preceding: InappifyLogHandler? = null

  fun register(owner: Any, callback: (InappifyLogLevel, String) -> Unit): AutoCloseable {
    synchronized(lock) {
      if (callbacks.isEmpty()) {
        preceding = InappifyClient.logHandler
        InappifyClient.logHandler = this
      }
      callbacks[owner] = callback
    }
    return AutoCloseable {
      synchronized(lock) {
        if (callbacks[owner] === callback) callbacks.remove(owner)
        if (callbacks.isEmpty()) {
          if (InappifyClient.logHandler === this) preceding?.let { InappifyClient.logHandler = it }
          preceding = null
        }
      }
    }
  }

  private fun emit(level: InappifyLogLevel, message: String) {
    val targets = synchronized(lock) { callbacks.values.toList() }
    targets.forEach { target -> runCatching { target(level, message) } }
  }
  override fun v(tag: String, msg: String) = emit(InappifyLogLevel.VERBOSE, msg)
  override fun d(tag: String, msg: String) = emit(InappifyLogLevel.DEBUG, msg)
  override fun i(tag: String, msg: String) = emit(InappifyLogLevel.INFO, msg)
  override fun w(tag: String, msg: String) = emit(InappifyLogLevel.WARN, msg)
  override fun e(tag: String, msg: String, throwable: Throwable?) = emit(InappifyLogLevel.ERROR, msg)
}
