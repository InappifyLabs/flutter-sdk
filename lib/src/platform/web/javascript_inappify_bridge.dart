import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:inappify_sdk/request_cancellation.dart';
import 'package:inappify_sdk/src/platform/web/web_inappify_bridge.dart';
import 'package:web/web.dart' as web;

/// Browser-only bridge to the ESM `@inappifylabs/web-sdk` package.
///
/// Flutter does not bundle bare NPM imports. The host application therefore
/// installs a tiny ESM entry before Flutter starts:
///
/// ```js
/// import {
///   InAppify,
///   SDK_VERSION,
///   isInAppifyError,
/// } from '@inappifylabs/web-sdk'
/// globalThis.__inappifyFlutterWebSdk = {
///   InAppify,
///   SDK_VERSION,
///   isInAppifyError,
/// }
/// ```
///
/// The official `dist/inappify.global.js` export named `InAppifySDK` and a
/// legacy global `InAppify` export are accepted as compatibility fallbacks.
/// The returned configured instance remains inside this browser-only class.
class JavaScriptInappifyBridge implements InappifyWebBridge {
  /// Creates an unconfigured JavaScript bridge.
  JavaScriptInappifyBridge();

  static const String _hostProperty = '__inappifyFlutterWebSdk';
  static const String _checkoutStorageKey = 'inappify_checkout_id';
  static const List<String> _eventNames = <String>[
    'customerInfoUpdated',
    'offeringsUpdated',
    'authenticationChanged',
    'sessionStateChanged',
  ];

  final StreamController<InappifyWebBridgeEvent> _events =
      StreamController<InappifyWebBridgeEvent>.broadcast(sync: true);
  final List<JSFunction> _unsubscribeFunctions = <JSFunction>[];
  final List<JSFunction> _retainedCallbacks = <JSFunction>[];

  JSObject? _instance;
  bool _disposed = false;

  @override
  bool get isAvailable => _configureTarget != null;

  @override
  String? get sdkVersion {
    final host = _host;
    if (host == null) return null;
    return _stringProperty(host, 'version') ??
        _stringProperty(host, 'VERSION') ??
        _stringProperty(host, 'SDK_VERSION') ??
        _stringProperty(host, 'sdkVersion');
  }

  @override
  Stream<InappifyWebBridgeEvent> get events => _events.stream;

  @override
  Future<Object?> configure(Map<String, Object?> options) async {
    _ensureNotDisposed();
    final target = _configureTarget;
    if (target == null) {
      throw const InappifyWebBridgeException(code: 'bridge_unavailable');
    }
    try {
      final jsOptions = options.jsify() as JSObject;
      final boundFetch = _boundBrowserFetch;
      if (boundFetch != null) {
        jsOptions.setProperty('fetch'.toJS, boundFetch);
      }
      final raw = target.callMethodVarArgs<JSAny?>('configure'.toJS, <JSAny?>[
        jsOptions,
      ]);
      final resolved = await _resolve(raw);
      if (resolved == null || !resolved.typeofEquals('object')) {
        throw const InappifyWebBridgeException(code: 'malformed_response');
      }
      _instance = resolved as JSObject;
      _subscribeToEvents();
      return null;
    } catch (error) {
      throw _normalizeException(error);
    }
  }

