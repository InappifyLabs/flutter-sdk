import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:inappify_sdk/models/attribute.dart';
import 'package:inappify_sdk/models/enums/market.dart';
import 'package:inappify_sdk/models/enums/purchase_status.dart';
import 'package:inappify_sdk/models/mobile_v2.dart';
import 'package:inappify_sdk/request_cancellation.dart';
import 'package:inappify_sdk/session_state.dart';
import 'package:inappify_sdk/src/platform/contracts/backend_capabilities.dart';
import 'package:inappify_sdk/src/platform/contracts/platform_event.dart';
import 'package:inappify_sdk/src/platform/contracts/sdk_failure.dart';
import 'package:inappify_sdk/src/platform/contracts/sdk_requests.dart';
import 'package:inappify_sdk/src/platform/contracts/sdk_result.dart';
import 'package:inappify_sdk/src/platform/web/web_inappify_bridge.dart';
import 'package:inappify_sdk/src/platform/web/web_inappify_platform.dart';

void main() {
  late _FakeWebBridge bridge;
  late WebInappifyPlatform platform;

  setUp(() {
    bridge = _FakeWebBridge(
      properties: <String, Object?>{
        'customerInfo': _customerPayload(),
        'offerings': _offeringsPayload(),
        'sessionState': 'anonymous',
        'persistenceMode': 'durable',
      },
    );
    platform = WebInappifyPlatform(bridge: bridge);
  });

  tearDown(() async {
    await platform.dispose();
  });

  group('capability and session ownership', () {
    test(
      'reports an unavailable non-owning backend when JS host is absent',
      () async {
        bridge.available = false;

        final capabilities = await platform.getCapabilities();

        expect(capabilities.backendKind, InappifyBackendKind.webJavaScript);
        expect(capabilities.ownsSession, isFalse);
        expect(capabilities.supportsCompleteLifecycle, isFalse);
      },
    );

    test(
      'advertises the complete documented Web lifecycle when available',
      () async {
        bridge.version = '0.2.0';

        final capabilities = await platform.getCapabilities();

        expect(capabilities.backendKind, InappifyBackendKind.webJavaScript);
        expect(capabilities.sdkVersion, '0.2.0');
        expect(capabilities.supportsCompleteLifecycle, isTrue);
        expect(
          capabilities.supportedOperations,
          containsAll(<InappifyOperation>{
            InappifyOperation.exchangeIdentityTicket,
            InappifyOperation.requestOtp,
            InappifyOperation.createOtpCaptcha,
            InappifyOperation.getCurrentOffering,
            InappifyOperation.handlePaymentReturn,
            InappifyOperation.createCheckout,
            InappifyOperation.getCheckoutStatus,
            InappifyOperation.syncAttributesAndOfferingsIfNeeded,
          }),
        );
      },
    );

    test(
      'rejects Web SDK builds older than the 0.2.0 policy contract',
      () async {
        for (final version in <String?>[
          null,
          'invalid',
          '0.1.0-beta.2',
          '0.1.0',
          '0.2.0-beta.1',
        ]) {
          bridge.version = version;
          final capabilities = await platform.getCapabilities();
          expect(capabilities.ownsSession, isFalse, reason: version);
          expect(
            capabilities.supportsCompleteLifecycle,
            isFalse,
            reason: version,
          );
        }
      },
    );

    test('accepts 0.2.0 and newer session contracts', () async {
      for (final version in <String>['0.2.0', '0.2.1', '1.0.0']) {
        bridge.version = version;
        final capabilities = await platform.getCapabilities();
        expect(capabilities.ownsSession, isTrue, reason: version);
      }
    });

    test(
      'configure sends only documented browser options and mirrors state',
      () async {
        const request = InappifyConfigureRequest(
          apiKey: 'public-web-key',
          country: 'IR',
          appVersion: '1.2.0',
          enableSubscriptionRecoveryWithoutPayload: false,
        );

        final result = await platform.configure(request);

        expect(result.isSuccess, isTrue);
        expect(bridge.configureOptions, <String, Object?>{
          'apiKey': 'public-web-key',
          'baseUrl': 'https://api.inappify.com/api/web/v1',
          'country': 'IR',
          'appVersion': '1.2.0',
        });
        expect(result.snapshot?.accessToken, isNull);
        expect(result.snapshot?.apiKey, 'public-web-key');
        expect(result.snapshot?.country, 'IR');
        expect(result.snapshot?.versionName, '1.2.0');
        expect(result.snapshot?.sessionState, InappifySessionState.anonymous);
        expect(
          result.snapshot?.persistenceMode,
          InappifySessionPersistenceMode.durable,
        );
        expect(result.snapshot?.customerInfo?.originalAppUserId, 'anonymous-1');
        expect(
          result.snapshot?.offerings?.defaultOffering()?.identifier,
          'main',
        );
      },
    );

    test(
      'does not recreate a healthy session for identical configure calls',
      () async {
        const request = InappifyConfigureRequest(
          apiKey: 'public-web-key',
          country: 'IR',
          appVersion: '1.2.0',
        );

        final first = await platform.configure(request);
        final second = await platform.configure(request);

        expect(first.isSuccess, isTrue);
        expect(second.isSuccess, isTrue);
        expect(bridge.configureCount, 1);
        expect(
          second.snapshot?.customerInfo,
          same(first.snapshot?.customerInfo),
        );
      },
    );

    test('captures beta.1 application and SDK metadata in snapshots', () async {
      bridge.version = '0.1.0-beta.1';
      bridge.properties['configuration'] = <String, Object?>{
        'app': <String, Object?>{'id': 73},
      };
      bridge.properties['offerings'] = _offeringsPayload(
        forceVersion: 12,
        fetchedAt: '2026-08-11T10:00:00Z',
      );

      final result = await platform.configure(
        const InappifyConfigureRequest(
          apiKey: 'public-web-key',
          country: 'IR',
          appVersion: '1.2.0',
        ),
      );

      expect(result.isSuccess, isTrue);
      expect(result.snapshot?.appId, 73);
      expect(result.snapshot?.sdkVersion, '0.1.0-beta.1');
      expect(result.snapshot?.forceVersion, 12);
      expect(result.snapshot?.offerings?.forceVersion, 12);
      expect(result.snapshot?.offerings?.fetchedAt, '2026-08-11T10:00:00Z');
    });

    test(
      'failed reconfiguration preserves the previous authoritative session',
      () async {
        await _configure(platform);
        bridge.configureError = const InappifyWebBridgeException(
          code: 'network_error',
          status: 503,
        );

        final failed = await platform.configure(
          const InappifyConfigureRequest(
            apiKey: 'replacement-public-key',
            country: 'DE',
            appVersion: '2.0.0',
          ),
        );

        expect(failed.failure?.code, InappifyFailureCode.network);
        expect(failed.failure?.details['outcomeMayHaveCommitted'], isTrue);
        expect(failed.snapshot?.apiKey, 'public-web-key');
        expect(failed.snapshot?.country, 'IR');
        expect(failed.snapshot?.versionName, '1.0.0');
        expect(failed.snapshot?.customerInfo?.originalAppUserId, 'anonymous-1');

        bridge.configureError = null;
        bridge.properties['customerInfo'] = _customerPayload(
          customerId: 'replacement-customer',
        );
        final succeeded = await platform.configure(
          const InappifyConfigureRequest(
            apiKey: 'replacement-public-key',
            country: 'DE',
            appVersion: '2.0.0',
          ),
        );

        expect(succeeded.isSuccess, isTrue);
        expect(succeeded.snapshot?.apiKey, 'replacement-public-key');
        expect(succeeded.snapshot?.country, 'DE');
        expect(succeeded.snapshot?.versionName, '2.0.0');
        expect(
          succeeded.snapshot?.customerInfo?.originalAppUserId,
          'replacement-customer',
        );
      },
    );

    test(
      'successful reconfiguration never retains stale app mirrors',
      () async {
        bridge.properties['configuration'] = <String, Object?>{
          'app': <String, Object?>{'id': 41},
        };
        bridge.properties['offerings'] = _offeringsPayload(forceVersion: 9);
        await _configure(platform);
        bridge.properties['configuration'] = 'malformed-configuration';
        bridge.properties['customerInfo'] = 'malformed-customer';
        bridge.properties['offerings'] = 'malformed-offerings';

        final result = await platform.configure(
          const InappifyConfigureRequest(
            apiKey: 'replacement-public-key',
            country: 'DE',
            appVersion: '2.0.0',
          ),
        );

        expect(result.isSuccess, isTrue);
        expect(result.snapshot?.apiKey, 'replacement-public-key');
        expect(result.snapshot?.customerInfo, isNull);
        expect(result.snapshot?.offerings, isNull);
        expect(result.snapshot?.appId, isNull);
        expect(result.snapshot?.forceVersion, 1);
        expect(result.snapshot?.failedToLoadCustomerInfo, isTrue);
        expect(result.snapshot?.failedToLoadOfferings, isTrue);
      },
    );

    test('drops native-only options before configuring JavaScript', () async {
      final result = await platform.configure(
        const InappifyConfigureRequest(
          apiKey: 'public-web-key',
          market: Market.myket,
          marketKey: 'native-or-server-key',
        ),
      );

      expect(result.isSuccess, isTrue);
      expect(bridge.configureOptions, <String, Object?>{
        'apiKey': 'public-web-key',
        'baseUrl': 'https://api.inappify.com/api/web/v1',
      });
      expect(bridge.configureOptions, isNot(contains('market')));
      expect(bridge.configureOptions, isNot(contains('marketKey')));
    });

    test('accepts only the exact Web anonymous identifier prefix', () async {
      final accepted = await platform.configure(
        const InappifyConfigureRequest(
          apiKey: 'public-web-key',
          appUserIdentifier: r'$InaAnonymousId_browser-1',
        ),
      );
      final rejected = await platform.configure(
        const InappifyConfigureRequest(
          apiKey: 'public-web-key',
          appUserIdentifier: r'prefix-$InaAnonymousId_browser-1',
        ),
      );

      expect(accepted.isSuccess, isTrue);
      expect(rejected.failure?.code, InappifyFailureCode.invalidConfiguration);
      expect(bridge.configureCount, 1);
    });

    test('legacy direct login is explicitly unsupported', () async {
      await _configure(platform);

      final result = await platform.login(
        const InappifyLoginRequest(appUserIdentifier: 'customer-1'),
      );

      expect(result.failure?.code, InappifyFailureCode.unsupportedOperation);
      expect(result.snapshot, isNotNull);
      expect(bridge.calls, isEmpty);
    });

    test('operations fail safely before a session is configured', () async {
      final result = await platform.getCustomerInfo(
        const InappifyRefreshRequest(),
      );

      expect(result.failure?.code, InappifyFailureCode.notConfigured);
      expect(bridge.calls, isEmpty);
    });
  });

  group('Web 0.2.0 customer policies and targeting sync', () {
    test(
      'does not advertise a method absent from the actual provider',
      () async {
        bridge.hasTargetingSync = false;
        final capabilities = await platform.getCapabilities();
        expect(
          capabilities.supportedOperations,
          isNot(contains(InappifyOperation.syncAttributesAndOfferingsIfNeeded)),
        );
        await _configure(platform);
        bridge.calls.clear();
        final result = await platform.syncAttributesAndOfferingsIfNeeded();
        expect(result.failure?.code, InappifyFailureCode.unsupportedOperation);
        expect(bridge.calls, isEmpty);
      },
    );
    for (final entry in <InappifyCacheFetchPolicy, String>{
      InappifyCacheFetchPolicy.cacheOnly: 'CACHE_ONLY',
      InappifyCacheFetchPolicy.fetchCurrent: 'FETCH_CURRENT',
      InappifyCacheFetchPolicy.notStaleCachedOrCurrent:
          'NOT_STALE_CACHED_OR_CURRENT',
      InappifyCacheFetchPolicy.cachedOrFetched: 'CACHED_OR_FETCHED',
    }.entries) {
      test(
        'forwards ${entry.value} and cancellation as the second argument',
        () async {
          await _configure(platform);
          bridge.calls.clear();
          bridge.callResponses['getCustomerInfo'] = _customerPayload();
          final cancellation = InappifyRequestCancellation();
          final result = await platform.getCustomerInfo(
            InappifyRefreshRequest(
              fetchPolicy: entry.key,
              cancellation: cancellation,
            ),
          );
          expect(result.isSuccess, isTrue);
          expect(bridge.calls.single.positionalArguments, <Object?>[
            entry.value,
            <String, Object?>{},
          ]);
          expect(bridge.calls.single.injectAbortSignal, isTrue);
          expect(bridge.calls.single.cancellation, same(cancellation));
        },
      );
    }

    test(
      'default is explicit CACHED_OR_FETCHED; internal forced read stays fresh',
      () async {
        await _configure(platform);
        bridge.calls.clear();
        bridge.callResponses['getCustomerInfo'] = _customerPayload();
        await platform.getCustomerInfo(const InappifyRefreshRequest());
        await platform.getCustomerInfo(
          const InappifyRefreshRequest(force: true),
        );
        expect(
          bridge.calls.map((call) => call.positionalArguments.first),
          <String>['CACHED_OR_FETCHED', 'FETCH_CURRENT'],
        );
      },
    );

    test(
      'delegates combined sync once and preserves partial success on failure',
      () async {
        final configured = await _configure(platform);
        bridge.calls.clear();
        bridge.callHandlers['syncAttributesAndOfferingsIfNeeded'] = (_) {
          bridge.properties['customerInfo'] = _customerPayload(
            attributes: <String, Object?>{'language': 'ar'},
          );
          throw const InappifyWebBridgeException(
            code: 'NETWORK_ERROR',
            kind: 'network',
          );
        };
        final failed = await platform.syncAttributesAndOfferingsIfNeeded();
        expect(failed.isSuccess, isFalse);
        expect(
          failed.snapshot?.offerings,
          same(configured.snapshot?.offerings),
        );
        expect(failed.snapshot?.customerInfo?.attributes?.single.value, 'ar');
        expect(
          bridge.calls.single.method,
          'syncAttributesAndOfferingsIfNeeded',
        );

        bridge.callHandlers.remove('syncAttributesAndOfferingsIfNeeded');
        bridge.callResponses['syncAttributesAndOfferingsIfNeeded'] =
            _offeringsPayload(forceVersion: 9);
        final succeeded = await platform.syncAttributesAndOfferingsIfNeeded();
        expect(succeeded.isSuccess, isTrue);
        expect(succeeded.data?.forceVersion, 9);
        expect(succeeded.snapshot?.offerings, same(succeeded.data));
      },
    );

    test(
      'retains server codes and only valid allowlisted retry timing',
      () async {
        await _configure(platform);
        for (final delay in <int?>[59000, -1, null]) {
          bridge.callHandlers['syncAttributesAndOfferingsIfNeeded'] = (_) {
            throw InappifyWebBridgeException(
              code: 'RATE_LIMITED_NO_CACHE',
              kind: 'configuration',
              retryAfterMillis: delay,
            );
          };
          final result = await platform.syncAttributesAndOfferingsIfNeeded();
          expect(result.isSuccess, isFalse);
          expect(
            result.failure?.details['serverCode'],
            'RATE_LIMITED_NO_CACHE',
          );
          expect(result.failure?.isRetryable, isTrue);
          expect(
            result.failure?.details['retryAfterMillis'],
            delay != null && delay >= 0 ? delay : null,
          );
        }
        bridge.callHandlers['getCustomerInfo'] = (_) =>
            throw const InappifyWebBridgeException(
              code: 'CACHE_MISS',
              kind: 'configuration',
            );
        final missing = await platform.getCustomerInfo(
          const InappifyRefreshRequest(
            fetchPolicy: InappifyCacheFetchPolicy.cacheOnly,
          ),
        );
        expect(missing.failure?.details['serverCode'], 'CACHE_MISS');
      },
    );

    test(
      'does not replace a newer event with a late cached response',
      () async {
        await _configure(platform);
        final pending = Completer<Object?>();
        bridge.callHandlers['getCustomerInfo'] = (_) => pending.future;
        final result = platform.getCustomerInfo(const InappifyRefreshRequest());
        bridge.emit(
          InappifyWebBridgeEvent(
            name: 'customerInfoUpdated',
            payload: _customerPayload(
              attributes: <String, Object?>{'language': 'fresh'},
            ),
          ),
        );
        pending.complete(_customerPayload());
        expect(
          (await result).snapshot?.customerInfo?.attributes?.single.value,
          'fresh',
        );
      },
    );

    test(
      'does not commit a read superseded by an identity replacement',
      () async {
        await _configure(platform);
        final pending = Completer<Object?>();
        bridge.callHandlers['getCustomerInfo'] = (_) => pending.future;
        final result = platform.getCustomerInfo(
          const InappifyRefreshRequest(
            fetchPolicy: InappifyCacheFetchPolicy.fetchCurrent,
          ),
        );
        bridge.emit(
          const InappifyWebBridgeEvent(
            name: 'sessionStateChanged',
            payload: <String, Object?>{
              'state': 'authenticated',
              'retryable': false,
            },
          ),
        );
        bridge.emit(
          InappifyWebBridgeEvent(
            name: 'customerInfoUpdated',
            payload: _customerPayload(customerId: 'new-account'),
          ),
        );
        pending.complete(_customerPayload());
        final late = await result;
        expect(late.isSuccess, isFalse);
        expect(late.snapshot?.customerInfo?.originalAppUserId, 'new-account');
      },
    );
  });

  group('identity and OTP', () {
    test(
      'exchanges one Identity Ticket once and refreshes cached state',
      () async {
        await _configure(platform);
        bridge.calls.clear();
        bridge.callResponses['exchangeIdentityTicket'] =
            _authenticationPayload();
        bridge.properties['customerInfo'] = _customerPayload(
          customerId: 'authenticated-1',
        );

        final result = await platform.exchangeIdentityTicket(
          const InappifyIdentityTicketRequest(
            identityTicket: 'single-use-ticket',
          ),
        );

        expect(result.isSuccess, isTrue);
        expect(result.data?.isAnonymous, isFalse);
        expect(result.data?.type, 'Authenticated');
        expect(result.snapshot?.accessToken, isNull);
        expect(
          result.snapshot?.customerInfo?.originalAppUserId,
          'authenticated-1',
        );
        expect(bridge.calls.single.method, 'exchangeIdentityTicket');
        expect(bridge.calls.single.positionalArguments, <Object?>[
          'single-use-ticket',
        ]);
      },
    );

    test(
      'keeps successful authentication when follow-up cache data is bad',
      () async {
        await _configure(platform);
        bridge.calls.clear();
        bridge.callResponses['exchangeIdentityTicket'] =
            _authenticationPayload();
        bridge.properties['customerInfo'] = 'malformed-customer';

        final result = await platform.exchangeIdentityTicket(
          const InappifyIdentityTicketRequest(
            identityTicket: 'single-use-ticket',
          ),
        );

        expect(result.isSuccess, isTrue);
        expect(result.data?.isAnonymous, isFalse);
        expect(result.snapshot?.failedToLoadCustomerInfo, isTrue);
        expect(result.snapshot?.customerInfo, isNull);
        expect(result.snapshot?.failedToLoadOfferings, isFalse);
      },
    );

    test(
      'keeps a newer authentication event snapshot during failed refresh',
      () async {
        await _configure(platform);
        bridge.calls.clear();
        bridge.callHandlers['exchangeIdentityTicket'] = (_) {
          bridge.emit(
            InappifyWebBridgeEvent(
              name: 'customerInfoUpdated',
              payload: _customerPayload(customerId: 'event-customer'),
            ),
          );
          return _authenticationPayload();
        };
        bridge.properties['customerInfo'] = 'malformed-customer';

        final result = await platform.exchangeIdentityTicket(
          const InappifyIdentityTicketRequest(
            identityTicket: 'single-use-ticket',
          ),
        );

        expect(result.isSuccess, isTrue);
        expect(result.snapshot?.failedToLoadCustomerInfo, isTrue);
        expect(
          result.snapshot?.customerInfo?.originalAppUserId,
          'event-customer',
        );
      },
    );

    test(
      'does not expose the previous customer after a committed auth mutation',
      () async {
        await _configure(platform);
        bridge.calls.clear();
        bridge.callHandlers['exchangeIdentityTicket'] = (_) {
          bridge.properties['sessionState'] = 'authenticated';
          bridge.properties['customerInfo'] = null;
          bridge.emit(
            const InappifyWebBridgeEvent(
              name: 'sessionStateChanged',
              payload: <String, Object?>{
                'state': 'authenticated',
                'retryable': false,
              },
            ),
          );
          throw const InappifyWebBridgeException(
            code: 'NETWORK_ERROR',
            kind: 'network',
          );
        };

        final result = await platform.exchangeIdentityTicket(
          const InappifyIdentityTicketRequest(
            identityTicket: 'single-use-ticket',
          ),
        );

        expect(result.failure?.code, InappifyFailureCode.network);
        expect(result.failure?.details['outcomeMayHaveCommitted'], isTrue);
        expect(
          result.snapshot?.sessionState,
          InappifySessionState.authenticated,
        );
        expect(result.snapshot?.customerInfo, isNull);
        expect(result.snapshot?.offerings, isNull);
      },
    );

    test('uses the documented requestOtp and verifyOtp signatures', () async {
      await _configure(platform);
      bridge.calls.clear();
      bridge.callResponses['requestOtp'] = <String, Object?>{
        'challengeId': 'challenge-1',
        'expiresAt': '2026-08-11T10:01:00Z',
      };
      bridge.callResponses['verifyOtp'] = _authenticationPayload();

      final challenge = await platform.requestOtp(
        const InappifyOtpRequest(phone: '09121234567'),
      );
      final authentication = await platform.verifyOtp(
        const InappifyOtpVerificationRequest(
          challengeId: 'challenge-1',
          code: '123456',
        ),
      );

      expect(challenge.data?.challengeId, 'challenge-1');
      expect(authentication.data?.isAnonymous, isFalse);
      expect(bridge.calls[0].method, 'requestOtp');
      expect(bridge.calls[0].positionalArguments, <Object?>[
        <String, Object?>{'phone': '09121234567'},
      ]);
      expect(bridge.calls[1].method, 'verifyOtp');
      expect(bridge.calls[1].positionalArguments, <Object?>[
        'challenge-1',
        '123456',
      ]);
    });

    test('creates CAPTCHA and sends it back with the OTP request', () async {
      await _configure(platform);
      bridge.calls.clear();
      bridge.callResponses['createOtpCaptcha'] = <String, Object?>{
        'captchaKey': 'captcha-1',
        'captchaImage': 'data:image/png;base64,AAAA',
        'expiresIn': 120,
      };
      bridge.callResponses['requestOtp'] = <String, Object?>{
        'challengeId': 'challenge-1',
        'expiresAt': '2026-08-11T10:01:00Z',
      };
      final cancellation = InappifyRequestCancellation();

      final captcha = await platform.createOtpCaptcha(
        InappifyNetworkRequest(cancellation: cancellation),
      );
      final challenge = await platform.requestOtp(
        InappifyOtpRequest(
          phone: '09121234567',
          captchaKey: captcha.data?.captchaKey,
          captchaAnswer: '7KQ2',
          cancellation: cancellation,
        ),
      );

      expect(captcha.data?.captchaKey, 'captcha-1');
      expect(captcha.data?.captchaImage, 'data:image/png;base64,AAAA');
      expect(captcha.data?.expiresIn, 120);
      expect(challenge.data?.challengeId, 'challenge-1');
      expect(bridge.calls[0].method, 'createOtpCaptcha');
      expect(bridge.calls[0].positionalArguments, <Object?>[
        const <String, Object?>{},
      ]);
      expect(bridge.calls[0].cancellation, same(cancellation));
      expect(bridge.calls[0].injectAbortSignal, isTrue);
      expect(bridge.calls[1].method, 'requestOtp');
      expect(bridge.calls[1].positionalArguments, <Object?>[
        <String, Object?>{
          'phone': '09121234567',
          'captchaKey': 'captcha-1',
          'captchaAnswer': '7KQ2',
        },
        const <String, Object?>{},
      ]);
      expect(bridge.calls[1].cancellation, same(cancellation));
      expect(bridge.calls[1].injectAbortSignal, isTrue);
    });

    test('pre-cancelled CAPTCHA never crosses the JS boundary', () async {
      await _configure(platform);
      bridge.calls.clear();
      final cancellation = InappifyRequestCancellation()..cancel();

      final result = await platform.createOtpCaptcha(
        InappifyNetworkRequest(cancellation: cancellation),
      );

      expect(result.failure?.code, InappifyFailureCode.requestCancelled);
      expect(bridge.calls, isEmpty);
    });
  });

  group('offerings, customer, and configuration', () {
    test(
      'forwards forceRefresh and an injectable cancellation handle',
      () async {
        await _configure(platform);
        bridge.calls.clear();
        bridge.callResponses['getOfferings'] = _offeringsPayload();
        final cancellation = InappifyRequestCancellation();

        final result = await platform.getOfferings(
          InappifyRefreshRequest(force: true, cancellation: cancellation),
        );

        expect(result.isSuccess, isTrue);
        expect(bridge.calls.single.method, 'getOfferings');
        expect(bridge.calls.single.positionalArguments, <Object?>[
          <String, Object?>{'forceRefresh': true},
        ]);
        expect(bridge.calls.single.cancellation, same(cancellation));
        expect(bridge.calls.single.injectAbortSignal, isTrue);
      },
    );

    test(
      'does not cross the bridge when cancellation already happened',
      () async {
        await _configure(platform);
        bridge.calls.clear();
        final cancellation = InappifyRequestCancellation()..cancel();

        final result = await platform.getOfferings(
          InappifyRefreshRequest(cancellation: cancellation),
        );

        expect(result.failure?.code, InappifyFailureCode.requestCancelled);
        expect(bridge.calls, isEmpty);
      },
    );

    test(
      'maps an in-flight AbortSignal cancellation to a domain failure',
      () async {
        await _configure(platform);
        bridge.calls.clear();
        final cancellation = InappifyRequestCancellation();
        bridge.callHandlers['getOfferings'] = (invocation) async {
          expect(invocation.cancellation, same(cancellation));
          await cancellation.whenCancelled.first;
          throw const InappifyWebBridgeException(
            code: 'aborted',
            name: 'AbortError',
          );
        };

        final operation = platform.getOfferings(
          InappifyRefreshRequest(cancellation: cancellation),
        );
        await Future<void>.delayed(Duration.zero);
        cancellation.cancel();
        final result = await operation;

        expect(result.failure?.code, InappifyFailureCode.requestCancelled);
        expect(result.failure?.isRetryable, isFalse);
      },
    );

    test(
      'decodes amount for modern and compatibility price accessors',
      () async {
        await _configure(platform);
        bridge.calls.clear();
        bridge.callResponses['getCurrentOffering'] = _offeringPayload();

        final result = await platform.getCurrentOffering(
          InappifyCurrentOfferingRequest(
            placementIdentifier: 'website_pricing',
          ),
        );

        final price = result.data?.packages?.single.product?.prices?.single;
        expect(price?.amount, 190000);
        expect(price?.price, 190000);
        expect(bridge.calls.single.positionalArguments, <Object?>[
          <String, Object?>{
            'placementIdentifier': 'website_pricing',
            'forceRefresh': false,
          },
        ]);
      },
    );

    test('checks entitlement with the documented refresh option', () async {
      await _configure(platform);
      bridge.calls.clear();
      bridge.callResponses['checkEntitlement'] = true;

      final result = await platform.checkEntitlement(
        const InappifyEntitlementCheckRequest(
          identifier: 'premium',
          forceRefresh: false,
        ),
      );

      expect(result.data, isTrue);
      expect(bridge.calls.single.positionalArguments, <Object?>[
        'premium',
        <String, Object?>{'forceRefresh': false},
      ]);
    });

    test(
      'returns configuration while recursively removing credentials',
      () async {
        await _configure(platform);
        bridge.properties['configuration'] = <String, Object?>{
          'offeringsEnabled': true,
          'accessToken': 'secret-access',
          'nested': <String, Object?>{
            'refresh_token': 'secret-refresh',
            'allowedReservedAttributes': <String>[r'$email'],
          },
        };

        final result = await platform.getConfiguration();
        final values = result.data?.toMap();
        final nested = values?['nested'] as Map<Object?, Object?>;

        expect(values, isNot(contains('accessToken')));
        expect(nested, isNot(contains('refresh_token')));
        expect(nested['allowedReservedAttributes'], <String>[r'$email']);
      },
    );
  });

  group('attributes', () {
    test(
      'uses map, key-list, and value-list shapes required by Web SDK',
      () async {
        await _configure(platform);
        bridge.calls.clear();
        bridge.properties['customerInfo'] = _customerPayload(
          attributes: <String, Object?>{'language': 'fa'},
        );

        final updated = await platform.setAttributes(
          InappifyAttributesRequest(
            attributes: <Attribute>[
              Attribute(key: 'language', value: 'fa'),
              Attribute(key: 'theme', value: null),
            ],
          ),
        );
        await platform.deleteAttributes(
          InappifyDeleteAttributesRequest(keys: <String>['theme']),
        );
        await platform.syncAttributeValues(
          InappifyAttributesRequest(
            attributes: <Attribute>[Attribute(key: 'language', value: 'fa')],
          ),
        );

        expect(updated.data?.single.key, 'language');
        expect(bridge.calls[0].method, 'syncAttributes');
        expect(bridge.calls[0].positionalArguments, <Object?>[
          <Object?>[
            <String, Object?>{'key': 'language', 'value': 'fa'},
            <String, Object?>{'key': 'theme', 'value': null},
          ],
        ]);
        expect(bridge.calls[1].method, 'deleteAttributes');
        expect(bridge.calls[1].positionalArguments, <Object?>[
          <String>['theme'],
        ]);
        expect(bridge.calls[2].method, 'syncAttributes');
        expect(bridge.calls[2].positionalArguments, <Object?>[
          <Object?>[
            <String, Object?>{'key': 'language', 'value': 'fa'},
          ],
        ]);
      },
    );

    test(
      'maps every documented reserved setter and rejects browser IP writes',
      () async {
        await _configure(platform);
        bridge.calls.clear();
        bridge.callResponses['canSetReservedAttribute'] = true;
        const cases =
            <
              ({
                InappifyReservedAttribute attribute,
                String setter,
                String value,
              })
            >[
              (
                attribute: InappifyReservedAttribute.email,
                setter: 'setEmail',
                value: 'user@example.com',
              ),
              (
                attribute: InappifyReservedAttribute.apnsToken,
                setter: 'setApnsToken',
                value: 'apns-token',
              ),
              (
                attribute: InappifyReservedAttribute.displayName,
                setter: 'setDisplayName',
                value: 'Example User',
              ),
              (
                attribute: InappifyReservedAttribute.fcmToken,
                setter: 'setFcmToken',
                value: 'fcm-token',
              ),
              (
                attribute: InappifyReservedAttribute.idfa,
                setter: 'setIdfa',
                value: 'idfa-value',
              ),
              (
                attribute: InappifyReservedAttribute.idfv,
                setter: 'setIdfv',
                value: 'idfv-value',
              ),
              (
                attribute: InappifyReservedAttribute.phoneNumber,
                setter: 'setPhoneNumber',
                value: '09121234567',
              ),
              (
                attribute: InappifyReservedAttribute.campaign,
                setter: 'setCampaign',
                value: 'summer-2026',
              ),
              (
                attribute: InappifyReservedAttribute.keyword,
                setter: 'setKeyword',
                value: 'pricing',
              ),
            ];

        for (final item in cases) {
          final result = await platform.setReservedAttribute(
            InappifyReservedAttributeRequest(
              attribute: item.attribute,
              value: item.value,
            ),
          );
          expect(result.isSuccess, isTrue);
        }
        final ipResult = await platform.setReservedAttribute(
          const InappifyReservedAttributeRequest(
            attribute: InappifyReservedAttribute.ip,
            value: '203.0.113.1',
          ),
        );
        final allowed = await platform.canSetReservedAttribute(
          const InappifyReservedAttributeCapabilityRequest(key: 'email'),
        );

        for (var index = 0; index < cases.length; index += 1) {
          expect(bridge.calls[index].method, cases[index].setter);
          expect(bridge.calls[index].positionalArguments, <Object?>[
            cases[index].value,
          ]);
        }
        expect(
          ipResult.failure?.code,
          InappifyFailureCode.unsupportedOperation,
        );
        expect(bridge.calls, hasLength(cases.length + 1));
        expect(bridge.calls.last.method, 'canSetReservedAttribute');
        expect(bridge.calls.last.positionalArguments, <Object?>[r'$email']);
        expect(allowed.data, isTrue);
      },
    );

    test('normalizes singular Web push-token capability aliases', () async {
      await _configure(platform);
      bridge.calls.clear();
      bridge.callResponses['canSetReservedAttribute'] = true;
      const aliases = <String, String>{
        'fcmToken': r'$fcmTokens',
        'fcmTokens': r'$fcmTokens',
        'apnsToken': r'$apnsTokens',
        'apnsTokens': r'$apnsTokens',
      };

      for (final key in aliases.keys) {
        final result = await platform.canSetReservedAttribute(
          InappifyReservedAttributeCapabilityRequest(key: key),
        );
        expect(result.data, isTrue);
      }

      expect(
        bridge.calls.map((call) => call.positionalArguments.single),
        aliases.values,
      );
    });
  });

  group('checkout and discount flow', () {
    test(
      'reads a pending checkout before a Web session is reconfigured',
      () async {
        bridge.pendingCheckoutId = 'checkout-from-session-storage';

        final result = await platform.getPendingCheckoutId();

        expect(result.isSuccess, isTrue);
        expect(result.data, 'checkout-from-session-storage');
        expect(result.snapshot, isNotNull);
        expect(bridge.pendingCheckoutReadCount, 1);
        expect(bridge.calls, isEmpty);
      },
    );

    test(
      'disables JS redirect and preserves checkout correlation metadata',
      () async {
        await _configure(platform);
        bridge.calls.clear();
        bridge.callResponses['purchase'] = _checkoutPayload();

        final result = await platform.purchase(
          const InappifyPurchaseRequest(
            productIdentifier: 'premium-monthly',
            offeringIdentifier: 'main',
            packageIdentifier: 'monthly',
            discountCode: 'WELCOME20',
            idempotencyKey: 'purchase-1',
          ),
        );

        expect(result.isSuccess, isTrue);
        expect(result.data?.url, 'https://pay.example.test/checkout-1');
        expect(result.data?.purchaseStatus, PurchaseStatus.NEEDTOPAY);
        expect(result.data?.checkoutId, 'checkout-1');
        expect(result.data?.checkoutStatus, 'Pending');
        expect(result.data?.nextActionType, 'redirect');
        expect(bridge.persistedCheckoutIds, <String>['checkout-1']);
        expect(bridge.calls.single.method, 'purchase');
        expect(bridge.calls.single.positionalArguments, <Object?>[
          <String, Object?>{
            'offeringIdentifier': 'main',
            'packageIdentifier': 'monthly',
            'productIdentifier': 'premium-monthly',
            'idempotencyKey': 'purchase-1',
            'country': 'IR',
            'appVersion': '1.0.0',
            'isCrypto': false,
            'discountCode': 'WELCOME20',
          },
          const <String, Object?>{'redirect': false},
        ]);
      },
    );

    test(
      'sends retry identity and current targeting in purchase parameters',
      () async {
        await _configure(platform);
        bridge.calls.clear();
        bridge.callResponses['setTargetingContext'] = null;
        await platform.setTargetingContext(
          const InappifyTargetingContextRequest(
            country: 'DE',
            appVersion: '2.5.0',
          ),
        );
        bridge.calls.clear();
        bridge.callResponses['purchase'] = _checkoutPayload();

        final result = await platform.purchase(
          const InappifyPurchaseRequest(
            productIdentifier: 'premium-monthly',
            offeringIdentifier: 'main',
            packageIdentifier: 'monthly',
            idempotencyKey: 'stable-retry-key',
            isCrypto: true,
          ),
        );

        expect(result.isSuccess, isTrue);
        final params =
            bridge.calls.single.positionalArguments.first
                as Map<Object?, Object?>;
        expect(params['idempotencyKey'], 'stable-retry-key');
        expect(params['country'], 'DE');
        expect(params['appVersion'], '2.5.0');
        expect(params['isCrypto'], isTrue);
        expect(
          bridge.calls.single.positionalArguments.last,
          const <String, Object?>{'redirect': false},
        );
      },
    );

    test(
      'creates a checkout with authoritative price and expiration metadata',
      () async {
        await _configure(platform);
        bridge.calls.clear();
        bridge.callResponses['createCheckout'] = _checkoutPayload(
          expiresAt: '2026-08-11T10:15:00Z',
          includePrice: true,
        );
        final cancellation = InappifyRequestCancellation();

        final result = await platform.createCheckout(
          InappifyPurchaseRequest(
            productIdentifier: 'premium-monthly',
            offeringIdentifier: 'main',
            packageIdentifier: 'monthly',
            discountCode: 'WELCOME20',
            idempotencyKey: 'checkout-attempt-1',
            country: 'DE',
            appVersion: '2.5.0',
            isCrypto: true,
            cancellation: cancellation,
          ),
        );

        expect(result.isSuccess, isTrue);
        expect(result.data?.checkout.id, 'checkout-1');
        expect(result.data?.checkout.expiresAt, '2026-08-11T10:15:00Z');
        expect(result.data?.price?.originalAmount, 250000);
        expect(result.data?.price?.discountAmount, 60000);
        expect(result.data?.price?.finalAmount, 190000);
        expect(result.data?.price?.currency, 'IRR');
        expect(bridge.persistedCheckoutIds, <String>['checkout-1']);
        expect(bridge.calls.single.method, 'createCheckout');
        expect(bridge.calls.single.positionalArguments, <Object?>[
          <String, Object?>{
            'offeringIdentifier': 'main',
            'packageIdentifier': 'monthly',
            'productIdentifier': 'premium-monthly',
            'idempotencyKey': 'checkout-attempt-1',
            'country': 'DE',
            'appVersion': '2.5.0',
            'isCrypto': true,
            'discountCode': 'WELCOME20',
          },
          const <String, Object?>{},
        ]);
        expect(bridge.calls.single.cancellation, same(cancellation));
        expect(bridge.calls.single.injectAbortSignal, isTrue);
      },
    );

    test(
      'polls checkout status and clears terminal correlation state',
      () async {
        await _configure(platform);
        bridge.calls.clear();
        bridge.pendingCheckoutId = 'checkout-1';
        bridge.callResponses['getCheckoutStatus'] = _checkoutPayload(
          status: 'Paid',
          includeNextAction: false,
          expiresAt: '2026-08-11T10:15:00Z',
          includePrice: true,
        );
        final cancellation = InappifyRequestCancellation();

        final result = await platform.getCheckoutStatus(
          InappifyCheckoutStatusRequest(
            checkoutId: 'checkout-1',
            cancellation: cancellation,
          ),
        );

        expect(result.isSuccess, isTrue);
        expect(result.data?.isPaid, isTrue);
        expect(result.data?.checkout.expiresAt, '2026-08-11T10:15:00Z');
        expect(result.data?.price?.finalAmount, 190000);
        expect(bridge.pendingCheckoutId, isNull);
        expect(bridge.clearedPendingCheckoutCount, 1);
        expect(bridge.calls.single.method, 'getCheckoutStatus');
        expect(bridge.calls.single.positionalArguments, <Object?>[
          'checkout-1',
          const <String, Object?>{},
        ]);
        expect(bridge.calls.single.cancellation, same(cancellation));
        expect(bridge.calls.single.injectAbortSignal, isTrue);
      },
    );

    test('pre-cancelled checkout APIs never cross the JS boundary', () async {
      await _configure(platform);
      bridge.calls.clear();
      final createCancellation = InappifyRequestCancellation()..cancel();
      final statusCancellation = InappifyRequestCancellation()..cancel();

      final created = await platform.createCheckout(
        InappifyPurchaseRequest(
          productIdentifier: 'premium-monthly',
          offeringIdentifier: 'main',
          packageIdentifier: 'monthly',
          idempotencyKey: 'checkout-attempt-1',
          cancellation: createCancellation,
        ),
      );
      final status = await platform.getCheckoutStatus(
        InappifyCheckoutStatusRequest(
          checkoutId: 'checkout-1',
          cancellation: statusCancellation,
        ),
      );

      expect(created.failure?.code, InappifyFailureCode.requestCancelled);
      expect(status.failure?.code, InappifyFailureCode.requestCancelled);
      expect(bridge.calls, isEmpty);
    });

    test(
      'infers a unique package only inside the requested offering',
      () async {
        await _configure(platform);
        bridge.calls.clear();
        bridge.callResponses['purchase'] = _checkoutPayload();

        final result = await platform.purchase(
          const InappifyPurchaseRequest(
            productIdentifier: 'premium-monthly',
            offeringIdentifier: 'main',
            idempotencyKey: 'purchase-1',
          ),
        );

        expect(result.isSuccess, isTrue);
        final params =
            bridge.calls.single.positionalArguments.first
                as Map<Object?, Object?>;
        expect(params['packageIdentifier'], 'monthly');
      },
    );

    test(
      'rejects missing or ambiguous inferred packages before checkout',
      () async {
        await _configure(platform);
        bridge.calls.clear();

        final missing = await platform.purchase(
          const InappifyPurchaseRequest(
            productIdentifier: 'missing-product',
            offeringIdentifier: 'main',
            idempotencyKey: 'purchase-1',
          ),
        );
        bridge.properties['offerings'] = _offeringsPayload(
          duplicateProductPackage: true,
        );
        bridge.callResponses['getOfferings'] = _offeringsPayload(
          duplicateProductPackage: true,
        );
        await platform.getOfferings(const InappifyRefreshRequest());
        bridge.calls.clear();
        final ambiguous = await platform.purchase(
          const InappifyPurchaseRequest(
            productIdentifier: 'premium-monthly',
            offeringIdentifier: 'main',
            idempotencyKey: 'purchase-2',
          ),
        );

        expect(missing.failure?.code, InappifyFailureCode.invalidConfiguration);
        expect(
          ambiguous.failure?.code,
          InappifyFailureCode.invalidConfiguration,
        );
        expect(bridge.calls, isEmpty);
      },
    );

    test('does not persist checkout state that is already terminal', () async {
      await _configure(platform);
      bridge.calls.clear();
      bridge.callResponses['purchase'] = _checkoutPayload(
        status: 'Paid',
        includeNextAction: false,
      );

      final result = await platform.purchase(
        const InappifyPurchaseRequest(
          productIdentifier: 'premium-monthly',
          offeringIdentifier: 'main',
          packageIdentifier: 'monthly',
          idempotencyKey: 'purchase-1',
        ),
      );

      expect(result.data?.purchaseStatus, PurchaseStatus.DONE);
      expect(result.data?.checkoutId, 'checkout-1');
      expect(result.data?.nextActionType, 'none');
      expect(bridge.persistedCheckoutIds, isEmpty);
    });

    test('maps a terminal Cancelled checkout without persisting it', () async {
      await _configure(platform);
      bridge.calls.clear();
      bridge.callResponses['purchase'] = _checkoutPayload(
        status: 'Cancelled',
        includeNextAction: false,
      );

      final result = await platform.purchase(
        const InappifyPurchaseRequest(
          productIdentifier: 'premium-monthly',
          offeringIdentifier: 'main',
          packageIdentifier: 'monthly',
          idempotencyKey: 'purchase-1',
        ),
      );

      expect(result.failure?.code, InappifyFailureCode.purchaseCancelled);
      expect(result.failure?.details['checkoutStatus'], 'Cancelled');
      expect(bridge.persistedCheckoutIds, isEmpty);
    });

    test('resolves the current offering before discount validation', () async {
      await _configure(platform);
      bridge.calls.clear();
      bridge.callResponses['getCurrentOffering'] = _offeringPayload();
      bridge.callResponses['validateDiscountCode'] = _nestedDiscountPayload();

      final result = await platform.validateDiscountCode(
        const InappifyDiscountCodeRequest(discountCode: 'WELCOME20'),
      );

      expect(result.data?.isValid, isTrue);
      expect(result.data?.code, 'WELCOME20');
      expect(result.data?.percent, 20);
      expect(result.data?.offering?.identifier, 'main');
      expect(
        result.data?.offering?.packages?.single.product?.prices?.single.price,
        190000,
      );
      expect(bridge.calls, hasLength(2));
      expect(bridge.calls[0].method, 'getCurrentOffering');
      expect(bridge.calls[0].positionalArguments, isEmpty);
      expect(bridge.calls[1].method, 'validateDiscountCode');
      expect(bridge.calls[1].positionalArguments, <Object?>[
        'WELCOME20',
        'main',
      ]);
    });

    test(
      'rejects discount validation when JS has no current offering',
      () async {
        await _configure(platform);
        bridge.calls.clear();
        bridge.callResponses['getCurrentOffering'] = null;

        final result = await platform.validateDiscountCode(
          const InappifyDiscountCodeRequest(discountCode: 'WELCOME20'),
        );

        expect(result.failure?.code, InappifyFailureCode.invalidConfiguration);
        expect(bridge.calls.single.method, 'getCurrentOffering');
        expect(bridge.calls.single.positionalArguments, isEmpty);
      },
    );

    test(
      'rejects beta.1 nested discount data without a priced offering',
      () async {
        await _configure(platform);
        bridge.calls.clear();
        bridge.callResponses['validateDiscountCode'] = <String, Object?>{
          'discount': <String, Object?>{
            'code': 'WELCOME20',
            'isValid': true,
            'percent': 20,
          },
        };

        final result = await platform.validateDiscountCode(
          const InappifyDiscountCodeRequest(
            discountCode: 'WELCOME20',
            offeringIdentifier: 'main',
          ),
        );

        expect(result.failure?.code, InappifyFailureCode.malformedResponse);
      },
    );

    test(
      'payment return polls exact checkout and clears storage only when Paid',
      () async {
        await _configure(platform);
        bridge.calls.clear();
        bridge.callResponses['handlePaymentReturn'] = _checkoutPayload(
          status: 'Paid',
          includeNextAction: false,
        );
        bridge.properties['customerInfo'] = _customerPayload(
          customerId: 'paid-customer',
        );

        final result = await platform.handlePaymentReturn(
          const InappifyPaymentReturnRequest(
            checkoutId: 'checkout-1',
            timeoutMs: 60000,
            intervalMs: 1500,
          ),
        );

        expect(result.data?.isPaid, isTrue);
        expect(
          result.snapshot?.customerInfo?.originalAppUserId,
          'paid-customer',
        );
        expect(bridge.clearedPendingCheckoutCount, 1);
        expect(bridge.calls.single.positionalArguments, <Object?>[
          'checkout-1',
          <String, Object?>{'timeoutMs': 60000, 'intervalMs': 1500},
        ]);
      },
    );

    test(
      'keeps authoritative Paid result when customer refresh is malformed',
      () async {
        await _configure(platform);
        bridge.calls.clear();
        bridge.callResponses['handlePaymentReturn'] = _checkoutPayload(
          status: 'Paid',
          includeNextAction: false,
        );
        bridge.properties['customerInfo'] = 'malformed-customer';

        final result = await platform.handlePaymentReturn(
          const InappifyPaymentReturnRequest(checkoutId: 'checkout-1'),
        );

        expect(result.isSuccess, isTrue);
        expect(result.data?.isPaid, isTrue);
        expect(result.snapshot?.failedToLoadCustomerInfo, isTrue);
        expect(result.snapshot?.customerInfo?.originalAppUserId, 'anonymous-1');
        expect(bridge.clearedPendingCheckoutCount, 1);
      },
    );
  });

  group('events and sanitized errors', () {
    test('maps documented events to complete Flutter snapshots', () async {
      await _configure(platform);
      final customerEvent = platform.events.first;

      bridge.emit(
        InappifyWebBridgeEvent(
          name: 'customerInfoUpdated',
          payload: _customerPayload(customerId: 'event-customer'),
        ),
      );
      final event = await customerEvent;

      expect(event.type, InappifyPlatformEventType.customerInfoChanged);
      expect(event.snapshot?.customerInfo?.originalAppUserId, 'event-customer');
      expect(event.snapshot?.offerings, isNotNull);
      expect(event.snapshot?.accessToken, isNull);
    });

    test('authentication events expose token-free data', () async {
      await _configure(platform);
      final authenticationEvent = platform.events.first;

      bridge.emit(
        InappifyWebBridgeEvent(
          name: 'authenticationChanged',
          payload: <String, Object?>{
            ..._authenticationPayload(),
            'accessToken': 'must-not-cross',
            'refreshToken': 'must-not-cross',
          },
        ),
      );
      final event = await authenticationEvent;

      expect(event.type, InappifyPlatformEventType.authenticationChanged);
      expect(event.data, isNot(contains('accessToken')));
      expect(event.data, isNot(contains('refreshToken')));
    });

    test(
      'session events preserve customer state during transient refresh errors',
      () async {
        await _configure(platform);
        final repeated = await platform.configure(
          const InappifyConfigureRequest(
            apiKey: 'public-web-key',
            country: 'IR',
            appVersion: '1.0.0',
          ),
        );
        final previousCustomer = repeated.snapshot?.customerInfo;
        final eventFuture = platform.events.first;

        bridge.emit(
          const InappifyWebBridgeEvent(
            name: 'sessionStateChanged',
            payload: <String, Object?>{
              'state': 'temporarily-unavailable',
              'reason': 'NETWORK_ERROR',
              'retryable': true,
            },
          ),
        );
        final event = await eventFuture;

        expect(event.type, InappifyPlatformEventType.sessionStateChanged);
        expect(
          event.snapshot?.sessionState,
          InappifySessionState.temporarilyUnavailable,
        );
        expect(event.snapshot?.customerInfo, same(previousCustomer));
        expect(event.data, <String, Object?>{
          'state': 'temporarily-unavailable',
          'retryable': true,
          'reason': 'NETWORK_ERROR',
        });
      },
    );

    test('maps beta.3 recovery and storage failures distinctly', () async {
      await _configure(platform);
      bridge.callHandlers['getCustomerInfo'] = (_) {
        throw const InappifyWebBridgeException(
          code: 'SESSION_RECOVERY_REQUIRED',
          status: 401,
          kind: 'api',
        );
      };

      final recovery = await platform.getCustomerInfo(
        const InappifyRefreshRequest(),
      );
      expect(
        recovery.failure?.code,
        InappifyFailureCode.sessionRecoveryRequired,
      );
      expect(
        recovery.snapshot?.sessionState,
        InappifySessionState.recoveryRequired,
      );

      bridge.callHandlers['getCustomerInfo'] = (_) {
        throw const InappifyWebBridgeException(
          code: 'STORAGE_UNAVAILABLE',
          kind: 'storage',
        );
      };
      final storage = await platform.getCustomerInfo(
        const InappifyRefreshRequest(),
      );
      expect(storage.failure?.code, InappifyFailureCode.storageUnavailable);
      expect(storage.failure?.isRetryable, isTrue);
      expect(storage.snapshot?.customerInfo, isNotNull);
    });

    test('offeringsUpdated replaces the offering snapshot', () async {
      await _configure(platform);
      final offeringsEvent = platform.events.first;
      final replacement = _offeringPayload()..['identifier'] = 'event-main';

      bridge.emit(
        InappifyWebBridgeEvent(
          name: 'offeringsUpdated',
          payload: <String, Object?>{
            'all': <Object?>[replacement],
            'current': replacement,
          },
        ),
      );
      final event = await offeringsEvent;

      expect(event.type, InappifyPlatformEventType.offeringsChanged);
      expect(
        event.snapshot?.offerings?.defaultOffering()?.identifier,
        'event-main',
      );
      expect(event.snapshot?.customerInfo, isNotNull);
    });

    test('normalizes provider errors without leaking raw details', () async {
      await _configure(platform);
      bridge.callHandlers['getCustomerInfo'] = (_) {
        throw const InappifyWebBridgeException(
          code: 'network_error',
          status: 503,
          requestId: 'safe-request-id',
        );
      };

      final result = await platform.getCustomerInfo(
        const InappifyRefreshRequest(),
      );

      expect(result.failure?.code, InappifyFailureCode.network);
      expect(result.failure?.isRetryable, isTrue);
      expect(result.failure?.details, <String, Object?>{
        'operation': 'getCustomerInfo',
        'serverCode': 'network_error',
        'status': 503,
        'requestId': 'safe-request-id',
      });
      expect(result.failure?.message, isNot(contains('public-web-key')));
    });

    test(
      'maps malformed JavaScript values without throwing raw errors',
      () async {
        await _configure(platform);
        bridge.callResponses['getOfferings'] = 'not-a-map';

        final result = await platform.getOfferings(
          const InappifyRefreshRequest(force: true),
        );

        expect(result.failure?.code, InappifyFailureCode.malformedResponse);
        expect(result.snapshot?.failedToLoadOfferings, isTrue);
      },
    );
  });
}

