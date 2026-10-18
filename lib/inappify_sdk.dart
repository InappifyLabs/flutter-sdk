import 'dart:async';

import 'package:inappify_sdk/models/attribute.dart';
import 'package:inappify_sdk/models/mobile_v2.dart';
import 'package:inappify_sdk/models/authentication_result.dart';
import 'package:inappify_sdk/models/captcha_challenge.dart';
import 'package:inappify_sdk/models/checkout_result.dart';
import 'package:inappify_sdk/models/customer_info.dart';
import 'package:inappify_sdk/models/entitlement_model.dart';
import 'package:inappify_sdk/models/enums/market.dart';
import 'package:inappify_sdk/models/inappify_configuration.dart';
import 'package:inappify_sdk/models/offering_model.dart';
import 'package:inappify_sdk/models/offerings_model.dart';
import 'package:inappify_sdk/models/otp_challenge.dart';
import 'package:inappify_sdk/models/purchase_result.dart';
import 'package:inappify_sdk/models/validate_discount_code_data.dart';
import 'package:inappify_sdk/request_cancellation.dart';
import 'package:inappify_sdk/session_state.dart';
import 'package:inappify_sdk/src/bootstrap/inappify_sdk_runtime.dart';
import 'package:inappify_sdk/src/platform/contracts/platform_event.dart';
import 'package:inappify_sdk/src/platform/contracts/sdk_failure.dart';
import 'package:inappify_sdk/src/platform/contracts/sdk_requests.dart';
import 'package:inappify_sdk/src/platform/contracts/sdk_result.dart';
import 'package:inappify_sdk/src/platform/contracts/sdk_snapshot.dart';

export 'package:inappify_sdk/models/authentication_result.dart';
export 'package:inappify_sdk/models/mobile_v2.dart';
export 'package:inappify_sdk/models/captcha_challenge.dart';
export 'package:inappify_sdk/models/checkout_result.dart';
export 'package:inappify_sdk/models/inappify_configuration.dart';
export 'package:inappify_sdk/models/otp_challenge.dart';
export 'package:inappify_sdk/offering_evaluation_context.dart';
export 'package:inappify_sdk/request_cancellation.dart';
export 'package:inappify_sdk/session_state.dart';
export 'package:inappify_sdk/src/platform/contracts/platform_event.dart';
export 'package:inappify_sdk/src/platform/contracts/sdk_failure.dart';
export 'package:inappify_sdk/src/platform/contracts/sdk_requests.dart'
    show InappifyReservedAttribute;
export 'package:inappify_sdk/src/platform/contracts/sdk_result.dart';
export 'package:inappify_sdk/src/platform/contracts/sdk_snapshot.dart';

/// Flutter façade for the Inappify SDK.
///
/// Static operations share one session-owning backend. Android requires the
/// native Kotlin SDK through MethodChannel; iOS uses the Dart V2 client with
/// native metadata and Keychain storage. Web requires the host-loaded Inappify
/// JavaScript SDK. Synchronous getters mirror the latest backend snapshot.
class InappifySdk {
  /// Creates a compatibility handle.
  ///
  /// SDK operations remain static to preserve the existing application API.
  InappifySdk();

  static final _coordinator = InappifySdkRuntime.coordinator;

  static int _requestSequence = 0;
  static InappifyFailure? _lastFailure;
  static final Map<Object, Future<InappifySdkResult<void>>>
  _authenticatedWebConfigureOperations =
      <Object, Future<InappifySdkResult<void>>>{};

  /// Ordered asynchronous updates emitted by the selected SDK backend.
  static Stream<InappifyPlatformEvent> get events => _coordinator.events;

  /// Filtered mobile HTTP diagnostics, active only while listened to.
  static Stream<InappifyHttpTrace> get httpTraces => _coordinator.httpTraces;

  /// Last mirrored backend state. Use typed operations for authoritative checks.
  static InappifySdkSnapshot get snapshot => _coordinator.state.snapshot;

  /// Typed, token-free Web session lifecycle updates.
  static Stream<InappifySessionStateChange> get sessionStateChanges => events
      .where(
        (event) => event.type == InappifyPlatformEventType.sessionStateChanged,
      )
      .map(
        (event) => InappifySessionStateChange.fromMap(
          event.data.cast<String, dynamic>(),
        ),
      );

  /// Most recent semantic failure observed through this compatibility façade.
  ///
  /// Prefer the additive `*Result` methods when multiple operations can run
  /// concurrently. This process-wide diagnostic contains only sanitized
  /// metadata; provider payloads and credentials are never retained here.
  static InappifyFailure? get lastFailure => _lastFailure;

  /// Legacy spelling retained for source compatibility.
  static String? get accessToekn => _coordinator.state.accessToken;
  static set accessToekn(String? value) {
    _coordinator.state.accessToken = value;
  }

  /// API key mirrored from the active backend.
  static String? get apiKeyValue => _coordinator.state.apiKey;
  static set apiKeyValue(String? value) {
    _coordinator.state.apiKey = value;
  }

  /// Latest customer snapshot returned by the active backend.
  static CustomerInfo? get customerInfo => _coordinator.state.customerInfo;
  static set customerInfo(CustomerInfo? value) {
    _coordinator.state.customerInfo = value;
  }

  /// Latest offering snapshot returned by the active backend.
  static OfferingsModel? get offerings => _coordinator.state.offerings;
  static set offerings(OfferingsModel? value) {
    _coordinator.state.offerings = value;
  }

  /// Store metadata returned during configuration, when available.
  static String? get storeInfo => _coordinator.state.storeInfo;
  static set storeInfo(String? value) {
    _coordinator.state.storeInfo = value;
  }

  /// Application identifier assigned by Inappify, when configured.
  static int? get appId => _coordinator.state.appId;

  /// Country code mirrored from the selected backend.
  static String get country => _coordinator.state.country;

  /// Host application version name mirrored from the selected backend.
  static String get vName => _coordinator.state.versionName;

  /// Host application version code mirrored from the selected backend.
  static int? get vCode => _coordinator.state.versionCode;

  /// Version of the backend SDK that owns the active session.
  static String? get sdkVersion => _coordinator.state.sdkVersion;

  /// Token-free lifecycle state of the backend-owned session.
  static InappifySessionState get sessionState =>
      _coordinator.state.sessionState;

  /// Whether the backend reports durable or memory-only session persistence.
  static InappifySessionPersistenceMode get sessionPersistenceMode =>
      _coordinator.state.persistenceMode;

  /// Whether the latest offering refresh failed.
  ///
  /// The legacy spelling is retained for source compatibility.
  static bool get faildToLoadOfferings =>
      _coordinator.state.failedToLoadOfferings;

