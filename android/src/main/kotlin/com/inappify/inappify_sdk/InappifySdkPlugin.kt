package com.inappify.inappify_sdk

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Handler
import android.os.Looper
import androidx.annotation.NonNull
import com.inappify.sdk.BuildConfig as InappifyBuildConfig
import com.inappify.sdk.addHttpTraceListener
import com.inappify.sdk.setConsumableDeliveryHandler
import com.inappify.sdk.InappifyV2Client
import com.inappify.sdk.InappifyClient
import com.inappify.sdk.InappifyLogLevel
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.PluginRegistry
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
  ActivityAware,
  PluginRegistry.NewIntentListener {
  private var logRegistration: AutoCloseable? = null
  private var methodChannel: MethodChannel? = null
  private var eventChannel: EventChannel? = null
  private var httpEventChannel: EventChannel? = null
  private var applicationContext: Context? = null
  private var session: InappifyNativeSession? = null
  private var bridge: InappifyNativeBridge? = null
  private var operationScope: CoroutineScope? = null
  private var mainHandler: Handler? = null
  private var currentActivity: Activity? = null
  private var activityBinding: ActivityPluginBinding? = null
  private var eventSink: EventChannel.EventSink? = null
  private var deliveryRegistration: AutoCloseable? = null
  private var deliveryRelay: FlutterConsumableDeliveryRelay? = null
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
      InappifyChannelContract.SET_LOG_LEVEL_METHOD -> handleLogLevel(call, result)
      InappifyChannelContract.SET_LOG_HANDLER_METHOD -> handleLogHandler(call, result)
      InappifyChannelContract.HANDSHAKE_METHOD -> handleHandshake(call, result)
      in InappifyChannelContract.SDK_METHODS -> handleSdkOperation(call, result)
      else -> result.notImplemented()
    }
  }

  private fun handleLogLevel(call: MethodCall, result: MethodChannel.Result) {
    val raw = (call.arguments as? Map<*, *>)?.get("level") as? String
    val level = InappifyLogLevel.values().firstOrNull { it.name == raw }
    if (level == null) result.error("inappify/invalid-arguments", "Invalid log level.", null)
    else { InappifyClient.logLevel = level; result.success(null) }
  }

  private fun handleLogHandler(call: MethodCall, result: MethodChannel.Result) {
    val enabled = (call.arguments as? Map<*, *>)?.get("enabled") as? Boolean
    if (enabled == null) {
      result.error("inappify/invalid-arguments", "Log handler enabled must be a boolean.", null)
      return
    }
    val channel = methodChannel
    val handler = mainHandler
    if (enabled && (channel == null || handler == null)) {
      result.error("inappify/sdk-unavailable", "The native SDK is not attached.", null)
      return
    }
    logRegistration?.close()
    logRegistration = null
    if (enabled) {
      val generation = engineGeneration
      logRegistration = FlutterLogRelay.register(this) { level, message ->
        handler?.post {
          if (engineGeneration == generation && methodChannel === channel)
            channel?.invokeMethod(InappifyChannelContract.LOG_CALLBACK,
              mapOf("level" to level.name, "message" to message))
        }
      }
    }
    result.success(null)
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
    activityBinding = binding
    currentActivity = binding.activity
    binding.addOnNewIntentListener(this)
    forwardPaymentReturn(binding.activity.intent)
  }

  override fun onDetachedFromActivityForConfigChanges() {
    activityBinding?.removeOnNewIntentListener(this)
    activityBinding = null
    currentActivity = null
  }

  override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
    onAttachedToActivity(binding)
  }

  override fun onDetachedFromActivity() {
    onDetachedFromActivityForConfigChanges()
  }

  override fun onNewIntent(intent: Intent): Boolean {
    forwardPaymentReturn(intent)
    return false // Flutter and the host keep ownership of navigation.
  }

  private fun forwardPaymentReturn(intent: Intent?) {
    if (intent?.action != Intent.ACTION_VIEW) return
    val url = intent.dataString ?: return
    (session?.select(MobileProtocol.GO_V2) as? InappifyV2Client)?.handleDeepLink(url)
  }

  override fun onDetachedFromEngine(
    @NonNull binding: FlutterPlugin.FlutterPluginBinding,
  ) {
    engineGeneration += 1L
    logRegistration?.close()
    logRegistration = null
    deliveryRelay?.close()
    deliveryRelay = null
    deliveryRegistration?.close()
    deliveryRegistration = null
    methodChannel?.setMethodCallHandler(null)
    eventChannel?.setStreamHandler(null)
    httpEventChannel?.setStreamHandler(null)
    eventSink = null
    eventRegistration?.close()
    eventRegistration = null
    httpSink = null
    httpRegistration?.close()
    httpRegistration = null
    activityBinding?.removeOnNewIntentListener(this)
    activityBinding = null
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
    if (call.method == InappifyChannelContract.SET_DELIVERY_HANDLER_METHOD) {
      val enabled = decoded.request.payload["enabled"] as? Boolean
      if (enabled == null) {
        result.success(semanticFailure(decoded.request.requestId, "invalidConfiguration",
          "Delivery handler enabled must be a boolean.", emptyMap()))
        return
      }
      deliveryRegistration?.close()
      deliveryRegistration = null
      deliveryRelay?.close()
      deliveryRelay = null
      if (enabled) {
        val generation = engineGeneration
        val relay = FlutterConsumableDeliveryRelay { delivery, complete ->
          handler.post {
            val channel = methodChannel
            if (generation != engineGeneration || channel == null) complete(null)
            else channel.invokeMethod(InappifyChannelContract.CONSUMABLE_DELIVERY_CALLBACK,
              InappifyNativeCodec.delivery(delivery), object : MethodChannel.Result {
                override fun success(value: Any?) { complete(value) }
                override fun error(code: String, message: String?, details: Any?) { complete(null) }
                override fun notImplemented() { complete(null) }
              })
          }
        }
        deliveryRelay = relay
        deliveryRegistration = session!!.observe { selected ->
          selected.setConsumableDeliveryHandler { delivery -> relay.deliver(delivery) }
        }
      }
      result.success(InappifyNativeCodec.withRuntimeState(InappifyNativeCodec.successEnvelope(
        decoded.request.requestId,
        session!!.select(MobileProtocol.GO_V2).snapshot,
        hostVersion,
      ), session!!))
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
