package com.inappify.inappify_sdk

import com.inappify.sdk.*
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import kotlin.test.*

class FlutterLogRelayTest {
  private class Handler : InappifyLogHandler {
    override fun v(tag: String, msg: String) {}
    override fun d(tag: String, msg: String) {}
    override fun i(tag: String, msg: String) {}
    override fun w(tag: String, msg: String) {}
    override fun e(tag: String, msg: String, throwable: Throwable?) {}
  }

  @Test fun multipleEnginesRestoreThePreviousHandlerOnlyAfterLastDetach() {
    val original = InappifyClient.logHandler
    val prior = Handler()
    InappifyClient.logHandler = prior
    val seen = mutableListOf<String>()
    val first = FlutterLogRelay.register(Any()) { _, message -> seen += "a:$message" }
    val second = FlutterLogRelay.register(Any()) { _, message -> seen += "b:$message" }
    try {
      InappifyClient.logHandler.i("[Inappify]", "Safe event.")
      assertEquals(listOf("a:Safe event.", "b:Safe event."), seen)
      first.close()
      assertSame(FlutterLogRelay, InappifyClient.logHandler)
      seen.clear()
      InappifyClient.logHandler.i("[Inappify]", "Next event.")
      assertEquals(listOf("b:Next event."), seen)
      second.close()
      assertSame(prior, InappifyClient.logHandler)
    } finally {
      first.close(); second.close()
      InappifyClient.logHandler = original
    }
  }

  @Test fun throwingEngineAndHostReplacementAreIsolated() {
    val original = InappifyClient.logHandler
    val first = FlutterLogRelay.register(Any()) { _, _ -> error("detached") }
    var calls = 0
    val second = FlutterLogRelay.register(Any()) { _, _ -> calls++ }
    try {
      InappifyClient.logHandler.w("[Inappify]", "Safe warning.")
      assertEquals(1, calls)
      val replacement = Handler()
      InappifyClient.logHandler = replacement
      first.close(); second.close()
      assertSame(replacement, InappifyClient.logHandler)
    } finally {
      first.close(); second.close()
      InappifyClient.logHandler = original
    }
  }

  @Test fun levelCanBeSetBeforeConfigureAndInvalidValuesLeaveItUnchanged() {
    val original = InappifyClient.logLevel
    val plugin = InappifySdkPlugin()
    var error: String? = null
    val result = object : MethodChannel.Result {
      override fun success(value: Any?) {}
      override fun error(code: String, message: String?, details: Any?) { error = code }
      override fun notImplemented() { fail("Logging must work before Configure") }
    }
    try {
      plugin.onMethodCall(MethodCall("sdkSetLogLevel", mapOf("level" to "ERROR")), result)
      assertEquals(InappifyLogLevel.ERROR, InappifyClient.logLevel)
      plugin.onMethodCall(MethodCall("sdkSetLogLevel", mapOf("level" to "INVALID")), result)
      assertEquals("inappify/invalid-arguments", error)
      assertEquals(InappifyLogLevel.ERROR, InappifyClient.logLevel)
    } finally { InappifyClient.logLevel = original }
  }
}