  /// Whether the latest customer-information refresh failed.
  ///
  /// The legacy spelling is retained for source compatibility.
  static bool get faildToLoadCustomerInfo =>
      _coordinator.state.failedToLoadCustomerInfo;

  /// Configures one authoritative backend for the complete SDK session.
  ///
  /// Concurrent calls with identical input share one Future. Failures preserve
  /// the historical `false` result and do not throw into fire-and-forget call
  /// sites. API and market keys must never be logged by implementations.
  /// On Web, [apiKey] must be the Public Web App Key and an authenticated
  /// [appUserIdentifier] is rejected; exchange an Identity Ticket after
  /// configuring the browser session instead.
  /// [enableSubscriptionRecoveryWithoutPayload] controls only native Android
  /// Bazaar recovery. Its default is true and requires the V2 subscription
  /// recovery endpoint; set false to opt out. iOS and Web ignore this option.
  static Future<bool> configure({
    required String apiKey,
    String? appUserIdentifier,
    Market? market,
    String? marketKey,
    String? country,
    String? appVersion,
    InappifyMobileProtocol mobileProtocol = InappifyMobileProtocol.goV2,
    bool enableSubscriptionRecoveryWithoutPayload = true,
  }) async {
    final result = await configureResult(
      apiKey: apiKey,
      appUserIdentifier: appUserIdentifier,
      market: market,
      marketKey: marketKey,
      country: country,
      appVersion: appVersion,
      mobileProtocol: mobileProtocol,
      enableSubscriptionRecoveryWithoutPayload:
          enableSubscriptionRecoveryWithoutPayload,
    );
    return result.isSuccess;
  }

  /// Optional backend operation for restoring a session without HTTP.
  /// Production Android and iOS V2 backends do not support this operation.
  /// Use [configureResult] to load validated persisted state and refresh it.
  static Future<InappifySdkResult<bool>> restoreCachedSessionResult({
    required String apiKey,
    String? appUserIdentifier,
    Market? market,
    String? marketKey,
    String? country,
    String? appVersion,
    InappifyMobileProtocol mobileProtocol = InappifyMobileProtocol.goV2,
    bool enableSubscriptionRecoveryWithoutPayload = true,
  }) async => _record(
    await _coordinator.restoreCachedSession(
      InappifyConfigureRequest(
        apiKey: apiKey,
        appUserIdentifier: appUserIdentifier,
        market: market,
        marketKey: marketKey,
        country: country,
        appVersion: appVersion,
        mobileProtocol: mobileProtocol,
        enableSubscriptionRecoveryWithoutPayload:
            enableSubscriptionRecoveryWithoutPayload,
      ),
    ),
  );

  /// Typed variant of [configure] that preserves sanitized failure metadata.
  static Future<InappifySdkResult<void>> configureResult({
    required String apiKey,
    String? appUserIdentifier,
    Market? market,
    String? marketKey,
    String? country,
    String? appVersion,
    InappifyMobileProtocol mobileProtocol = InappifyMobileProtocol.goV2,
    bool enableSubscriptionRecoveryWithoutPayload = true,
  }) async {
    return _record(
      await _coordinator.configure(
        InappifyConfigureRequest(
          apiKey: apiKey,
          appUserIdentifier: appUserIdentifier,
          market: market,
          marketKey: marketKey,
          country: country,
          appVersion: appVersion,
          mobileProtocol: mobileProtocol,
          enableSubscriptionRecoveryWithoutPayload:
              enableSubscriptionRecoveryWithoutPayload,
        ),
      ),
    );
  }

  /// Configures and guarantees an authenticated Web session for a logged-in
  /// host application user.
  ///
  /// Use this method instead of a separate `configure` + ticket exchange on
  /// PWA startup. If beta.3 reports [InappifySessionState.recoveryRequired],
  /// the SDK first creates a replacement anonymous transport session and only
  /// then asks [identityTicketProvider] for a fresh one-time ticket. Concurrent
  /// identical calls share one recovery operation so a ticket is never
  /// consumed twice. Pass [expectedCustomerIdentifier] when the host identity
  /// is known so a restored session belonging to another user is never
  /// accepted as authenticated.
  static Future<bool> configureAuthenticatedWebSession({
    required String apiKey,
    required InappifyIdentityTicketProvider identityTicketProvider,
    String? expectedCustomerIdentifier,
    String? country,
    String? appVersion,
    InappifyRequestCancellation? cancellation,
  }) async {
    final result = await configureAuthenticatedWebSessionResult(
      apiKey: apiKey,
      identityTicketProvider: identityTicketProvider,
      expectedCustomerIdentifier: expectedCustomerIdentifier,
      country: country,
      appVersion: appVersion,
      cancellation: cancellation,
    );
    return result.isSuccess;
  }

  /// Typed variant of [configureAuthenticatedWebSession].
  ///
  /// Temporary network, timeout, and storage failures are returned without
  /// requesting a ticket or clearing the last authoritative customer mirror.
  /// An ambiguous ticket-exchange failure is reconciled with a safe customer
  /// refresh and the same ticket is never retried.
  static Future<InappifySdkResult<void>>
  configureAuthenticatedWebSessionResult({
    required String apiKey,
    required InappifyIdentityTicketProvider identityTicketProvider,
    String? expectedCustomerIdentifier,
    String? country,
    String? appVersion,
    InappifyRequestCancellation? cancellation,
  }) {
    final normalizedExpectedIdentifier = expectedCustomerIdentifier?.trim();
    final fingerprint = (
      apiKey: apiKey,
      expectedCustomerIdentifier: normalizedExpectedIdentifier,
      country: country,
      appVersion: appVersion,
    );
    final existing = _authenticatedWebConfigureOperations[fingerprint];
    if (existing != null) return existing;

    final operation = _configureAuthenticatedWebSession(
      apiKey: apiKey,
      identityTicketProvider: identityTicketProvider,
      expectedCustomerIdentifier: normalizedExpectedIdentifier,
      country: country,
      appVersion: appVersion,
      cancellation: cancellation,
    ).then(_record);
    _authenticatedWebConfigureOperations[fingerprint] = operation;
    unawaited(
      operation.whenComplete(() {
        if (identical(
          _authenticatedWebConfigureOperations[fingerprint],
          operation,
        )) {
          _authenticatedWebConfigureOperations.remove(fingerprint);
        }
      }),
    );
    return operation;
  }

