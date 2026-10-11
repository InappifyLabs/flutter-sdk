import Flutter
import CoreFoundation
import UIKit
import Security

/// Flutter bridge for host metadata and the versioned Inappify native contract.
///
/// Native lifecycle ownership remains disabled until the iOS SDK implements
/// every stateful operation required by protocol v1. This prevents Dart and
/// native implementations from maintaining different session state.
public class InappifySdkPlugin: NSObject, FlutterPlugin {
  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: Contract.channelName,
      binaryMessenger: registrar.messenger()
    )
    let instance = InappifySdkPlugin()
    registrar.addMethodCallDelegate(instance, channel: channel)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "getPlatformVersion":
      result("iOS " + UIDevice.current.systemVersion)

    case "getVersionInfo":
      let infoDictionary = Bundle.main.infoDictionary
      let versionName = infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
      let versionCode = infoDictionary?["CFBundleVersion"] as? String ?? ""

      let response: [String: String] = [
        "versionName": versionName,
        "versionCode": versionCode
      ]
      result(response)

    case Contract.handshakeMethod:
      handleHandshake(call, result: result)

    case "sdkGetMobileMetadata":
      handleMobileMetadata(result)

    case "sdkReadGoState":
      handleReadGoState(call, result: result)

    case "sdkWriteGoState":
      handleWriteGoState(call, result: result)

    default:
      result(FlutterMethodNotImplemented)
    }
  }

  /// Infrastructure only: Go lifecycle and signature verification remain in Dart.
  private func handleMobileMetadata(_ result: @escaping FlutterResult) {
    let info = Bundle.main.infoDictionary
    guard
      let identifier = Bundle.main.bundleIdentifier, !identifier.isEmpty,
      let versionName = info?["CFBundleShortVersionString"] as? String,
      !versionName.isEmpty, versionName.count <= 50,
      let build = info?["CFBundleVersion"] as? String,
      build.range(of: "^[0-9]+$", options: .regularExpression) != nil,
      let versionCode = Int(build), versionCode > 0
    else {
      result(FlutterError(code: "inappify/invalid-metadata",
        message: "The application must provide a bundle identifier, version name and positive integer build number.",
        details: nil))
      return
    }
    result(["identifierValue": identifier, "versionName": versionName,
      "versionCode": versionCode] as [String: Any])
  }

  /// Separate non-synchronizing, device-only accounts; legacy preferences stay intact.
  private func goStateQuery(_ call: FlutterMethodCall) -> [String: Any]? {
    guard let args = call.arguments as? [String: Any],
      let namespace = args["namespace"] as? String,
      namespace == "goV2"
    else { return nil }
    return [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: "com.inappify.flutter.mobile.secure-state.v2",
      kSecAttrAccount as String: namespace,
      kSecAttrSynchronizable as String: false,
    ]
  }

  private func handleReadGoState(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard var query = goStateQuery(call) else {
      result(storageFailure("invalid-namespace")); return
    }
    query[kSecReturnData as String] = true
    query[kSecMatchLimit as String] = kSecMatchLimitOne
    var stored: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &stored)
    if status == errSecItemNotFound { result(nil); return }
    guard status == errSecSuccess, let data = stored as? Data,
      data.count <= 1024 * 1024, let document = String(data: data, encoding: .utf8)
    else { result(storageFailure("read-failed")); return }
    result(document)
  }

  private func handleWriteGoState(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard let query = goStateQuery(call),
      let args = call.arguments as? [String: Any],
      let document = args["document"] as? String,
      let data = document.data(using: .utf8), data.count <= 1024 * 1024,
      (try? JSONSerialization.jsonObject(with: data)) is [String: Any]
    else { result(storageFailure("invalid-document")); return }
    // SecItemUpdate replaces the entire value atomically; never delete before saving.
    let attributes: [String: Any] = [
      kSecValueData as String: data,
      kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
    ]
    var status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
    if status == errSecItemNotFound {
      var insertion = query
      for (key, value) in attributes { insertion[key] = value }
      status = SecItemAdd(insertion as CFDictionary, nil)
      // Another engine can create the same account concurrently.
      if status == errSecDuplicateItem {
        status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
      }
    }
    guard status == errSecSuccess else { result(storageFailure("write-failed")); return }
    result(nil)
  }

  private func storageFailure(_ code: String) -> FlutterError {
    return FlutterError(code: "inappify/storage-" + code,
      message: "The Inappify secure state operation could not be completed.", details: nil)
  }

  /// Validates protocol compatibility and reports current native capabilities.
  private func handleHandshake(
    _ call: FlutterMethodCall,
    result: @escaping FlutterResult
  ) {
    guard
      let arguments = call.arguments as? [String: Any],
      let requestId = arguments[Contract.requestIdKey] as? String,
      !requestId.isEmpty
    else {
      result(
        FlutterError(
          code: "inappify/invalid-arguments",
          message: "The handshake envelope has no valid request identifier.",
          details: nil
        )
      )
      return
    }

    guard
      let rawProtocolVersion = arguments[Contract.protocolVersionKey],
      let payload = arguments[Contract.payloadKey] as? [String: Any],
      let clientProtocolVersions = payload[Contract.clientProtocolVersionsKey]
        as? [Any]
    else {
      result(failureEnvelope(
        requestId: requestId,
        code: "invalidConfiguration",
        message: "The handshake envelope is missing required fields."
      ))
      return
    }

    guard let protocolVersion = exactInteger(rawProtocolVersion) else {
      result(failureEnvelope(
        requestId: requestId,
        code: "protocolMismatch",
        message: "Unsupported Inappify protocol version.",
        details: [Contract.protocolVersionKey: Contract.protocolVersion]
      ))
      return
    }

    let supportsProtocol = clientProtocolVersions.contains { value in
      exactInteger(value) == Contract.protocolVersion
    }
    guard
      protocolVersion == Contract.protocolVersion,
      supportsProtocol
    else {
      result(failureEnvelope(
        requestId: requestId,
        code: "protocolMismatch",
        message: "Unsupported Inappify protocol version.",
        details: [Contract.protocolVersionKey: Contract.protocolVersion]
      ))
      return
    }

    result([
      Contract.protocolVersionKey: Contract.protocolVersion,
      Contract.requestIdKey: requestId,
      Contract.okKey: true,
      Contract.dataKey: [
        "backendKind": "methodChannel",
        Contract.protocolVersionKey: Contract.protocolVersion,
        "ownsSession": false,
        "supportedOperations": [String](),
      ],
    ])
  }

  /// Returns an exact integer without truncating fractional codec numbers.
  private func exactInteger(_ value: Any?) -> Int? {
    guard
      let number = value as? NSNumber,
      CFGetTypeID(number) != CFBooleanGetTypeID()
    else {
      return nil
    }

    let doubleValue = number.doubleValue
    guard
      doubleValue.isFinite,
      doubleValue.rounded(.towardZero) == doubleValue,
      let integer = Int(exactly: doubleValue)
    else {
      return nil
    }
    return integer
  }

  /// Builds a correlated protocol-v1 semantic failure envelope.
  private func failureEnvelope(
    requestId: String,
    code: String,
    message: String,
    details: [String: Any] = [:]
  ) -> [String: Any] {
    return [
      Contract.protocolVersionKey: Contract.protocolVersion,
      Contract.requestIdKey: requestId,
      Contract.okKey: false,
      Contract.errorKey: [
        Contract.errorCodeKey: code,
        Contract.errorMessageKey: message,
        Contract.errorRetryableKey: false,
        Contract.errorDetailsKey: details,
      ],
    ]
  }

  private enum Contract {
    static let channelName = "inappify_sdk"
    static let protocolVersion = 1
    static let handshakeMethod = "sdkHandshake"
    static let protocolVersionKey = "protocolVersion"
    static let requestIdKey = "requestId"
    static let payloadKey = "payload"
    static let clientProtocolVersionsKey = "clientProtocolVersions"
    static let okKey = "ok"
    static let dataKey = "data"
    static let errorKey = "error"
    static let errorCodeKey = "code"
    static let errorMessageKey = "message"
    static let errorRetryableKey = "retryable"
    static let errorDetailsKey = "details"
  }
}