  @override
  Future<Object?> call(
    String method, {
    List<Object?> positionalArguments = const <Object?>[],
    InappifyRequestCancellation? cancellation,
    bool injectAbortSignal = false,
  }) async {
    _ensureNotDisposed();
    final instance = _instance;
    if (instance == null) {
      throw const InappifyWebBridgeException(code: 'not_configured');
    }
    final member = instance.getProperty<JSAny?>(method.toJS);
    if (!member.typeofEquals('function')) {
      throw const InappifyWebBridgeException(code: 'method_unavailable');
    }

    final arguments = positionalArguments
        .map<JSAny?>((argument) => argument.jsify())
        .toList(growable: true);
    web.AbortController? controller;
    StreamSubscription<void>? cancellationSubscription;
    if (injectAbortSignal) {
      controller = web.AbortController();
      final options = arguments.isEmpty
          ? JSObject()
          : arguments.last as JSObject;
      options.setProperty('signal'.toJS, controller.signal);
      if (arguments.isEmpty) arguments.add(options);
      cancellationSubscription = cancellation?.whenCancelled.listen((_) {
        controller?.abort();
      });
      if (cancellation?.isCancelled ?? false) controller.abort();
    }

    try {
      final raw = instance.callMethodVarArgs<JSAny?>(method.toJS, arguments);
      final resolved = await _resolve(raw);
      if (cancellation?.isCancelled ?? false) {
        throw const InappifyWebBridgeException(
          code: 'request_cancelled',
          name: 'AbortError',
        );
      }
      return _toDart(resolved);
    } catch (error) {
      if (cancellation?.isCancelled ?? false) {
        throw const InappifyWebBridgeException(
          code: 'request_cancelled',
          name: 'AbortError',
        );
      }
      throw _normalizeException(error);
    } finally {
      await cancellationSubscription?.cancel();
    }
  }

  @override
  Object? readProperty(String name) {
    _ensureNotDisposed();
    final instance = _instance;
    if (instance == null) return null;
    try {
      return _toDart(instance.getProperty<JSAny?>(name.toJS));
    } catch (error) {
      throw _normalizeException(error);
    }
  }

  @override
  void persistPendingCheckout(String checkoutId) {
    try {
      web.window.sessionStorage.setItem(_checkoutStorageKey, checkoutId);
    } catch (_) {
      // Checkout creation has already succeeded. Storage restrictions must not
      // turn it into a false failure; the typed result still exposes the id.
    }
  }

  @override
  void clearPendingCheckout() {
    try {
      web.window.sessionStorage.removeItem(_checkoutStorageKey);
    } catch (_) {
      // A blocked sessionStorage is non-authoritative payment state.
    }
  }

  @override
  String? readPendingCheckout() {
    try {
      final value = web.window.sessionStorage.getItem(_checkoutStorageKey);
      return value == null || value.isEmpty ? null : value;
    } catch (_) {
      return null;
    }
  }

  void _subscribeToEvents() {
    _clearEventSubscriptions();
    final instance = _instance;
    if (instance == null) return;
    final on = instance.getProperty<JSAny?>('on'.toJS);
    if (!on.typeofEquals('function')) {
      throw const InappifyWebBridgeException(code: 'method_unavailable');
    }
    for (final name in _eventNames) {
      final callback = ((JSAny? payload) {
        if (_disposed) return;
        try {
          _events.add(
            InappifyWebBridgeEvent(name: name, payload: _toDart(payload)),
          );
        } catch (_) {
          // External malformed events must not throw into the JS emitter.
        }
      }).toJS;
      _retainedCallbacks.add(callback);
      final unsubscribe = instance.callMethodVarArgs<JSAny?>(
        'on'.toJS,
        <JSAny?>[name.toJS, callback],
      );
      if (unsubscribe.typeofEquals('function')) {
        _unsubscribeFunctions.add(unsubscribe as JSFunction);
      }
    }
  }

  JSObject? get _host {
    final explicit = globalContext.getProperty<JSAny?>(_hostProperty.toJS);
    if (explicit.isDefinedAndNotNull &&
        (explicit.typeofEquals('object') ||
            explicit.typeofEquals('function'))) {
      return explicit as JSObject;
    }
    final globalBundle = globalContext.getProperty<JSAny?>('InAppifySDK'.toJS);
    if (globalBundle.isDefinedAndNotNull &&
        (globalBundle.typeofEquals('object') ||
            globalBundle.typeofEquals('function'))) {
      return globalBundle as JSObject;
    }
    final fallback = globalContext.getProperty<JSAny?>('InAppify'.toJS);
    if (fallback.isDefinedAndNotNull &&
        (fallback.typeofEquals('object') ||
            fallback.typeofEquals('function'))) {
      return fallback as JSObject;
    }
    return null;
  }