  static Future<InappifySdkResult<void>> _configureAuthenticatedWebSession({
    required String apiKey,
    required InappifyIdentityTicketProvider identityTicketProvider,
    required String? expectedCustomerIdentifier,
    required String? country,
    required String? appVersion,
    required InappifyRequestCancellation? cancellation,
  }) async {
    Future<InappifySdkResult<void>> configureOnce() {
      return _coordinator.configure(
        InappifyConfigureRequest(
          apiKey: apiKey,
          country: country,
          appVersion: appVersion,
        ),
      );
    }

    var configured = await configureOnce();
    if (!configured.isSuccess &&
        configured.failure?.code ==
            InappifyFailureCode.sessionRecoveryRequired) {
      // beta.3 has now removed only the definitively invalid authenticated
      // refresh token. A second configure creates the anonymous transport
      // session required before exchanging a newly issued Identity Ticket.
      configured = await configureOnce();
    }
    if (!configured.isSuccess) return configured;

    final snapshot = configured.snapshot ?? _coordinator.state.snapshot;
    final expectedIdentifier = expectedCustomerIdentifier?.trim();
    final hasExpectedIdentifier = expectedIdentifier?.isNotEmpty ?? false;
    final restoredIdentifier = snapshot.customerInfo?.originalAppUserId;
    final restoredIdentityMatches =
        !hasExpectedIdentifier || restoredIdentifier == expectedIdentifier;
    if (snapshot.sessionState == InappifySessionState.authenticated &&
        restoredIdentityMatches) {
      return configured;
    }
    if (snapshot.storeInfo != 'web') {
      // Native and legacy Dart backends retain their existing identity flow.
      return configured;
    }
    if (snapshot.sessionState == InappifySessionState.temporarilyUnavailable) {
      return InappifySdkResult<void>.failure(
        const InappifyFailure(
          code: InappifyFailureCode.sessionTemporarilyUnavailable,
          message: 'The Inappify Web session is temporarily unavailable.',
          isRetryable: true,
          details: <String, Object?>{'operation': 'configureAuthenticatedWeb'},
        ),
        snapshot: snapshot,
      );
    }
    if (snapshot.sessionState != InappifySessionState.anonymous &&
        snapshot.sessionState != InappifySessionState.authenticated) {
      return InappifySdkResult<void>.failure(
        const InappifyFailure(
          code: InappifyFailureCode.malformedResponse,
          message: 'The Inappify Web SDK returned an invalid session state.',
          details: <String, Object?>{'operation': 'configureAuthenticatedWeb'},
        ),
        snapshot: snapshot,
      );
    }
    if (cancellation?.isCancelled ?? false) {
      return InappifySdkResult<void>.failure(
        const InappifyFailure(
          code: InappifyFailureCode.requestCancelled,
          message: 'Inappify Web session recovery was cancelled.',
          details: <String, Object?>{'operation': 'configureAuthenticatedWeb'},
        ),
        snapshot: snapshot,
      );
    }

    String ticket;
    try {
      ticket = (await identityTicketProvider()).trim();
    } catch (_) {
      return InappifySdkResult<void>.failure(
        const InappifyFailure(
          code: InappifyFailureCode.sessionRecoveryRequired,
          message: 'A fresh Inappify Identity Ticket could not be obtained.',
          isRetryable: true,
          details: <String, Object?>{
            'operation': 'configureAuthenticatedWeb',
            'stage': 'identityTicketProvider',
          },
        ),
        snapshot: snapshot,
      );
    }
    if (ticket.isEmpty) {
      return InappifySdkResult<void>.failure(
        const InappifyFailure(
          code: InappifyFailureCode.invalidConfiguration,
          message: 'The Identity Ticket provider returned an empty value.',
          details: <String, Object?>{
            'operation': 'configureAuthenticatedWeb',
            'stage': 'identityTicketProvider',
          },
        ),
        snapshot: snapshot,
      );
    }

    final authenticated = await _coordinator.exchangeIdentityTicket(
      InappifyIdentityTicketRequest(
        identityTicket: ticket,
        cancellation: cancellation,
      ),
    );
    if (!authenticated.isSuccess) {
      final afterExchange =
          authenticated.snapshot ?? _coordinator.state.snapshot;
      final mayHaveCommitted =
          authenticated.failure?.details['outcomeMayHaveCommitted'] == true;
      if (mayHaveCommitted &&
          afterExchange.sessionState == InappifySessionState.authenticated) {
        final reconciled = await _coordinator.getCustomerInfo(force: true);
        final reconciledFailure = reconciled.failure;
        if (reconciledFailure != null) {
          return InappifySdkResult<void>.failure(
            reconciledFailure,
            snapshot: reconciled.snapshot,
          );
        }
        final reconciledIdentifier =
            reconciled.data?.originalAppUserId ??
            reconciled.snapshot?.customerInfo?.originalAppUserId;
        if (hasExpectedIdentifier &&
            reconciledIdentifier != expectedIdentifier) {
          return _identityMismatchFailure(reconciled.snapshot);
        }
        return InappifySdkResult<void>.success(snapshot: reconciled.snapshot);
      }
      return _withoutData(authenticated);
    }
    final authentication = authenticated.data;
    if (authentication == null) {
      return InappifySdkResult<void>.failure(
        const InappifyFailure(
          code: InappifyFailureCode.malformedResponse,
          message: 'Identity Ticket exchange returned no authentication state.',
          details: <String, Object?>{'operation': 'configureAuthenticatedWeb'},
        ),
        snapshot: authenticated.snapshot,
      );
    }
    if (authentication.isAnonymous) {
      return InappifySdkResult<void>.failure(
        const InappifyFailure(
          code: InappifyFailureCode.identityMismatch,
          message: 'Identity Ticket exchange did not authenticate the session.',
          details: <String, Object?>{'operation': 'configureAuthenticatedWeb'},
        ),
        snapshot: authenticated.snapshot,
      );
    }
    final authenticatedIdentifier =
        authenticated.snapshot?.customerInfo?.originalAppUserId;
    if (hasExpectedIdentifier &&
        authenticatedIdentifier != expectedIdentifier) {
      return _identityMismatchFailure(authenticated.snapshot);
    }
    return InappifySdkResult<void>.success(snapshot: authenticated.snapshot);
  }

  static InappifySdkResult<void> _identityMismatchFailure(
    InappifySdkSnapshot? snapshot,
  ) {
    return InappifySdkResult<void>.failure(
      const InappifyFailure(
        code: InappifyFailureCode.identityMismatch,
        message:
            'The authenticated Inappify customer does not match the host user.',
        details: <String, Object?>{'operation': 'configureAuthenticatedWeb'},
      ),
      snapshot: snapshot,
    );
  }

