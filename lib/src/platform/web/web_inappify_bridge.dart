import 'package:inappify_sdk/request_cancellation.dart';

/// Browser event emitted by the JavaScript InAppify SDK.
///
/// [name] is one of the documented `customerInfoUpdated`,
/// `offeringsUpdated`, `authenticationChanged`, or `sessionStateChanged` event
/// names. [payload] is a recursively converted JSON-compatible value;
/// JavaScript objects never leak past this boundary.
class InappifyWebBridgeEvent {
  /// Creates an immutable browser bridge event.
  const InappifyWebBridgeEvent({required this.name, this.payload});

  /// JavaScript SDK event name.
  final String name;

  /// JSON-compatible event value.
  final Object? payload;
}

/// Sanitized exception raised by the browser-only JavaScript bridge.
///
/// The bridge deliberately retains only stable, non-secret metadata. Raw
/// JavaScript errors and their potentially sensitive `details` objects are
/// never exposed to the shared Flutter layers.
class InappifyWebBridgeException implements Exception {
  /// Creates a normalized JavaScript bridge exception.
  const InappifyWebBridgeException({
    required this.code,
    this.status,
    this.requestId,
    this.name,
    this.kind,
    this.retryAfterMillis,
  });

  /// Provider error code, or a bridge-owned fallback code.
  final String code;

  /// HTTP status reported by the provider, when present.
  final int? status;

  /// Non-secret service request identifier, when present.
  final String? requestId;

  /// JavaScript error name such as `AbortError`, when present.
  final String? name;

  /// Stable JavaScript SDK error kind such as `network` or `configuration`.
  final String? kind;

  /// Allowlisted rate-limit delay. No other provider `details` are retained.
  final int? retryAfterMillis;

  @override
  String toString() => 'InappifyWebBridgeException($code)';
}

/// Optional feature probe for a provider's actual JavaScript methods.
abstract interface class InappifyWebProviderCapabilities {
  bool supportsMethod(String method);
}

/// Injectable boundary between the typed Flutter adapter and JavaScript.
///
/// Production code uses a browser-only implementation backed by
/// `@inappifylabs/web-sdk`. Tests can provide a deterministic fake without
/// importing `dart:js_interop`. All arguments and return values must contain
/// only null, booleans, numbers, strings, lists, and string-keyed maps.
abstract interface class InappifyWebBridge {
  /// Whether the ESM host has been installed in the current browser page.
  bool get isAvailable;

  /// Optional JavaScript package version used only for diagnostics.
  String? get sdkVersion;

  /// Documented out-of-band JavaScript SDK events.
  Stream<InappifyWebBridgeEvent> get events;

  /// Calls the static `InAppify.configure(options)` factory.
  ///
  /// Implementations retain the returned session instance and use it for all
  /// subsequent [call] and [readProperty] operations.
  Future<Object?> configure(Map<String, Object?> options);

  /// Invokes a method on the configured JavaScript session instance.
  Future<Object?> call(
    String method, {
    List<Object?> positionalArguments = const <Object?>[],
    InappifyRequestCancellation? cancellation,
    bool injectAbortSignal = false,
  });

  /// Reads a synchronous property from the configured JavaScript instance.
  Object? readProperty(String name);

  /// Persists the pending checkout id in browser `sessionStorage`.
  void persistPendingCheckout(String checkoutId);

  /// Removes the pending checkout id after authoritative `Paid` state.
  void clearPendingCheckout();

  /// Reads the non-secret checkout id retained across a payment redirect.
  String? readPendingCheckout();

  /// Releases event listeners owned by this bridge.
  Future<void> dispose();
}