Future<InappifySdkResult<void>> _configure(WebInappifyPlatform platform) async {
  final result = await platform.configure(
    const InappifyConfigureRequest(
      apiKey: 'public-web-key',
      country: 'IR',
      appVersion: '1.0.0',
    ),
  );
  expect(result.isSuccess, isTrue);
  return result;
}

Map<String, Object?> _authenticationPayload() => <String, Object?>{
  'isAnonymous': false,
  'type': 'Authenticated',
  'authenticatedAt': '2026-08-11T10:00:00Z',
};

Map<String, Object?> _customerPayload({
  String customerId = 'anonymous-1',
  Map<String, Object?> attributes = const <String, Object?>{'language': 'fa'},
}) {
  return <String, Object?>{
    'originalAppUserId': customerId,
    'entitlements': <String, Object?>{
      'premium': <String, Object?>{'isActive': true},
    },
    'attributes': attributes,
  };
}

Map<String, Object?> _offeringPayload({bool duplicateProductPackage = false}) {
  return <String, Object?>{
    'identifier': 'main',
    'isDefault': true,
    'packages': <Object?>[
      <String, Object?>{
        'identifier': 'monthly',
        'name': 'Monthly',
        'product': <String, Object?>{
          'identifier': 'premium-monthly',
          'prices': <Object?>[
            <String, Object?>{'amount': 190000, 'currency': 'IRR'},
          ],
        },
      },
      if (duplicateProductPackage)
        <String, Object?>{
          'identifier': 'monthly-duplicate',
          'product': <String, Object?>{
            'identifier': 'premium-monthly',
            'prices': <Object?>[
              <String, Object?>{'amount': 190000, 'currency': 'IRR'},
            ],
          },
        },
    ],
  };
}