  static InappifySdkResult<void> _withoutData<T>(InappifySdkResult<T> result) {
    final failure = result.failure;
    return failure == null
        ? InappifySdkResult<void>.success(snapshot: result.snapshot)
        : InappifySdkResult<void>.failure(failure, snapshot: result.snapshot);
  }

  /// Changes the active Inappify customer identity.
  /// Login uses the configured session; no app key is required again.
  ///
  /// This compatibility API is implemented by Dart and the Android native
  /// backend. The Web backend returns `false` because the browser SDK accepts
  /// only [loginWithIdentityTicket] or OTP, not a stable user identifier.
  static Future<bool> login({required String appUserIdentifier}) async {
    final result = await loginResult(appUserIdentifier: appUserIdentifier);
    return result.isSuccess;
  }

  /// Typed variant of [login]. Web callers should use Identity Ticket or OTP.
  static Future<InappifySdkResult<void>> loginResult({
    required String appUserIdentifier,
  }) async {
    return _record(
      await _coordinator.login(
        InappifyLoginRequest(appUserIdentifier: appUserIdentifier),
      ),
    );
  }

  /// Exchanges a backend-issued, single-use Identity Ticket.
  ///
  /// On success, the selected backend replaces its session credentials,
  /// refreshes customer state, and invalidates stale offering caches. The
  /// ticket and resulting tokens are never exposed through the SDK snapshot.
  static Future<InappifyAuthenticationResult?> exchangeIdentityTicket({
    required String identityTicket,
    InappifyRequestCancellation? cancellation,
  }) async {
    final result = await exchangeIdentityTicketResult(
      identityTicket: identityTicket,
      cancellation: cancellation,
    );
    return result.isSuccess ? result.data : null;
  }

  /// Typed Identity Ticket exchange result with non-secret diagnostics.
  static Future<InappifySdkResult<InappifyAuthenticationResult>>
  exchangeIdentityTicketResult({
    required String identityTicket,
    InappifyRequestCancellation? cancellation,
  }) async {
    return _record(
      await _coordinator.exchangeIdentityTicket(
        InappifyIdentityTicketRequest(
          identityTicket: identityTicket,
          cancellation: cancellation,
        ),
      ),
    );
  }

  /// Alias for [exchangeIdentityTicket].
  ///
  /// Call only one of these methods for a ticket because Identity Tickets are
  /// one-time credentials.
  static Future<InappifyAuthenticationResult?> loginWithIdentityTicket({
    required String identityTicket,
    InappifyRequestCancellation? cancellation,
  }) {
    return exchangeIdentityTicket(
      identityTicket: identityTicket,
      cancellation: cancellation,
    );
  }

  /// Typed alias for [exchangeIdentityTicketResult].
  ///
  /// A single-use ticket must be passed to exactly one exchange method.
  static Future<InappifySdkResult<InappifyAuthenticationResult>>
  loginWithIdentityTicketResult({
    required String identityTicket,
    InappifyRequestCancellation? cancellation,
  }) {
    return exchangeIdentityTicketResult(
      identityTicket: identityTicket,
      cancellation: cancellation,
    );
  }

  /// Creates a CAPTCHA challenge for an OTP flow that requires one.
  static Future<InappifyCaptchaChallenge?> createOtpCaptcha({
    InappifyRequestCancellation? cancellation,
  }) async {
    final result = await createOtpCaptchaResult(cancellation: cancellation);
    return result.isSuccess ? result.data : null;
  }

  /// Typed CAPTCHA challenge result.
  static Future<InappifySdkResult<InappifyCaptchaChallenge>>
  createOtpCaptchaResult({InappifyRequestCancellation? cancellation}) async {
    return _record(
      await _coordinator.createOtpCaptcha(
        InappifyNetworkRequest(cancellation: cancellation),
      ),
    );
  }

  /// Requests an OTP challenge for the supplied phone number.
  static Future<InappifyOtpChallenge?> requestOtp({
    required String phone,
    String? captchaKey,
    String? captchaAnswer,
    InappifyRequestCancellation? cancellation,
  }) async {
    final result = await requestOtpResult(
      phone: phone,
      captchaKey: captchaKey,
      captchaAnswer: captchaAnswer,
      cancellation: cancellation,
    );
    return result.isSuccess ? result.data : null;
  }

  /// Typed OTP challenge request with non-secret diagnostics.
  static Future<InappifySdkResult<InappifyOtpChallenge>> requestOtpResult({
    required String phone,
    String? captchaKey,
    String? captchaAnswer,
    InappifyRequestCancellation? cancellation,
  }) async {
    return _record(
      await _coordinator.requestOtp(
        InappifyOtpRequest(
          phone: phone,
          captchaKey: captchaKey,
          captchaAnswer: captchaAnswer,
          cancellation: cancellation,
        ),
      ),
    );
  }

  /// Verifies an OTP challenge and replaces the active session on success.
  static Future<InappifyAuthenticationResult?> verifyOtp({
    required String challengeId,
    required String code,
    InappifyRequestCancellation? cancellation,
  }) async {
    final result = await verifyOtpResult(
      challengeId: challengeId,
      code: code,
      cancellation: cancellation,
    );
    return result.isSuccess ? result.data : null;
  }

  /// Typed OTP verification result with non-secret diagnostics.
  static Future<InappifySdkResult<InappifyAuthenticationResult>>
  verifyOtpResult({
    required String challengeId,
    required String code,
    InappifyRequestCancellation? cancellation,
  }) async {
    return _record(
      await _coordinator.verifyOtp(
        InappifyOtpVerificationRequest(
          challengeId: challengeId,
          code: code,
          cancellation: cancellation,
        ),
      ),
    );
  }

  /// Starts a purchase using the backend selected during configuration.
  ///
  /// A returned URL remains owned by the Flutter application, matching the
  /// host application navigation contract. A failed or cancelled legacy
  /// purchase returns `null` for backward compatibility.
  static Future<PurchaseResult?> purchase({
    required String productIdentifier,
    required String offeringIdentifier,
    String? packageIdentifier,
    String? discountCode,
    String? country,
    String? appVersion,
    String? apiKey,
    int discount = 0,
    bool isCrypto = false,
    Market market = Market.none,
    String? marketKey,
    bool isLostPurchase = false,
    String? lostPurchaseToken,
    int? lostPurchaseTime,
    String? idempotencyKey,
    InappifyProductType? productType,
    String? dynamicPriceToken,
    int? paywallId,
    int? paywallRevision,
    InappifyRequestCancellation? cancellation,
  }) async {
    final result = await purchaseResult(
      productIdentifier: productIdentifier,
      offeringIdentifier: offeringIdentifier,
      packageIdentifier: packageIdentifier,
      discountCode: discountCode,
      country: country,
      appVersion: appVersion,
      apiKey: apiKey,
      discount: discount,
      isCrypto: isCrypto,
      market: market,
      marketKey: marketKey,
      isLostPurchase: isLostPurchase,
      lostPurchaseToken: lostPurchaseToken,
      lostPurchaseTime: lostPurchaseTime,
      idempotencyKey: idempotencyKey,
      productType: productType,
      dynamicPriceToken: dynamicPriceToken,
      paywallId: paywallId,
      paywallRevision: paywallRevision,
      cancellation: cancellation,
    );
    return result.isSuccess ? result.data : null;
  }

