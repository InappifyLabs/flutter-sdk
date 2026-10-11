package com.inappify.inappify_sdk

import android.app.Activity
import android.content.Context
import android.os.Build
import android.os.Handler
import android.os.Looper
import androidx.annotation.NonNull
import com.inappify.sdk.BuildConfig as InappifyBuildConfig
import com.inappify.sdk.addHttpTraceListener
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch

/** Android bridge that delegates the complete mobile lifecycle to the native SDK. */
class InappifySdkPlugin :
  FlutterPlugin,
  MethodChannel.MethodCallHandler,
  EventChannel.StreamHandler,
  ActivityAware {
  private var methodChannel: MethodChannel? = null
  private var eventChannel: EventChannel? = null
  private var httpEventChannel: EventChannel? = null
  private var applicationContext: Context? = null
  private var session: InappifyNativeSession? = null
  private var bridge: InappifyNativeBridge? = null
  private var operationScope: CoroutineScope? = null
  private var mainHandler: Handler? = null
  private var currentActivity: Activity? = null
  private var eventSink: EventChannel.EventSink? = null
  private var eventRegistration: AutoCloseable? = null
  private var httpRegistration: AutoCloseable? = null
  private var httpSink: EventChannel.EventSink? = null
  private var hostVersion = HostApplicationVersion(versionName = "", versionCode = 0L)
  private var engineGeneration: Long = 0L

  override fun onAttachedToEngine(
    @NonNull flutterPluginBinding: FlutterPlugin.FlutterPluginBinding,
  ) {
    val context = flutterPluginBinding.applicationContext
    val ownedSession = InappifyClientHolder.acquire(context)
    hostVersion = readHostVersion(context)
    applicationContext = context
    session = ownedSession
    bridge = InappifyNativeBridge(ownedSession, hostVersion)
    operationScope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    mainHandler = Handler(Looper.getMainLooper())
    engineGeneration += 1L

    methodChannel = MethodChannel(
      flutterPluginBinding.binaryMessenger,
      InappifyChannelContract.CHANNEL_NAME,
    ).also { it.setMethodCallHandler(this) }
    eventChannel = EventChannel(
      flutterPluginBinding.binaryMessenger,
      InappifyChannelContract.EVENT_CHANNEL_NAME,
    ).also { it.setStreamHandler(this) }
    httpEventChannel = EventChannel(
      flutterPluginBinding.binaryMessenger,
      InappifyChannelContract.HTTP_EVENT_CHANNEL_NAME,
    ).also { channel ->
      channel.setStreamHandler(object : EventChannel.StreamHandler {
        override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
          httpRegistration?.close()
          httpSink = events
          val generation = engineGeneration
          httpRegistration = session?.observe { selected ->
            selected.addHttpTraceListener { trace ->
              // Never relay raw debug traces even if a future factory changes.
              if (!trace.containsSensitiveData) {
                val encoded = InappifyNativeCodec.httpTrace(trace)
                mainHandler?.post {
                  if (engineGeneration == generation && httpSink === events) events.success(encoded)
                }
              }
            }
          }
        }

        override fun onCancel(arguments: Any?) {
          httpSink = null
          httpRegistration?.close()
          httpRegistration = null
        }
      })
    }
  }

  override fun onMethodCall(
    @NonNull call: MethodCall,
    @NonNull result: MethodChannel.Result,
  ) {
    when (call.method) {
      "getPlatformVersion" -> result.success("Android ${Build.VERSION.RELEASE}")
      "getVersionInfo" -> handleVersionInfo(result)
      InappifyChannelContract.HANDSHAKE_METHOD -> handleHandshake(call, result)
      in InappifyChannelContract.SDK_METHODS -> handleSdkOperation(call, result)
      else -> result.notImplemented()
    }
  }

  override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
    eventRegistration?.close()
    eventRegistration = null
    eventSink = events

    val ownedSession = session
    if (ownedSession == null) {
      events.error(
        "inappify/sdk-unavailable",
        "The native Inappify SDK is not attached to a Flutter engine.",
        null,
      )
      return
    }
    val generation = engineGeneration
    eventRegistration = ownedSession.observe { selected ->
      selected.addEventListener { event ->
        val encoded = InappifyNativeCodec.withRuntimeState(
          InappifyNativeCodec.eventEnvelope(event, hostVersion), ownedSession,
        )
        mainHandler?.post {
          if (engineGeneration == generation && eventSink === events) {
            events.success(encoded)
          }
        }
      }
    }
  }

  override fun onCancel(arguments: Any?) {
    eventSink = null
    eventRegistration?.close()
    eventRegistration = null
  }

  override fun onAttachedToActivity(binding: ActivityPluginBinding) {
    currentActivity = binding.activity
  }

  override fun onDetachedFromActivityForConfigChanges() {
    currentActivity = null
  }

  override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
    currentActivity = binding.activity
  }

  override fun onDetachedFromActivity() {
    currentActivity = null
  }

  override fun onDetachedFromEngine(
    @NonNull binding: FlutterPlugin.FlutterPluginBinding,
  ) {
    engineGeneration += 1L
    methodChannel?.setMethodCallHandler(null)
    eventChannel?.setStreamHandler(null)
    httpEventChannel?.setStreamHandler(null)
    eventSink = null
    eventRegistration?.close()
    eventRegistration = null
    httpSink = null
    httpRegistration?.close()
    httpRegistration = null
    currentActivity = null
    operationScope?.cancel()
    operationScope = null

    session?.let(InappifyClientHolder::release)
    session = null
    bridge = null
    applicationContext = null
    methodChannel = null
    eventChannel = null
    httpEventChannel = null
    mainHandler = null
  }

  private fun handleVersionInfo(result: MethodChannel.Result) {
    if (applicationContext == null) {
      result.error(
        "inappify/sdk-unavailable",
        "Host application version information is unavailable.",
        null,
      )
      return
    }
    result.success(
      mapOf(
        "versionName" to hostVersion.versionName,
        // Preserve the original plugin response type for callers that still
        // consume this legacy metadata method directly.
        "versionCode" to hostVersion.versionCode.toString(),
      ),
    )
  }

  private fun handleHandshake(call: MethodCall, result: MethodChannel.Result) {
    when (val decoded = decodeChannelRequest(call.arguments)) {
      is InappifyChannelRequestResult.TransportFailure -> {
        val message = if (decoded.message.contains("request identifier")) {
          "The handshake envelope has no valid request identifier."
        } else {
          decoded.message
        }
        result.error("inappify/invalid-arguments", message, null)
      }

      is InappifyChannelRequestResult.SemanticFailure -> result.success(
        InappifyNativeCodec.failureEnvelope(
          requestId = decoded.requestId,
          code = decoded.code,
          message = decoded.message,
          details = decoded.details,
        ),
      )

      is InappifyChannelRequestResult.Valid -> {
        val versions = decoded.request.payload[
          InappifyChannelContract.CLIENT_PROTOCOL_VERSIONS_KEY
        ] as? List<*>
        if (versions == null) {
          result.success(
            InappifyNativeCodec.failureEnvelope(
              requestId = decoded.request.requestId,
              code = "invalidConfiguration",
              message = "The handshake payload is missing client protocol versions.",
            ),
          )
          return
        }
        val supportsProtocol = versions.any {
          exactInt(it) == InappifyChannelContract.PROTOCOL_VERSION
        }
        if (!supportsProtocol) {
          result.success(
            InappifyNativeCodec.failureEnvelope(
              requestId = decoded.request.requestId,
              code = "protocolMismatch",
              message = "Unsupported Inappify protocol version.",
              details = mapOf(
                InappifyChannelContract.PROTOCOL_VERSION_KEY to
                  InappifyChannelContract.PROTOCOL_VERSION,
              ),
            ),
          )
          return
        }
        result.success(
          linkedMapOf(
            InappifyChannelContract.PROTOCOL_VERSION_KEY to
              InappifyChannelContract.PROTOCOL_VERSION,
            InappifyChannelContract.REQUEST_ID_KEY to decoded.request.requestId,
            InappifyChannelContract.OK_KEY to true,
            InappifyChannelContract.DATA_KEY to linkedMapOf(
              "backendKind" to "methodChannel",
              InappifyChannelContract.PROTOCOL_VERSION_KEY to
                InappifyChannelContract.PROTOCOL_VERSION,
              "ownsSession" to true,
              "supportedOperations" to InappifyChannelContract.SUPPORTED_OPERATIONS,
              "sdkVersion" to InappifyBuildConfig.SDK_VERSION,
            ),
          ),
        )
      }
    }
  }

  private fun handleSdkOperation(call: MethodCall, result: MethodChannel.Result) {
    val decoded = decodeChannelRequest(call.arguments)
    if (decoded is InappifyChannelRequestResult.TransportFailure) {
      result.error("inappify/invalid-arguments", decoded.message, null)
      return
    }
    if (decoded is InappifyChannelRequestResult.SemanticFailure) {
      result.success(
        semanticFailure(
          requestId = decoded.requestId,
          code = decoded.code,
          message = decoded.message,
          details = decoded.details,
        ),
      )
      return
    }
    decoded as InappifyChannelRequestResult.Valid

    val activeBridge = bridge
    val scope = operationScope
    val handler = mainHandler
    if (activeBridge == null || scope == null || handler == null) {
      result.error(
        "inappify/sdk-unavailable",
        "The native Inappify SDK is not attached to a Flutter engine.",
        null,
      )
      return
    }
    val generation = engineGeneration
    val activity = currentActivity
    scope.launch {
      val response = activeBridge.invoke(
        method = call.method,
        requestId = decoded.request.requestId,
        payload = decoded.request.payload,
        activity = activity,
      )
      handler.post {
        if (engineGeneration == generation && methodChannel != null) {
          result.success(response)
        }
      }
    }
  }

  private fun semanticFailure(
    requestId: String,
    code: String,
    message: String,
    details: Map<String, Any?>,
  ): Map<String, Any?> {
    val ownedClient = session?.currentClient
    val envelope = InappifyNativeCodec.failureEnvelope(
      requestId = requestId,
      code = code,
      message = message,
      details = details,
      snapshot = ownedClient?.snapshot,
      hostVersion = if (ownedClient == null) null else hostVersion,
    )
    return session?.let { InappifyNativeCodec.withRuntimeState(envelope, it) } ?: envelope
  }

  private fun readHostVersion(context: Context): HostApplicationVersion = try {
    val packageInfo = context.packageManager.getPackageInfo(context.packageName, 0)
    val versionCode = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
      packageInfo.longVersionCode
    } else {
      @Suppress("DEPRECATION")
      packageInfo.versionCode.toLong()
    }
    HostApplicationVersion(
      versionName = packageInfo.versionName.orEmpty(),
      versionCode = versionCode,
    )
  } catch (_: Exception) {
    HostApplicationVersion(versionName = "", versionCode = 0L)
  }
}