Map<String, Object?> _offeringsPayload({
  bool duplicateProductPackage = false,
  int? forceVersion,
  String? fetchedAt,
}) {
  final offering = _offeringPayload(
    duplicateProductPackage: duplicateProductPackage,
  );
  return <String, Object?>{
    'all': <Object?>[offering],
    'current': offering,
    if (forceVersion != null) 'forceVersion': forceVersion,
    if (fetchedAt != null) 'fetchedAt': fetchedAt,
  };
}

Map<String, Object?> _checkoutPayload({
  String status = 'Pending',
  bool includeNextAction = true,
  String? expiresAt,
  bool includePrice = false,
}) {
  return <String, Object?>{
    'checkout': <String, Object?>{
      'id': 'checkout-1',
      'status': status,
      if (expiresAt != null) 'expiresAt': expiresAt,
    },
    if (includeNextAction)
      'nextAction': <String, Object?>{
        'type': 'redirect',
        'url': 'https://pay.example.test/checkout-1',
      },
    if (includePrice)
      'price': <String, Object?>{
        'originalAmount': 250000,
        'discountAmount': 60000,
        'finalAmount': 190000,
        'currency': 'IRR',
      },
  };
}

Map<String, Object?> _nestedDiscountPayload() => <String, Object?>{
  'discount': <String, Object?>{
    'code': 'WELCOME20',
    'isValid': true,
    'percent': 20,
  },
  'offering': _offeringPayload(),
};