  /// Typed purchase variant preserving checkout correlation and failures.
  ///
  /// [idempotencyKey] must be reused only when retrying the same logical
  /// purchase attempt. Omit it to let the façade create a fresh identifier;
  /// typed failures expose that non-secret identifier in `details` so an
  /// ambiguous checkout can be reconciled or retried with the same key.
  static Future<InappifySdkResult<PurchaseResult>> purchaseResult({
    required String productIdentifier,
    required String offeringIdentifier,
    String? packageIdentifier,
    String? discountCode,
    String? country,
    String? appVersion,
    String? idempotencyKey,
    String? apiKey,
    int discount = 0,
    bool isCrypto = false,
    Market market = Market.none,
    String? marketKey,
    bool isLostPurchase = false,
    String? lostPurchaseToken,
    int? lostPurchaseTime,
    InappifyProductType? productType,
    String? dynamicPriceToken,
    int? paywallId,
    int? paywallRevision,
    InappifyRequestCancellation? cancellation,
  }) async {
    final resolvedIdempotencyKey = idempotencyKey ?? _nextRequestId('purchase');
    final result = await _coordinator.purchase(
      InappifyPurchaseRequest(
        productIdentifier: productIdentifier,
        offeringIdentifier: offeringIdentifier,
        idempotencyKey: resolvedIdempotencyKey,
        packageIdentifier: packageIdentifier,
        discountCode: discountCode,
        country: country,
        appVersion: appVersion,
        apiKey: apiKey,
        discount: discount,
        isCrypto: isCrypto,
        market: market,
        marketKey: marketKey,
        isLostPurchase: isLostPurchase,
        lostPurchaseToken: lostPurchaseToken,
        lostPurchaseTime: lostPurchaseTime,
        productType: productType,
        dynamicPriceToken: dynamicPriceToken,
        paywallId: paywallId,
        paywallRevision: paywallRevision,
        cancellation: cancellation,
      ),
    );
    return _record(
      _withIdempotencyKey(result, idempotencyKey: resolvedIdempotencyKey),
    );
  }

  /// Creates a canonical checkout without navigating the browser.
  ///
  /// Unlike the legacy [purchase] projection, this method preserves the
  /// server-authoritative price, expiry, status, and next action.
  static Future<InappifySdkResult<InappifyCheckoutResult>> createCheckout({
    required String productIdentifier,
    required String offeringIdentifier,
    required String packageIdentifier,
    String? discountCode,
    String? country,
    String? appVersion,
    String? idempotencyKey,
    bool isCrypto = false,
    InappifyRequestCancellation? cancellation,
  }) async {
    final resolvedIdempotencyKey = idempotencyKey ?? _nextRequestId('checkout');
    final result = await _coordinator.createCheckout(
      InappifyPurchaseRequest(
        productIdentifier: productIdentifier,
        offeringIdentifier: offeringIdentifier,
        packageIdentifier: packageIdentifier,
        discountCode: discountCode,
        country: country,
        appVersion: appVersion,
        idempotencyKey: resolvedIdempotencyKey,
        isCrypto: isCrypto,
        cancellation: cancellation,
      ),
    );
    return _record(
      _withIdempotencyKey(result, idempotencyKey: resolvedIdempotencyKey),
    );
  }

  /// Reads one authoritative checkout state without polling.
  static Future<InappifySdkResult<InappifyCheckoutResult>> getCheckoutStatus({
    required String checkoutId,
    InappifyRequestCancellation? cancellation,
  }) async {
    return _record(
      await _coordinator.getCheckoutStatus(
        InappifyCheckoutStatusRequest(
          checkoutId: checkoutId,
          cancellation: cancellation,
        ),
      ),
    );
  }

  /// Validates a discount code for the active customer.
  static Future<ValidateDiscountCodeData?> validateDiscountCode({
    required String discountCode,
    String? offeringIdentifier,
    InappifyRequestCancellation? cancellation,
  }) async {
    final result = await validateDiscountCodeResult(
      discountCode: discountCode,
      offeringIdentifier: offeringIdentifier,
      cancellation: cancellation,
    );
    return result.isSuccess ? result.data : null;
  }

  /// Typed discount validation result with sanitized provider diagnostics.
  static Future<InappifySdkResult<ValidateDiscountCodeData>>
  validateDiscountCodeResult({
    required String discountCode,
    String? offeringIdentifier,
    InappifyRequestCancellation? cancellation,
  }) async {
    return _record(
      await _coordinator.validateDiscountCode(
        InappifyDiscountCodeRequest(
          discountCode: discountCode,
          offeringIdentifier: offeringIdentifier,
          cancellation: cancellation,
        ),
      ),
    );
  }

  /// Ends the active session while preserving the historical bool result.
  static Future<bool> logout({
    InappifyRequestCancellation? cancellation,
  }) async {
    final result = await logoutResult(cancellation: cancellation);
    return result.isSuccess;
  }

  /// Typed logout result with the authoritative post-operation snapshot.
  static Future<InappifySdkResult<void>> logoutResult({
    InappifyRequestCancellation? cancellation,
  }) async {
    return _record(await _coordinator.logout(cancellation: cancellation));
  }

  /// Refreshes customer information from the backend that owns the session.
  static Future<CustomerInfo?> getCustomerInfo({
    bool forceRefresh = true,
    InappifyRequestCancellation? cancellation,
  }) async {
    final result = await getCustomerInfoResult(
      forceRefresh: forceRefresh,
      cancellation: cancellation,
    );
    return result.isSuccess ? result.data : null;
  }

  /// Typed customer refresh result.
  static Future<InappifySdkResult<CustomerInfo>> getCustomerInfoResult({
    bool forceRefresh = true,
    InappifyRequestCancellation? cancellation,
  }) async {
    return _record(
      await _coordinator.getCustomerInfo(
        force: forceRefresh,
        cancellation: cancellation,
      ),
    );
  }

