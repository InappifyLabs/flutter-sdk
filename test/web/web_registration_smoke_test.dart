@TestOn('browser')
library;

import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:flutter_test/flutter_test.dart';
import 'package:inappify_sdk/inappify_sdk_web.dart';
import 'package:inappify_sdk/src/platform/contracts/backend_capabilities.dart';
import 'package:inappify_sdk/src/platform/contracts/sdk_requests.dart';

void main() {
  test(
    'browser entry remains safe when the ESM host is not installed',
    () async {
      final platform = InappifySdkWeb();
      addTearDown(platform.dispose);

      final capabilities = await platform.getCapabilities();

      expect(capabilities.backendKind, InappifyBackendKind.webJavaScript);
      expect(capabilities.ownsSession, isFalse);
      expect(capabilities.supportsCompleteLifecycle, isFalse);
      expect(await platform.getPlatformVersion(), isNotEmpty);
    },
  );

  test('browser entry discovers the beta.3 global IIFE bundle', () async {
    var receivedWorkingFetchOverride = false;
    String? receivedBaseUrl;
    final session = JSObject();
    session.setProperty(
      'customerInfo'.toJS,
      <String, Object?>{
        'originalAppUserId': 'browser-customer',
        'entitlements': <String, Object?>{},
        'attributes': <String, Object?>{},
      }.jsify(),
    );
    session.setProperty(
      'offerings'.toJS,
      <String, Object?>{'all': <Object?>[]}.jsify(),
    );
    session.setProperty('sessionState'.toJS, 'anonymous'.toJS);
    session.setProperty('persistenceMode'.toJS, 'durable'.toJS);
    session.setProperty(
      'on'.toJS,
      ((JSString eventName, JSFunction callback) {
        return (() {}).toJS;
      }).toJS,
    );

    final inAppify = JSObject();
    inAppify.setProperty(
      'configure'.toJS,
      ((JSAny? options) {
        final configureOptions = options as JSObject;
        final baseUrl = configureOptions.getProperty<JSAny?>('baseUrl'.toJS);
        if (baseUrl.typeofEquals('string')) {
          receivedBaseUrl = (baseUrl as JSString).toDart;
        }
        final fetch = configureOptions.getProperty<JSAny?>('fetch'.toJS);
        if (fetch.typeofEquals('function')) {
          final receiver = JSObject();
          receiver.setProperty('fetcher'.toJS, fetch);
          try {
            final result = receiver.callMethodVarArgs<JSAny?>(
              'fetcher'.toJS,
              <JSAny?>['data:text/plain,inappify-fetch-probe'.toJS],
            );
            receivedWorkingFetchOverride = result.typeofEquals('object');
          } catch (_) {
            receivedWorkingFetchOverride = false;
          }
        }
        return session;
      }).toJS,
    );
    final bundle = JSObject();
    bundle.setProperty('InAppify'.toJS, inAppify);
    bundle.setProperty('SDK_VERSION'.toJS, '0.1.0-beta.3'.toJS);
    globalContext.setProperty('InAppifySDK'.toJS, bundle);
    addTearDown(() {
      globalContext.delete('InAppifySDK'.toJS);
    });

    final platform = InappifySdkWeb();
    addTearDown(platform.dispose);

    final capabilities = await platform.getCapabilities();
    final configured = await platform.configure(
      const InappifyConfigureRequest(
        apiKey: 'public-web-key',
        country: 'IR',
        appVersion: '1.0.0',
      ),
    );

    expect(capabilities.backendKind, InappifyBackendKind.webJavaScript);
    expect(capabilities.ownsSession, isTrue);
    expect(capabilities.supportsCompleteLifecycle, isTrue);
    expect(capabilities.sdkVersion, '0.1.0-beta.3');
    expect(configured.isSuccess, isTrue);
    expect(receivedWorkingFetchOverride, isTrue);
    expect(receivedBaseUrl, 'https://api.inappify.com/api/web/v1');
    expect(
      configured.snapshot?.customerInfo?.originalAppUserId,
      'browser-customer',
    );
  });
}
