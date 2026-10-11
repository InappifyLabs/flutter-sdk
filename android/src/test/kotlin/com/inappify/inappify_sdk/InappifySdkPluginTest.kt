package com.inappify.inappify_sdk

import android.os.Build
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

internal class InappifySdkPluginTest {
  @Test
  fun getPlatformVersionReturnsTheAndroidVersion() {
    val result = RecordingResult()

    InappifySdkPlugin().onMethodCall(MethodCall("getPlatformVersion", null), result)

    assertEquals("Android ${Build.VERSION.RELEASE}", result.successValue)
    assertNull(result.errorCode)
    assertFalse(result.notImplementedCalled)
  }

  @Test
  fun handshakeReturnsACorrelatedVersionedCapabilityEnvelope() {
    val result = RecordingResult()
    val arguments = mapOf(
      "protocolVersion" to 1,
      "requestId" to "request-1",
      "payload" to mapOf("clientProtocolVersions" to listOf(1)),
    )

    InappifySdkPlugin().onMethodCall(MethodCall("sdkHandshake", arguments), result)

    val response = result.successValue as Map<*, *>
    assertEquals(1, response["protocolVersion"])
    assertEquals("request-1", response["requestId"])
    assertEquals(true, response["ok"])

    val capabilities = response["data"] as Map<*, *>
    assertEquals("methodChannel", capabilities["backendKind"])
    assertEquals(1, capabilities["protocolVersion"])
    assertEquals(true, capabilities["ownsSession"])
    assertEquals(
      InappifyChannelContract.SUPPORTED_OPERATIONS,
      capabilities["supportedOperations"],
    )
    assertEquals("0.1.0", capabilities["sdkVersion"])
    assertNull(result.errorCode)
    assertFalse(result.notImplementedCalled)
  }

  @Test
  fun handshakeRejectsAMissingRequestId() {
    val result = RecordingResult()
    val arguments = mapOf("protocolVersion" to 1)

    InappifySdkPlugin().onMethodCall(MethodCall("sdkHandshake", arguments), result)

    assertNull(result.successValue)
    assertEquals("inappify/invalid-arguments", result.errorCode)
    assertEquals(
      "The handshake envelope has no valid request identifier.",
      result.errorMessage,
    )
    assertFalse(result.notImplementedCalled)
  }

  @Test
  fun handshakeReturnsACorrelatedFailureForMissingPayloadFields() {
    val result = RecordingResult()
    val arguments = mapOf(
      "protocolVersion" to 1,
      "requestId" to "request-incomplete",
    )

    InappifySdkPlugin().onMethodCall(MethodCall("sdkHandshake", arguments), result)

    val response = result.successValue as Map<*, *>
    assertEquals("request-incomplete", response["requestId"])
    assertEquals(false, response["ok"])
    val error = response["error"] as Map<*, *>
    assertEquals("invalidConfiguration", error["code"])
    assertNull(result.errorCode)
  }

  @Test
  fun handshakeRejectsAnUnsupportedProtocolVersion() {
    val result = RecordingResult()
    val arguments = mapOf(
      "protocolVersion" to 2,
      "requestId" to "request-2",
      "payload" to mapOf("clientProtocolVersions" to listOf(1, 2)),
    )

    InappifySdkPlugin().onMethodCall(MethodCall("sdkHandshake", arguments), result)

    val response = result.successValue as Map<*, *>
    assertEquals(1, response["protocolVersion"])
    assertEquals("request-2", response["requestId"])
    assertEquals(false, response["ok"])

    val error = response["error"] as Map<*, *>
    assertEquals(
      "protocolMismatch",
      error["code"],
    )
    assertEquals(false, error["retryable"])
    assertEquals(mapOf("protocolVersion" to 1), error["details"])
    assertNull(result.errorCode)
  }

  @Test
  fun handshakeDoesNotTruncateAFractionalProtocolVersion() {
    val result = RecordingResult()
    val arguments = mapOf(
      "protocolVersion" to 1.9,
      "requestId" to "request-fractional",
      "payload" to mapOf("clientProtocolVersions" to listOf(1)),
    )

    InappifySdkPlugin().onMethodCall(MethodCall("sdkHandshake", arguments), result)

    val response = result.successValue as Map<*, *>
    assertEquals(false, response["ok"])
    val error = response["error"] as Map<*, *>
    assertEquals("protocolMismatch", error["code"])
    assertNull(result.errorCode)
  }

  @Test
  fun exactLongAcceptsCodecLongsAndRejectsLossyDoubles() {
    assertEquals(Long.MAX_VALUE, exactLong(Long.MAX_VALUE))
    assertEquals(42L, exactLong(42.0))
    assertNull(exactLong(42.5))
    assertNull(exactLong(9.223372036854776E18))
  }

  @Test
  fun unknownMethodsAreReportedAsNotImplemented() {
    val result = RecordingResult()

    InappifySdkPlugin().onMethodCall(MethodCall("unknownMethod", null), result)

    assertTrue(result.notImplementedCalled)
    assertNull(result.successValue)
    assertNull(result.errorCode)
  }
}

private class RecordingResult : MethodChannel.Result {
  var successValue: Any? = null
    private set
  var errorCode: String? = null
    private set
  var errorMessage: String? = null
    private set
  var errorDetails: Any? = null
    private set
  var notImplementedCalled: Boolean = false
    private set

  override fun success(result: Any?) {
    successValue = result
  }

  override fun error(errorCode: String, errorMessage: String?, errorDetails: Any?) {
    this.errorCode = errorCode
    this.errorMessage = errorMessage
    this.errorDetails = errorDetails
  }

  override fun notImplemented() {
    notImplementedCalled = true
  }
}