  /// Returns token-free backend capabilities and browser allowlists.
  static Future<InappifyConfiguration?> getConfiguration() async {
    final result = await getConfigurationResult();
    return result.isSuccess ? result.data : null;
  }

  /// Typed, token-free configuration query.
  static Future<InappifySdkResult<InappifyConfiguration>>
  getConfigurationResult() async {
    return _record(await _coordinator.getConfiguration());
  }

  /// Returns cached offerings or forces a service refresh when requested.
  static Future<OfferingsModel?> getOfferings({
    bool forceRefresh = false,
    InappifyRequestCancellation? cancellation,
  }) async {
    final result = await getOfferingsResult(
      forceRefresh: forceRefresh,
      cancellation: cancellation,
    );
    return result.isSuccess ? result.data : null;
  }

  /// Typed offering refresh result, including cancellation failures.
  static Future<InappifySdkResult<OfferingsModel>> getOfferingsResult({
    bool forceRefresh = false,
    InappifyRequestCancellation? cancellation,
  }) async {
    return _record(
      await _coordinator.getOfferings(
        force: forceRefresh,
        cancellation: cancellation,
      ),
    );
  }

  /// Updates the runtime targeting context and invalidates offering caches.
  static Future<bool> setTargetingContext({
    String? country,
    String? appVersion,
  }) async {
    final result = await setTargetingContextResult(
      country: country,
      appVersion: appVersion,
    );
    return result.isSuccess;
  }

  /// Typed runtime-targeting update result.
  static Future<InappifySdkResult<void>> setTargetingContextResult({
    String? country,
    String? appVersion,
  }) async {
    return _record(
      await _coordinator.setTargetingContext(
        InappifyTargetingContextRequest(
          country: country,
          appVersion: appVersion,
        ),
      ),
    );
  }

  /// Resolves the current offering using backend-owned placement rules.
  static Future<OfferingModel?> getCurrentOffering({
    String? placementIdentifier,
    bool forceRefresh = false,
    Map<String, Object?>? context,
    InappifyRequestCancellation? cancellation,
  }) async {
    final result = await getCurrentOfferingResult(
      placementIdentifier: placementIdentifier,
      forceRefresh: forceRefresh,
      context: context,
      cancellation: cancellation,
    );
    return result.isSuccess ? result.data : null;
  }

  /// Typed placement-aware offering resolution result.
  ///
  /// A successful result may contain null when no rule selects an offering.
  static Future<InappifySdkResult<OfferingModel>> getCurrentOfferingResult({
    String? placementIdentifier,
    bool forceRefresh = false,
    Map<String, Object?>? context,
    InappifyRequestCancellation? cancellation,
  }) async {
    return _record(
      await _coordinator.getCurrentOffering(
        InappifyCurrentOfferingRequest(
          placementIdentifier: placementIdentifier,
          forceRefresh: forceRefresh,
          context: context,
          cancellation: cancellation,
        ),
      ),
    );
  }

  /// Returns whether the named entitlement is active in the mirrored snapshot.
  /// Go access decisions should use [checkEntitlementResult], which applies
  /// verified data and trusted time. This compatibility UI helper uses wall time.
  static bool isActiveEntitlement(String name) {
    for (final entitlement in customerInfo?.entitlements ?? const []) {
      if (entitlement.identifier == name && _isEntitlementActive(entitlement)) {
        return true;
      }
    }
    return false;
  }

  /// Alias for [isActiveEntitlement] matching the Web SDK terminology.
  static bool hasEntitlement(String identifier) {
    return isActiveEntitlement(identifier);
  }

  /// Returns the named entitlement from the latest customer snapshot.
  static EntitlementModel? getEntitlement(String identifier) {
    for (final entitlement in customerInfo?.entitlements ?? const []) {
      if (entitlement.identifier == identifier &&
          _isEntitlementActive(entitlement)) {
        return entitlement;
      }
    }
    return null;
  }

  /// Verifies an entitlement, refreshing customer information by default.
  static Future<bool> checkEntitlement(
    String identifier, {
    bool forceRefresh = true,
    InappifyRequestCancellation? cancellation,
  }) async {
    final result = await checkEntitlementResult(
      identifier,
      forceRefresh: forceRefresh,
      cancellation: cancellation,
    );
    return result.isSuccess && (result.data ?? false);
  }

  /// Typed entitlement verification result.
  static Future<InappifySdkResult<bool>> checkEntitlementResult(
    String identifier, {
    bool forceRefresh = true,
    InappifyRequestCancellation? cancellation,
  }) async {
    return _record(
      await _coordinator.checkEntitlement(
        InappifyEntitlementCheckRequest(
          identifier: identifier,
          forceRefresh: forceRefresh,
          cancellation: cancellation,
        ),
      ),
    );
  }

  /// Returns whether the supplied identifier represents an anonymous customer.
  static bool isCustomerAnonymous({required String? appUserIdentifier}) {
    if (_coordinator.state.mobileProtocol == InappifyMobileProtocol.goV2 &&
        appUserIdentifier != null &&
        RegExp(
          r'^\$INAAnonymousID:[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-4[0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$',
        ).hasMatch(appUserIdentifier)) {
      return true;
    }
    return appUserIdentifier == null ||
        appUserIdentifier.contains('InaAnonymous');
  }

  /// Stores or removes custom customer attributes.
  static Future<bool> setAttributes({
    required List<Attribute> attributes,
    InappifyRequestCancellation? cancellation,
  }) async {
    final result = await setAttributesResult(
      attributes: attributes,
      cancellation: cancellation,
    );
    return result.isSuccess;
  }

  /// Typed custom-attribute update result.
  static Future<InappifySdkResult<List<Attribute>>> setAttributesResult({
    required List<Attribute> attributes,
    InappifyRequestCancellation? cancellation,
  }) async {
    return _record(
      await _coordinator.setAttributes(
        InappifyAttributesRequest(
          attributes: attributes,
          cancellation: cancellation,
        ),
      ),
    );
  }

  /// Updates custom attributes using the Web SDK map-style API.
  static Future<bool> updateAttributes({
    required Map<String, String?> values,
    InappifyRequestCancellation? cancellation,
  }) {
    return setAttributes(
      attributes: values.entries
          .map((entry) => Attribute(key: entry.key, value: entry.value))
          .toList(growable: false),
      cancellation: cancellation,
    );
  }

  /// Typed map-style custom-attribute update result.
  static Future<InappifySdkResult<List<Attribute>>> updateAttributesResult({
    required Map<String, String?> values,
    InappifyRequestCancellation? cancellation,
  }) {
    return setAttributesResult(
      attributes: values.entries
          .map((entry) => Attribute(key: entry.key, value: entry.value))
          .toList(growable: false),
      cancellation: cancellation,
    );
  }

