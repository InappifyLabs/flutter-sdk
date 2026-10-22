@TestOn('browser')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:flutter_test/flutter_test.dart';
import 'package:inappify_sdk/inappify_sdk.dart';
import 'package:inappify_sdk/inappify_sdk_platform_interface.dart';
import 'package:inappify_sdk/src/bootstrap/inappify_sdk_runtime.dart';
import 'package:inappify_sdk/src/platform/web/javascript_inappify_bridge.dart';
import 'package:inappify_sdk/src/platform/web/web_inappify_bridge.dart';
import 'package:inappify_sdk/src/platform/web/web_inappify_platform.dart';
import 'package:web/web.dart' as web;

// Run tool/prepare_web_provider_test.mjs first. These tests use the exact
// published 0.2.0 bundle; only HTTP and the monotonic clock are controlled.
void main() {
  late InappifySdkPlatform previous;
  late WebInappifyPlatform platform;
  late JavaScriptInappifyBridge bridge;

  setUpAll(() async {
    await _load('/web/fixtures/provider-0.2.0.local.js');
    await _load('/web/fixtures/provider_harness.js');
  });
  setUp(() async {
    _invoke('reset');
    previous = InappifySdkPlatform.instance;
    await InappifySdkRuntime.coordinator.resetForTesting();
    bridge = JavaScriptInappifyBridge();
    platform = WebInappifyPlatform(bridge: bridge);
    InappifySdkPlatform.instance = platform;
  });
  tearDown(() async {
    _invoke('release');
    await InappifySdkRuntime.coordinator.resetForTesting();
    InappifySdkPlatform.instance = previous;
    await platform.dispose();
    _invoke('restore');
  });

  Future<void> configure({bool offeringsCache = true}) async {
    _set(<String, Object?>{'failOfferings': !offeringsCache});
    final configured = await InappifySdk.configureResult(
      apiKey: 'test-public-key',
    );
    expect(configured.isSuccess, isTrue);
    expect((await platform.getCapabilities()).sdkVersion, '0.2.0');
    _set(<String, Object?>{'failOfferings': false});
    _invoke('clear');
  }

  Future<void> removeCache() async {
    _set(<String, Object?>{'failInfo': true});
    final login = await InappifySdk.loginWithIdentityTicketResult(
      identityTicket: 'test-ticket',
    );
    expect(login.isSuccess, isFalse);
    expect(login.snapshot?.customerInfo, isNull);
    _set(<String, Object?>{'failInfo': false});
    _invoke('clear');
  }

  test(
    'combined sync delegates to the same provider, refreshes in order and publishes snapshots',
    () async {
      await configure();
      final events = <InappifyPlatformEvent>[];
      final sub = InappifySdk.events.listen(events.add);
      addTearDown(sub.cancel);
      // A Web setter is already a server write. Combined sync only reads.
      expect(
        await InappifySdk.setAttributes(<String, String?>{'language': 'fa'}),
        isTrue,
      );
      _invoke('clear');
      events.clear();
      final result = await InappifySdk.syncAttributesAndOfferingsIfNeeded();
      expect(
        result.isSuccess,
        isTrue,
        reason: '${result.failure?.code}: ${result.failure?.details}',
      );
      expect(_requests, <String>['customerInfo', 'offerings']);
      expect(_state['configureCount'], 1);
      expect(result.data?.current?.identifier, isNotNull);
      expect(result.snapshot?.offerings, same(result.data));
      expect(result.snapshot?.customerInfo?.attributes?.single.value, 'fa');
      expect(InappifySdk.customerInfo?.attributes?.single.value, 'fa');
      expect(events.map((event) => event.type), <InappifyPlatformEventType>[
        InappifyPlatformEventType.customerInfoChanged,
        InappifyPlatformEventType.offeringsChanged,
      ]);
      expect(
        events.last.snapshot?.offerings?.current?.identifier,
        result.data?.current?.identifier,
      );
      expect(
        _calls.where(
          (call) => call['method'] == 'syncAttributesAndOfferingsIfNeeded',
        ),
        hasLength(1),
      );
    },
  );

  test(
    'sixth sync returns the same session cache, and window expiry admits work again',
    () async {
      await configure();
      String? latest;
      for (var i = 0; i < 5; i++) {
        final result = await InappifySdk.syncAttributesAndOfferingsIfNeeded();
        expect(result.isSuccess, isTrue);
        latest = result.data?.current?.identifier;
      }
      expect(_requests, hasLength(10));
      _invoke('clear');
      final limited = await InappifySdk.syncAttributesAndOfferingsIfNeeded();
      expect(limited.isSuccess, isTrue);
      expect(limited.data?.current?.identifier, latest);
      expect(_requests, isEmpty);
      _set(<String, Object?>{'now': 59999});
      expect(
        (await InappifySdk.syncAttributesAndOfferingsIfNeeded())
            .data
            ?.current
            ?.identifier,
        latest,
      );
      expect(_requests, isEmpty);
      _set(<String, Object?>{'now': 60000});
      expect(
        (await InappifySdk.syncAttributesAndOfferingsIfNeeded())
            .data
            ?.current
            ?.identifier,
        isNot(latest),
      );
      expect(_requests, <String>['customerInfo', 'offerings']);
    },
  );

  for (final cache in <bool>[true, false]) {
    test(
      'failed admissions count with offerings cache=$cache; errors stay failures',
      () async {
        await configure(offeringsCache: cache);
        final previous = InappifySdk.offerings;
        _set(<String, Object?>{'failOfferings': true, 'language': 'fresh'});
        for (var i = 0; i < 5; i++) {
          final failed = await InappifySdk.syncAttributesAndOfferingsIfNeeded();
          expect(failed.isSuccess, isFalse);
          expect(
            failed.failure?.code,
            InappifyFailureCode.network,
            reason: '${failed.failure?.details}',
          );
          expect(
            failed.snapshot?.customerInfo?.attributes?.single.value,
            'fresh',
          );
          expect(
            failed.snapshot?.offerings,
            same(previous),
            reason: '${failed.failure?.details}',
          );
        }
        _invoke('clear');
        _set(<String, Object?>{'now': 1000});
        final limited = await InappifySdk.syncAttributesAndOfferingsIfNeeded();
        expect(_requests, isEmpty);
        if (cache) {
          expect(limited.isSuccess, isTrue);
          expect(
            limited.data?.current?.identifier,
            previous?.current?.identifier,
          );
        } else {
          expect(limited.isSuccess, isFalse);
          expect(
            limited.failure?.details['serverCode'],
            'RATE_LIMITED_NO_CACHE',
          );
          expect(limited.failure?.details['retryAfterMillis'], 59000);
          expect(limited.failure?.isRetryable, isTrue);
        }
        _set(<String, Object?>{'now': 60000, 'failOfferings': false});
        expect(
          (await InappifySdk.syncAttributesAndOfferingsIfNeeded()).isSuccess,
          isTrue,
        );
        expect(_requests, <String>['customerInfo', 'offerings']);
      },
    );
  }

  test(
    'login/logout retain client allowance and never return another customer cache',
    () async {
      await configure();
      for (var i = 0; i < 5; i++) {
        await InappifySdk.syncAttributesAndOfferingsIfNeeded();
      }
      expect(
        (await InappifySdk.loginWithIdentityTicketResult(
          identityTicket: 'test-ticket',
        )).isSuccess,
        isTrue,
      );
      _invoke('clear');
      final account = await InappifySdk.syncAttributesAndOfferingsIfNeeded();
      expect(account.isSuccess, isTrue);
      expect(account.snapshot?.customerInfo?.originalAppUserId, 'account-b');
      expect(_requests, isEmpty);
      _set(<String, Object?>{'failOfferings': true});
      expect(await InappifySdk.logOut(), isTrue);
      _set(<String, Object?>{'failOfferings': false});
      _invoke('clear');
      final anonymous = await InappifySdk.syncAttributesAndOfferingsIfNeeded();
      expect(anonymous.isSuccess, isFalse);
      expect(anonymous.failure?.details['serverCode'], 'RATE_LIMITED_NO_CACHE');
      expect(
        anonymous.snapshot?.customerInfo?.originalAppUserId,
        '$anonymousPrefix'
        'second',
      );
      expect(_requests, isEmpty);
    },
  );

  const policies = <InappifyCacheFetchPolicy, String>{
    InappifyCacheFetchPolicy.cacheOnly: 'CACHE_ONLY',
    InappifyCacheFetchPolicy.fetchCurrent: 'FETCH_CURRENT',
    InappifyCacheFetchPolicy.notStaleCachedOrCurrent:
        'NOT_STALE_CACHED_OR_CURRENT',
    InappifyCacheFetchPolicy.cachedOrFetched: 'CACHED_OR_FETCHED',
  };
  for (final policy in policies.entries) {
    for (final cache in <String>['fresh', 'stale', 'missing']) {
      for (final offline in <bool>[false, true]) {
        test('${policy.value}: cache=$cache offline=$offline', () async {
          await configure();
          if (cache == 'missing') await removeCache();
          if (cache == 'stale') _set(<String, Object?>{'now': 300000});
          _set(<String, Object?>{'failInfo': offline, 'language': 'fresh'});
          final result = await InappifySdk.getCustomerInfoResult(
            fetchPolicy: policy.key,
          );
          expect(_calls.first['policy'], policy.value);
          expect(_calls.first['options'], isTrue);
          final only = policy.key == InappifyCacheFetchPolicy.cacheOnly;
          final hasCache = cache != 'missing';
          final returnsCache =
              hasCache &&
              (only ||
                  policy.key == InappifyCacheFetchPolicy.cachedOrFetched ||
                  (cache == 'fresh' &&
                      policy.key ==
                          InappifyCacheFetchPolicy.notStaleCachedOrCurrent));
          if (only && !hasCache) {
            expect(result.isSuccess, isFalse);
            expect(result.failure?.details['serverCode'], 'CACHE_MISS');
            expect(_requests, isEmpty);
          } else if (returnsCache) {
            expect(result.isSuccess, isTrue);
            expect(result.data?.attributes?.single.value, 'en');
            if (only || cache == 'fresh') expect(_requests, isEmpty);
          } else if (offline) {
            expect(result.isSuccess, isFalse);
            expect(result.failure?.code, InappifyFailureCode.network);
            expect(
              result.snapshot?.customerInfo?.attributes?.single.value,
              hasCache ? 'en' : null,
            );
          } else {
            expect(result.isSuccess, isTrue);
            expect(result.data?.attributes?.single.value, 'fresh');
          }
          // Drain any optional background refresh before disposing this session.
          if (cache == 'stale' &&
              policy.key == InappifyCacheFetchPolicy.cachedOrFetched) {
            await _until(() => _requests.isNotEmpty);
            await Future<void>.delayed(const Duration(milliseconds: 10));
          }
        });
      }
    }
  }

  test('both public defaults send CACHED_OR_FETCHED explicitly', () async {
    await configure();
    expect(await InappifySdk.getCustomerInfo(), isNotNull);
    expect((await InappifySdk.getCustomerInfoResult()).isSuccess, isTrue);
    expect(_calls.map((call) => call['policy']), <String>[
      'CACHED_OR_FETCHED',
      'CACHED_OR_FETCHED',
    ]);
    expect(_requests, isEmpty);
  });

  test(
    'cache-only public read completes while a required network read is held',
    () async {
      await configure();
      _set(<String, Object?>{'holdNext': true});
      final fresh = InappifySdk.getCustomerInfoResult(
        fetchPolicy: InappifyCacheFetchPolicy.fetchCurrent,
      );
      await _until(() => _state['held'] == true);
      final cached = await InappifySdk.getCustomerInfoResult(
        fetchPolicy: InappifyCacheFetchPolicy.cacheOnly,
      ).timeout(const Duration(seconds: 2));
      expect(cached.isSuccess, isTrue);
      expect(_state['held'], isTrue);
      expect(_requests, <String>['customerInfo']);
      _invoke('release');
      expect((await fresh).isSuccess, isTrue);
    },
  );

  test('background refresh reaches public mirror and events', () async {
    await configure();
    _set(<String, Object?>{
      'now': 300000,
      'language': 'fresh',
      'holdNext': true,
    });
    final next = InappifySdk.events.firstWhere(
      (event) => event.type == InappifyPlatformEventType.customerInfoChanged,
    );
    final cached = await InappifySdk.getCustomerInfoResult();
    expect(cached.data?.attributes?.single.value, 'en');
    await _until(() => _state['held'] == true);
    _invoke('release');
    final updated = await next.timeout(
      const Duration(seconds: 2),
      onTimeout: () => throw TestFailure(
        'Missing Flutter event; provider events=${_state['emitted']}; mirror=${InappifySdk.customerInfo?.attributes?.single.value}',
      ),
    );
    expect(updated.snapshot?.customerInfo?.attributes?.single.value, 'fresh');
    expect(InappifySdk.customerInfo?.attributes?.single.value, 'fresh');
  });

  test(
    'CACHE_MISS also returns immediately while a missing-cache fetch is pending',
    () async {
      await configure();
      await removeCache();
      _set(<String, Object?>{'holdNext': true});
      final fresh = InappifySdk.getCustomerInfoResult(
        fetchPolicy: InappifyCacheFetchPolicy.fetchCurrent,
      );
      await _until(() => _state['held'] == true);
      final missing = await InappifySdk.getCustomerInfoResult(
        fetchPolicy: InappifyCacheFetchPolicy.cacheOnly,
      ).timeout(const Duration(seconds: 2));
      expect(missing.isSuccess, isFalse);
      expect(missing.failure?.details['serverCode'], 'CACHE_MISS');
      expect(_state['held'], isTrue);
      expect(_requests, <String>['customerInfo']);
      _invoke('release');
      expect((await fresh).isSuccess, isTrue);
    },
  );

  for (final transition in <String>['fetchCurrent', 'login', 'logout']) {
    test('late background response cannot undo $transition', () async {
      await configure();
      _set(<String, Object?>{'now': 300000, 'holdNext': true});
      await InappifySdk.getCustomerInfoResult();
      await _until(() => _state['held'] == true);
      _set(<String, Object?>{'language': 'new-account-value'});
      if (transition == 'login') {
        expect(
          (await InappifySdk.loginWithIdentityTicketResult(
            identityTicket: 'test-ticket',
          )).isSuccess,
          isTrue,
        );
      } else if (transition == 'logout') {
        expect(await InappifySdk.logOut(), isTrue);
      } else {
        expect(
          (await InappifySdk.getCustomerInfoResult(
            fetchPolicy: InappifyCacheFetchPolicy.fetchCurrent,
          )).isSuccess,
          isTrue,
        );
      }
      final current = InappifySdk.customerInfo;
      final events = <InappifyPlatformEvent>[];
      final sub = InappifySdk.events.listen(events.add);
      _invoke('release');
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(InappifySdk.customerInfo, same(current));
      expect(
        events.where(
          (event) =>
              event.type == InappifyPlatformEventType.customerInfoChanged,
        ),
        isEmpty,
      );
      await sub.cancel();
    });
  }

  test(
    'cancellation options and AbortSignal are the second JS argument',
    () async {
      await configure();
      _set(<String, Object?>{'holdNext': true});
      final cancellation = InappifyRequestCancellation();
      final pending = platform.getCustomerInfo(
        InappifyRefreshRequest(
          fetchPolicy: InappifyCacheFetchPolicy.fetchCurrent,
          cancellation: cancellation,
        ),
      );
      await _until(() => _state['held'] == true);
      expect(_calls.single['policy'], 'FETCH_CURRENT');
      expect(_calls.single['signal'], isTrue);
      cancellation.cancel();
      _invoke('release');
      expect(
        (await pending).failure?.code,
        InappifyFailureCode.requestCancelled,
      );
      expect(InappifySdk.customerInfo, isNotNull);
    },
  );

  test(
    'bridge copies only a valid numeric retry delay from provider error details',
    () async {
      await configure();
      final host = globalContext.getProperty<JSObject>(
        '__inappifyFlutterWebSdk'.toJS,
      );
      // A separate controlled bridge instance exercises actual JS exception
      // normalization without exposing a raw error/details object to Dart.
      final target = host.getProperty<JSObject>('InAppify'.toJS);
      final original = target.getProperty<JSAny?>('configure'.toJS);
      for (final delay in <Object?>[
        59000,
        -1,
        '59000',
        1.5,
        double.infinity,
        null,
      ]) {
        final session = JSObject();
        final error = <String, Object?>{
          'code': 'RATE_LIMITED_NO_CACHE',
          'kind': 'configuration',
          'details': <String, Object?>{
            'retryAfterMillis': delay,
            'accessToken': 'never-copy-this',
          },
        }.jsify();
        session.setProperty(
          'on'.toJS,
          ((JSAny? a, JSAny? b) => (() {}).toJS).toJS,
        );
        session.setProperty(
          'syncAttributesAndOfferingsIfNeeded'.toJS,
          (() => _reject(error)).toJS,
        );
        target.setProperty(
          'configure'.toJS,
          ((JSAny? options) => session).toJS,
        );
        final probe = JavaScriptInappifyBridge();
        await probe.configure(<String, Object?>{});
        try {
          await probe.call('syncAttributesAndOfferingsIfNeeded');
          fail('Expected provider error');
        } on InappifyWebBridgeException catch (error) {
          expect(error.code, 'RATE_LIMITED_NO_CACHE');
          expect(error.retryAfterMillis, delay == 59000 ? 59000 : null);
          expect(error.toString(), isNot(contains('never-copy-this')));
        } finally {
          await probe.dispose();
        }
      }
      target.setProperty('configure'.toJS, original);
    },
  );
}