typedef _CallHandler = FutureOr<Object?> Function(_BridgeInvocation invocation);

class _BridgeInvocation {
  const _BridgeInvocation({
    required this.method,
    required this.positionalArguments,
    required this.cancellation,
    required this.injectAbortSignal,
  });

  final String method;
  final List<Object?> positionalArguments;
  final InappifyRequestCancellation? cancellation;
  final bool injectAbortSignal;
}

class _FakeWebBridge
    implements InappifyWebBridge, InappifyWebProviderCapabilities {
  _FakeWebBridge({Map<String, Object?>? properties})
    : properties = properties ?? <String, Object?>{};

  bool available = true;
  bool hasTargetingSync = true;
  String? version = '0.2.0';
  Map<String, Object?>? configureOptions;
  Object? configureResponse;
  Object? configureError;
  int configureCount = 0;
  final Map<String, Object?> properties;
  final Map<String, Object?> callResponses = <String, Object?>{};
  final Map<String, _CallHandler> callHandlers = <String, _CallHandler>{};
  final List<_BridgeInvocation> calls = <_BridgeInvocation>[];
  final List<String> persistedCheckoutIds = <String>[];
  int clearedPendingCheckoutCount = 0;
  String? pendingCheckoutId;
  int pendingCheckoutReadCount = 0;
  bool disposed = false;

  final StreamController<InappifyWebBridgeEvent> _eventController =
      StreamController<InappifyWebBridgeEvent>.broadcast(sync: true);

  @override
  bool get isAvailable => available;

  @override
  bool supportsMethod(String method) =>
      method != 'syncAttributesAndOfferingsIfNeeded' || hasTargetingSync;

  @override
  String? get sdkVersion => version;

  @override
  Stream<InappifyWebBridgeEvent> get events => _eventController.stream;

  @override
  Future<Object?> configure(Map<String, Object?> options) async {
    configureCount += 1;
    configureOptions = Map<String, Object?>.of(options);
    final error = configureError;
    if (error != null) throw error;
    return configureResponse;
  }

  @override
  Future<Object?> call(
    String method, {
    List<Object?> positionalArguments = const <Object?>[],
    InappifyRequestCancellation? cancellation,
    bool injectAbortSignal = false,
  }) async {
    final invocation = _BridgeInvocation(
      method: method,
      positionalArguments: List<Object?>.of(positionalArguments),
      cancellation: cancellation,
      injectAbortSignal: injectAbortSignal,
    );
    calls.add(invocation);
    final handler = callHandlers[method];
    if (handler != null) return handler(invocation);
    return callResponses[method];
  }

  @override
  Object? readProperty(String name) => properties[name];

  @override
  void persistPendingCheckout(String checkoutId) {
    persistedCheckoutIds.add(checkoutId);
    pendingCheckoutId = checkoutId;
  }

  @override
  void clearPendingCheckout() {
    clearedPendingCheckoutCount += 1;
    pendingCheckoutId = null;
  }

  @override
  String? readPendingCheckout() {
    pendingCheckoutReadCount += 1;
    return pendingCheckoutId;
  }

  void emit(InappifyWebBridgeEvent event) {
    _eventController.add(event);
  }

  @override
  Future<void> dispose() async {
    disposed = true;
    await _eventController.close();
  }
}