  /// Deletes custom attributes by key.
  static Future<bool> deleteAttributes({
    required List<String> keys,
    InappifyRequestCancellation? cancellation,
  }) async {
    final result = await deleteAttributesResult(
      keys: keys,
      cancellation: cancellation,
    );
    return result.isSuccess;
  }

  /// Typed custom-attribute deletion result.
  static Future<InappifySdkResult<List<Attribute>>> deleteAttributesResult({
    required List<String> keys,
    InappifyRequestCancellation? cancellation,
  }) async {
    return _record(
      await _coordinator.deleteAttributes(
        InappifyDeleteAttributesRequest(keys: keys, cancellation: cancellation),
      ),
    );
  }

  /// Stores or removes the reserved customer email attribute.
  static Future<bool> setEmail({
    required String email,
    InappifyRequestCancellation? cancellation,
  }) {
    return _setReserved(
      InappifyReservedAttribute.email,
      email,
      cancellation: cancellation,
    );
  }

  /// Stores the reserved APNs device token attribute.
  static Future<bool> setApnsToken({
    required String apnsToken,
    InappifyRequestCancellation? cancellation,
  }) {
    return _setReserved(
      InappifyReservedAttribute.apnsToken,
      apnsToken,
      cancellation: cancellation,
    );
  }

  /// Legacy spelling retained because it is used by existing applications.
  static Future<bool> setDisplayname({
    required String displayName,
    InappifyRequestCancellation? cancellation,
  }) {
    return _setReserved(
      InappifyReservedAttribute.displayName,
      displayName,
      cancellation: cancellation,
    );
  }

  /// Stores the reserved FCM device token attribute.
  static Future<bool> setFcmToken({
    required String fcmToken,
    InappifyRequestCancellation? cancellation,
  }) {
    return _setReserved(
      InappifyReservedAttribute.fcmToken,
      fcmToken,
      cancellation: cancellation,
    );
  }

  /// Stores the reserved Apple advertising identifier attribute.
  static Future<bool> setIdfa({
    required String idfa,
    InappifyRequestCancellation? cancellation,
  }) {
    return _setReserved(
      InappifyReservedAttribute.idfa,
      idfa,
      cancellation: cancellation,
    );
  }

  /// Stores the reserved Apple vendor identifier attribute.
  static Future<bool> setIdfv({
    required String idfv,
    InappifyRequestCancellation? cancellation,
  }) {
    return _setReserved(
      InappifyReservedAttribute.idfv,
      idfv,
      cancellation: cancellation,
    );
  }

  /// Stores the reserved customer IP attribute.
  static Future<bool> setIp({
    required String ip,
    InappifyRequestCancellation? cancellation,
  }) {
    return _setReserved(
      InappifyReservedAttribute.ip,
      ip,
      cancellation: cancellation,
    );
  }

  /// Stores the reserved customer phone-number attribute.
  static Future<bool> setPhoneNumber({
    required String phoneNumber,
    InappifyRequestCancellation? cancellation,
  }) {
    return _setReserved(
      InappifyReservedAttribute.phoneNumber,
      phoneNumber,
      cancellation: cancellation,
    );
  }

  /// Stores the reserved acquisition campaign attribute.
  static Future<bool> setCampaign({
    required String campaign,
    InappifyRequestCancellation? cancellation,
  }) {
    return _setReserved(
      InappifyReservedAttribute.campaign,
      campaign,
      cancellation: cancellation,
    );
  }

  /// Stores the reserved acquisition keyword attribute.
  static Future<bool> setKeyword({
    required String keyword,
    InappifyRequestCancellation? cancellation,
  }) {
    return _setReserved(
      InappifyReservedAttribute.keyword,
      keyword,
      cancellation: cancellation,
    );
  }

  /// Stores the reserved customer display-name attribute.
  static Future<bool> setDisplayName({
    required String displayName,
    InappifyRequestCancellation? cancellation,
  }) {
    return _setReserved(
      InappifyReservedAttribute.displayName,
      displayName,
      cancellation: cancellation,
    );
  }

  /// Synchronizes all customer attributes with the selected backend.
  static Future<bool> syncAttributes({
    List<Attribute>? attributes,
    String? idempotencyKey,
    InappifyRequestCancellation? cancellation,
  }) async {
    final result = await syncAttributesResult(
      attributes: attributes,
      idempotencyKey: idempotencyKey,
      cancellation: cancellation,
    );
    return result.isSuccess;
  }

  /// Typed full-attribute synchronization result.
  static Future<InappifySdkResult<List<Attribute>>> syncAttributesResult({
    List<Attribute>? attributes,
    String? idempotencyKey,
    InappifyRequestCancellation? cancellation,
  }) async {
    return _record(
      await _coordinator.syncAttributeValues(
        InappifyAttributesRequest(
          attributes:
              attributes ?? customerInfo?.attributes ?? const <Attribute>[],
          idempotencyKey: idempotencyKey,
          cancellation: cancellation,
        ),
      ),
    );
  }

  /// Returns whether the selected backend permits a reserved attribute key.
  static Future<bool> canSetReservedAttribute(String key) async {
    final result = await canSetReservedAttributeResult(key);
    return result.isSuccess && (result.data ?? false);
  }

  /// Typed reserved-attribute capability result.
  static Future<InappifySdkResult<bool>> canSetReservedAttributeResult(
    String key,
  ) async {
    return _record(
      await _coordinator.canSetReservedAttribute(
        InappifyReservedAttributeCapabilityRequest(key: key),
      ),
    );
  }

  /// Returns the non-secret checkout id retained across a browser redirect.
  static Future<String?> getPendingCheckoutId() async {
    final result = await getPendingCheckoutIdResult();
    return result.isSuccess ? result.data : null;
  }

  /// Typed pending-checkout query result.
  ///
  /// Success with null means that the active session has no pending checkout.
  static Future<InappifySdkResult<String>> getPendingCheckoutIdResult() async {
    return _record(await _coordinator.getPendingCheckoutId());
  }

  /// Polls authoritative checkout state after returning from a payment page.
  static Future<InappifyCheckoutResult?> handlePaymentReturn({
    String? checkoutId,
    int timeoutMs = 60000,
    int intervalMs = 1500,
    InappifyRequestCancellation? cancellation,
  }) async {
    final result = await handlePaymentReturnResult(
      checkoutId: checkoutId,
      timeoutMs: timeoutMs,
      intervalMs: intervalMs,
      cancellation: cancellation,
    );
    return result.isSuccess ? result.data : null;
  }