const anonymousPrefix = r'$InaAnonymousId_';
JSObject get _harness =>
    globalContext.getProperty<JSObject>('__inappifyProviderTest'.toJS);
void _invoke(String method) => _harness.callMethodVarArgs<JSAny?>(method.toJS);
void _set(Map<String, Object?> values) =>
    _harness.callMethodVarArgs<JSAny?>('set'.toJS, <JSAny?>[values.jsify()]);
Map<String, dynamic> get _state {
  final raw = _harness.callMethodVarArgs<JSAny?>('read'.toJS);
  final json = globalContext.getProperty<JSObject>('JSON'.toJS);
  return jsonDecode(
        (json.callMethodVarArgs<JSString>('stringify'.toJS, <JSAny?>[
          raw,
        ])).toDart,
      )
      as Map<String, dynamic>;
}

List<String> get _requests => (_state['requests'] as List).cast<String>();
List<Map<String, dynamic>> get _calls =>
    (_state['calls'] as List).cast<Map<String, dynamic>>();
JSPromise<JSAny?> _reject(JSAny? error) => globalContext
    .getProperty<JSObject>('Promise'.toJS)
    .callMethodVarArgs<JSPromise<JSAny?>>('reject'.toJS, <JSAny?>[error]);
Future<void> _until(bool Function() ready) async {
  final deadline = DateTime.now().add(const Duration(seconds: 3));
  while (!ready()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('Provider operation did not reach expected state');
    }
    await Future<void>.delayed(const Duration(milliseconds: 1));
  }
}

Future<void> _load(String src) async {
  final completed = Completer<void>();
  final script = web.HTMLScriptElement()..src = src;
  script.addEventListener('load', ((web.Event _) => completed.complete()).toJS);
  script.addEventListener(
    'error',
    ((web.Event _) => completed.completeError(
      StateError(
        'Cannot load $src. Run node tool/prepare_web_provider_test.mjs first.',
      ),
    )).toJS,
  );
  web.document.head!.append(script);
  await completed.future;
}