  JSObject? get _configureTarget {
    final host = _host;
    if (host == null) return null;
    final exported = host.getProperty<JSAny?>('InAppify'.toJS);
    final target = exported.isDefinedAndNotNull ? exported : host;
    if (!(target.typeofEquals('object') || target.typeofEquals('function'))) {
      return null;
    }
    final object = target as JSObject;
    return object.getProperty<JSAny?>('configure'.toJS).typeofEquals('function')
        ? object
        : null;
  }

  JSFunction? get _boundBrowserFetch {
    final fetch = globalContext.getProperty<JSAny?>('fetch'.toJS);
    if (!fetch.typeofEquals('function')) return null;
    try {
      // Older Web SDK builds stored `globalThis.fetch` and later invoked it as
      // an instance member. Supplying a bound native function is compatible
      // with beta.3 and keeps older host builds from failing before a request.
      final bound = (fetch as JSFunction).callMethodVarArgs<JSAny?>(
        'bind'.toJS,
        <JSAny?>[globalContext],
      );
      return bound.typeofEquals('function') ? bound as JSFunction : null;
    } catch (_) {
      return null;
    }
  }

  Future<JSAny?> _resolve(JSAny? value) async {
    if (value.isUndefinedOrNull) return value;
    if (value.typeofEquals('object')) {
      final object = value as JSObject;
      final then = object.getProperty<JSAny?>('then'.toJS);
      if (then.typeofEquals('function')) {
        return (value as JSPromise<JSAny?>).toDart;
      }
    }
    return value;
  }

  Object? _toDart(JSAny? value) {
    if (value.isUndefinedOrNull) return null;
    if (!value.typeofEquals('object')) return value.dartify();
    final json = globalContext.getProperty<JSAny?>('JSON'.toJS) as JSObject;
    final encoded = json.callMethodVarArgs<JSAny?>('stringify'.toJS, <JSAny?>[
      value,
    ]);
    if (encoded.isUndefinedOrNull) return null;
    final text = (encoded as JSString).toDart;
    return jsonDecode(text);
  }

  InappifyWebBridgeException _normalizeException(Object error) {
    if (error is InappifyWebBridgeException) return error;
    final map = error is Map ? error : null;
    String? readString(String key) {
      final mapValue = map?[key];
      if (mapValue is String) return mapValue;
      try {
        return _stringProperty(error as JSObject, key);
      } catch (_) {
        return null;
      }
    }

    int? readStatus() {
      final mapValue = map?['status'];
      if (mapValue is num &&
          mapValue.isFinite &&
          mapValue == mapValue.toInt()) {
        return mapValue.toInt();
      }
      try {
        final value = (error as JSObject).getProperty<JSAny?>('status'.toJS);
        final dartValue = value.dartify();
        if (dartValue is num &&
            dartValue.isFinite &&
            dartValue == dartValue.toInt()) {
          return dartValue.toInt();
        }
      } catch (_) {
        return null;
      }
      return null;
    }

    return InappifyWebBridgeException(
      code: readString('code') ?? 'unknown',
      status: readStatus(),
      requestId: readString('requestId'),
      name: readString('name'),
      kind: readString('kind'),
    );
  }

  String? _stringProperty(JSObject object, String name) {
    final value = object.getProperty<JSAny?>(name.toJS);
    if (!value.typeofEquals('string')) return null;
    return (value as JSString).toDart;
  }

  void _clearEventSubscriptions() {
    for (final unsubscribe in _unsubscribeFunctions) {
      try {
        unsubscribe.callAsFunction();
      } catch (_) {
        // Listener cleanup is best effort during reconfiguration/disposal.
      }
    }
    _unsubscribeFunctions.clear();
    _retainedCallbacks.clear();
  }

  void _ensureNotDisposed() {
    if (_disposed) {
      throw const InappifyWebBridgeException(code: 'bridge_unavailable');
    }
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _clearEventSubscriptions();
    _instance = null;
    await _events.close();
  }
}