  /// Typed authoritative checkout polling result.
  ///
  /// When [checkoutId] is omitted, the Web backend uses the non-secret id it
  /// saved in `sessionStorage` before redirecting. Query-string payment status
  /// is never trusted as authoritative state.
  static Future<InappifySdkResult<InappifyCheckoutResult>>
  handlePaymentReturnResult({
    String? checkoutId,
    int timeoutMs = 60000,
    int intervalMs = 1500,
    InappifyRequestCancellation? cancellation,
  }) async {
    var resolvedCheckoutId = checkoutId;
    if (resolvedCheckoutId == null || resolvedCheckoutId.isEmpty) {
      final pending = await getPendingCheckoutIdResult();
      if (!pending.isSuccess) {
        return InappifySdkResult<InappifyCheckoutResult>.failure(
          pending.failure!,
          snapshot: pending.snapshot,
        );
      }
      resolvedCheckoutId = pending.data;
    }
    if (resolvedCheckoutId == null || resolvedCheckoutId.isEmpty) {
      return _record(
        InappifySdkResult<InappifyCheckoutResult>.failure(
          const InappifyFailure(
            code: InappifyFailureCode.invalidConfiguration,
            message: 'No pending Inappify checkout is available.',
            details: <String, Object?>{'operation': 'handlePaymentReturn'},
          ),
        ),
      );
    }
    return _record(
      await _coordinator.handlePaymentReturn(
        InappifyPaymentReturnRequest(
          checkoutId: resolvedCheckoutId,
          timeoutMs: timeoutMs,
          intervalMs: intervalMs,
          cancellation: cancellation,
        ),
      ),
    );
  }

  static Future<bool> _setReserved(
    InappifyReservedAttribute attribute,
    String value, {
    InappifyRequestCancellation? cancellation,
  }) async {
    final result = await setReservedAttributeResult(
      attribute: attribute,
      value: value,
      cancellation: cancellation,
    );
    return result.isSuccess;
  }

  /// Typed reserved-attribute update result.
  static Future<InappifySdkResult<void>> setReservedAttributeResult({
    required InappifyReservedAttribute attribute,
    required String value,
    InappifyRequestCancellation? cancellation,
  }) async {
    return _record(
      await _coordinator.setReservedAttribute(
        InappifyReservedAttributeRequest(
          attribute: attribute,
          value: value,
          cancellation: cancellation,
        ),
      ),
    );
  }

  static InappifySdkResult<T> _record<T>(InappifySdkResult<T> result) {
    _lastFailure = result.failure;
    return result;
  }

  /// Convenience configuration for the default mobile V2 protocol.
  /// Use [configureResult] when providing a market and its billing public key.
  static Future<InappifySdkResult<void>> configureGoV2({
    required String apiKey,
    String? appUserIdentifier,
    String? country,
    String? appVersion,
    bool enableSubscriptionRecoveryWithoutPayload = true,
  }) => configureResult(
    apiKey: apiKey,
    appUserIdentifier: appUserIdentifier,
    country: country,
    appVersion: appVersion,
    mobileProtocol: InappifyMobileProtocol.goV2,
    enableSubscriptionRecoveryWithoutPayload:
        enableSubscriptionRecoveryWithoutPayload,
  );

  /// Reconciles ambiguous/pending purchases; do this before starting a new attempt.
  static Future<InappifySdkResult<List<PurchaseResult>>>
  syncPurchases() async => _record(await _coordinator.syncPurchases());

  static Future<InappifySdkResult<InappifyRestoreResult>>
  restorePurchases() async => _record(await _coordinator.restorePurchases());

  /// Returns server-authoritative deliveries. Does not grant host inventory.
  static Future<InappifySdkResult<InappifyConsumableSyncResult>>
  syncPendingConsumables() async =>
      _record(await _coordinator.syncPendingConsumables());

  /// Call ONLY after durably granting this delivery once for the same app/user.
  /// A failed acknowledgement must not cause a second inventory grant.
  static Future<InappifySdkResult<PurchaseResult>> confirmDelivery(
    int deliveryId,
  ) async => _record(await _coordinator.confirmDelivery(deliveryId));

  static Future<InappifySdkResult<CustomerInfo>> customerInfoWithPolicy(
    InappifyFetchPolicy policy,
  ) async => _record(await _coordinator.customerInfoWithPolicy(policy));
  static Future<InappifySdkResult<OfferingsModel>> offeringsWithPolicy(
    InappifyFetchPolicy policy,
  ) async => _record(await _coordinator.offeringsWithPolicy(policy));

  /// Go attributes are write-only. Null/empty removes a key, not the user.
  static Future<InappifySdkResult<void>> queueAttributes(
    Map<String, String?> values,
  ) async => _record(await _coordinator.queueAttributes(values));
  static Future<InappifySdkResult<void>> flushAttributes() async =>
      _record(await _coordinator.flushAttributes());
  static Future<InappifySdkResult<void>> recover() async =>
      _record(await _coordinator.recover());
  static Future<InappifySdkResult<void>> setNetworkEnabled(
    bool enabled,
  ) async => _record(await _coordinator.setNetworkEnabled(enabled));

  static Future<InappifySdkResult<bool>> isPaymentUrlAllowed(
    String url,
  ) async => _record(await _coordinator.isPaymentUrlAllowed(url));

  static InappifySdkResult<T> _withIdempotencyKey<T>(
    InappifySdkResult<T> result, {
    required String idempotencyKey,
  }) {
    final failure = result.failure;
    if (failure == null) return result;
    return InappifySdkResult<T>.failure(
      InappifyFailure(
        code: failure.code,
        message: failure.message,
        isRetryable: failure.isRetryable,
        details: <String, Object?>{
          ...failure.details,
          'idempotencyKey': idempotencyKey,
        },
      ),
      snapshot: result.snapshot,
    );
  }

  static bool _isEntitlementActive(EntitlementModel entitlement) {
    if (entitlement.isActive != true) return false;
    final expiration = entitlement.expirationDate;
    if (expiration == null || expiration.isEmpty) return true;
    final parsed = DateTime.tryParse(expiration);
    if (_coordinator.state.mobileProtocol == InappifyMobileProtocol.goV2 &&
        parsed == null) {
      return false;
    }
    return parsed == null || parsed.isAfter(DateTime.now());
  }

  static String _nextRequestId(String operation) {
    _requestSequence += 1;
    return '$operation-${DateTime.now().microsecondsSinceEpoch}-$_requestSequence';
  }
}
