import 'package:inappify_sdk/src/logging/sdk_logger.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:inappify_sdk/inappify_sdk_platform_interface.dart';
import 'package:inappify_sdk/models/attribute.dart';
import 'package:inappify_sdk/models/customer_info.dart';
import 'package:inappify_sdk/models/inappify_configuration.dart';
import 'package:inappify_sdk/models/enums/market.dart';
import 'package:inappify_sdk/models/enums/purchase_status.dart';
import 'package:inappify_sdk/models/offering_model.dart';
import 'package:inappify_sdk/models/offerings_model.dart';
import 'package:inappify_sdk/models/purchase_result.dart';
import 'package:inappify_sdk/models/validate_discount_code_data.dart';
import 'package:inappify_sdk/src/platform/mobile/go_v2_infrastructure.dart';
import 'package:inappify_sdk/src/platform/mobile/go_v2_protocol.dart';

/// Explicit iOS Go backend. V1 preferences, static compatibility credentials,
/// and the browser implementation are deliberately not used by this client.
class GoV2Platform extends InappifySdkPlatform {
  GoV2Platform({
    GoV2Transport? transport,
    GoV2Transport? commerceTransport,
    GoV2Storage? storage,
    GoV2MetadataProvider? metadataProvider,
    GoV2Verifier? verifier,
    DateTime Function()? now,
    int Function()? monotonicMilliseconds,
    String Function()? anonymousIdFactory,
    String Function()? attemptIdFactory,
    this.backgroundRecovery = true,
  }) : _transport = transport ?? DioGoV2Transport(),
       _commerceTransport = commerceTransport ?? DioGoV2Transport.commerce(),
       _storage = storage ?? MethodChannelGoV2Storage(),
       _metadataProvider = metadataProvider ?? readGoV2MobileMetadata,
       _trustedClock = _TrustedGoV2Clock(
         now ?? DateTime.now,
         monotonicMilliseconds,
       ),
       _targetingSyncLimiter = _TargetingSyncRateLimiter(monotonicMilliseconds),
       _now = now ?? DateTime.now,
       _anonymousIdFactory = anonymousIdFactory ?? _newAnonymousId,
       _attemptIdFactory = attemptIdFactory ?? _newAttemptId {
    _verifier = verifier ?? GoV2Verifier(now: _trustedClock.now);
  }

  final GoV2Transport _transport;
  final GoV2Transport _commerceTransport;
  final GoV2Storage _storage;
  final GoV2MetadataProvider _metadataProvider;
  late final GoV2Verifier _verifier;
  final _TrustedGoV2Clock _trustedClock;
  final _TargetingSyncRateLimiter _targetingSyncLimiter;
  final DateTime Function() _now;
  final String Function() _anonymousIdFactory;
  final String Function() _attemptIdFactory;
  final bool backgroundRecovery;
  final _events = StreamController<InappifyPlatformEvent>.broadcast();
  late final _traceEvents = StreamController<InappifyHttpTrace>.broadcast(
    onListen: _listenTraces,
    onCancel: _stopTraces,
  );
  StreamSubscription<Map<String, Object?>>? _goTraceSubscription;
  StreamSubscription<Map<String, Object?>>? _commerceTraceSubscription;
  final Map<String, Future<InappifySdkResult<dynamic>>> _shared = {};
  Future<void> _tail = Future<void>.value();
  Map<String, dynamic> _document = {};
  InappifyConfigureRequest? _options;
  GoV2Metadata? _metadata;
  String? _fingerprint;
  DateTime? _renewalBlockedUntil;
  GoV2ProtocolException? _renewalFailure;
  int _revision = 0;
  bool _closed = false;

  @override
  Stream<InappifyPlatformEvent> get events => _events.stream;

  @override
  Stream<InappifyHttpTrace> get httpTraces => _traceEvents.stream;

  void _forwardTrace(Map<String, Object?> trace) {
    if (_closed || !_traceEvents.hasListener) return;
    try {
      _traceEvents.add(
        InappifyHttpTrace.fromMap(Map<String, dynamic>.from(trace)),
      );
    } catch (_) {
      /* Malformed diagnostic data must not affect SDK state. */
    }
  }

  void _listenTraces() {
    _goTraceSubscription ??= _transport.traces.listen(_forwardTrace);
    _commerceTraceSubscription ??= _commerceTransport.traces.listen(
      _forwardTrace,
    );
  }

  void _stopTraces() {
    unawaited(_goTraceSubscription?.cancel());
    unawaited(_commerceTraceSubscription?.cancel());
    _goTraceSubscription = null;
    _commerceTraceSubscription = null;
  }

  bool get _logoutPending => _document['pendingLogout'] == true;
  bool get _loginPending => _document.containsKey('pendingLogin');
  bool get _identityPending => _logoutPending || _loginPending;
  Map<String, dynamic>? get _session => _objectOrNull(_document['session']);
  Map<String, Object?>? get verifiedScope {
    final scope = _objectOrNull(_document['scope']);
    return _identityPending || scope == null || _session == null
        ? null
        : Map<String, Object?>.unmodifiable(scope);
  }

  /// Each projection is reconstructed so host mutation cannot modify the
  /// signature-verified canonical document used by subsequent operations.
  InappifySdkSnapshot get snapshot {
    final session = _session;
    final active = !_identityPending && session != null;
    final envelope = _objectOrNull(_document['info']);
    final rawCustomer = active
        ? _objectOrNull(envelope?['customerInfo'])
        : null;
    final customer = rawCustomer == null ? null : _customer(rawCustomer);
    final rawOfferings = active ? _objectOrNull(_document['offerings']) : null;
    return InappifySdkSnapshot(
      accessToken: '',
      apiKey: '',
      customerInfo: customer,
      offerings: rawOfferings == null
          ? null
          : OfferingsModel.fromJson(_copy(rawOfferings)),
      storeInfo: active ? session['storeInfo'] as String? : null,
      appId: active ? session['appId'] as int? : null,
      forceVersion: null,
      country: _document['country'] as String? ?? 'IR',
      versionName:
          _document['appVersion'] as String? ?? _metadata?.versionName ?? '',
      versionCode: _metadata?.versionCode,
      sdkVersion: goV2SdkVersion,
      revision: _revision,
      isConfigured: active,
      isAuthenticated: active && !_isAnonymous(session['appUserId'] as String),
      appUserIdentifier: active ? session['appUserId'] as String : null,
      storePlatform: active ? session['storePlatform'] as int : null,
      market: active && session['storePlatform'] == 1 ? 'none' : null,
      mobileProtocol: InappifyMobileProtocol.goV2,
      isLogoutPending: _logoutPending,
      sessionState: _identityPending
          ? InappifySessionState.recoveryRequired
          : !active
          ? InappifySessionState.unconfigured
          : _isAnonymous(session['appUserId'] as String)
          ? InappifySessionState.anonymous
          : InappifySessionState.authenticated,
      persistenceMode: InappifySessionPersistenceMode.durable,
    );
  }

  @override
  Future<InappifyBackendCapabilities> getCapabilities() async =>
      InappifyBackendCapabilities(
        backendKind: InappifyBackendKind.dart,
        protocolVersion: InappifyBackendCapabilities.currentProtocolVersion,
        ownsSession: true,
        supportedOperations: {
          InappifyOperation.configure,
          InappifyOperation.login,
          InappifyOperation.logout,
          InappifyOperation.purchase,
          InappifyOperation.validateDiscountCode,
          InappifyOperation.getCustomerInfo,
          InappifyOperation.getOfferings,
          InappifyOperation.syncAttributesAndOfferingsIfNeeded,
          InappifyOperation.setAttributes,
          InappifyOperation.setReservedAttribute,
          InappifyOperation.syncAttributes,
          InappifyOperation.setTargetingContext,
          InappifyOperation.getCurrentOffering,
          InappifyOperation.checkEntitlement,
          InappifyOperation.deleteAttributes,
          InappifyOperation.syncAttributeValues,
          InappifyOperation.canSetReservedAttribute,
          InappifyOperation.getConfiguration,
          InappifyOperation.goV2,
        },
        sdkVersion: goV2SdkVersion,
      );

  @override
  Future<InappifyAppVersionInfo?> getAppVersionInfo() async {
    final metadata = _metadata ?? await _metadataProvider();
    return InappifyAppVersionInfo(
      versionName: metadata.versionName,
      versionCode: metadata.versionCode,
    );
  }

  @override
  Future<InappifySdkResult<void>> configure(
    InappifyConfigureRequest request,
  ) => _share<void>(
    'configure:${_hash(jsonEncode(request.toMap()))}',
    () => _run<void>('configure', () async {
      if (request.apiKey.trim().isEmpty) {
        _fail('VALIDATION', 'API_KEY_REQUIRED');
      }
      if (request.appUserIdentifier != null &&
          !_validIdentity(request.appUserIdentifier!)) {
        _fail('VALIDATION', 'APP_USER_ID_INVALID');
      }
      _validateTargeting(request.country, request.appVersion);
      final metadata = _metadata ?? await _metadataProvider();
      if (metadata.identifierValue.trim().isEmpty ||
          metadata.versionCode < 1 ||
          metadata.versionName.trim().isEmpty) {
        _fail('CONFIGURATION', 'INVALID_APP_METADATA');
      }
      final fingerprint = _hash(
        jsonEncode(['go-v2-ios-1', request.apiKey, metadata.identifierValue]),
      );
      if (_fingerprint != null && _fingerprint != fingerprint) {
        _fail('CONFIGURATION', 'CREATE_NEW_CLIENT_FOR_APP_CHANGE');
      }
      _metadata = metadata;
      _options = request;
      if (_fingerprint == null) {
        _fingerprint = fingerprint;
        try {
          await _load(fingerprint);
        } catch (_) {
          _fingerprint = null;
          rethrow;
        }
      }
      if (_logoutPending) {
        await _logout();
        return;
      }
      if (_loginPending) {
        final target = _object(_document['pendingLogin'])['appUserId'];
        if (request.appUserIdentifier != null &&
            request.appUserIdentifier != target) {
          _fail('AUTH', 'LOGIN_PENDING');
        }
        await _resumeLogin();
        _scheduleRecovery();
        return;
      }
      final oldSession = _session;
      final retainedIdentity =
          oldSession?['appUserId'] as String? ??
          _document['retainedIdentity'] as String? ??
          _document['anonymousId'] as String?;
      final identity =
          request.appUserIdentifier ??
          retainedIdentity ??
          _anonymousIdFactory();
      if (!_validIdentity(identity)) _fail('VALIDATION', 'APP_USER_ID_INVALID');
      final country = _normalizeCountry(
        request.country ?? _document['country'] as String? ?? 'IR',
      );
      final version = request.appVersion ?? metadata.versionName;
      final contextChanged =
          oldSession != null &&
          (_document['country'] != country ||
              _document['appVersion'] != version);
      if (contextChanged &&
          oldSession['appUserId'] == identity &&
          _document.containsKey('offerings')) {
        // Keep the old context until signed Configure succeeds, but never
        // display a catalog targeted at an obsolete country/application version.
        await _commit(_copy(_document)..remove('offerings'));
      }
      if (oldSession != null &&
          oldSession['appUserId'] == identity &&
          !contextChanged &&
          _document['sessionInvalid'] != true &&
          goV2IsoDate(
            oldSession['sessionExpiresAt'] as String,
          ).isAfter(_now())) {
        _scheduleRecovery();
        return;
      }
      if (_isAnonymous(identity) && _document['anonymousId'] != identity) {
        await _commit({..._copy(_document), 'anonymousId': identity});
      }
      await _configureOnline(identity);
      _scheduleRecovery();
    }),
  );

  Future<void> _load(String fingerprint) async {
    String? raw;
    try {
      raw = await _storage.read();
    } catch (_) {
      _fail('STORAGE', 'READ_FAILED');
    }
    if (raw == null) return;
    Map<String, dynamic> saved;
    try {
      saved = strictGoV2Json(raw);
    } catch (_) {
      // An unreadable secure document may contain a pending logout intent.
      _fail('STORAGE', 'INVALID_SESSION_DOCUMENT');
    }
    if (saved['fingerprint'] != fingerprint) return;
    final session = _objectOrNull(saved['session']);
    if (session == null) {
      if (saved.containsKey('pendingLogin')) {
        _fail('AUTH', 'INVALID_PENDING_LOGIN_CACHE');
      }
      if (saved['pendingLogout'] == true) {
        _fail('AUTH', 'INVALID_PENDING_LOGOUT_CACHE');
      }
      final anonymous = saved['anonymousId'];
      if (anonymous is String &&
          _validIdentity(anonymous) &&
          _isAnonymous(anonymous)) {
        _document = {'anonymousId': anonymous, 'fingerprint': fingerprint};
      }
      return;
    }
    try {
      final identity = session['appUserId'];
      if (identity is! String || !_validIdentity(identity)) {
        _fail('SIGNATURE', 'INVALID_IDENTITY');
      }
      await _ensureKey(session);
      final verified = await _verifier.verify(
        session,
        expectedPublicUserId: identity,
        expectedScope: _objectOrNull(saved['scope']),
        expectedSubject: saved['customerSubject'] as String?,
        allowExpiredCache: true,
      );
      _validateSession(
        session,
        allowExpired: true,
        allowMissingToken: saved['sessionInvalid'] == true,
      );
      if (session['appId'] != verified.scope['appId']) {
        _fail('SIGNATURE', 'SCOPE_MISMATCH');
      }
      final info = _objectOrNull(saved['info']);
      if (info != null) {
        await _ensureKey(info);
        await _verifier.verify(
          info,
          expectedPublicUserId: identity,
          expectedScope: verified.scope,
          expectedSubject: verified.subject,
          allowExpiredCache: true,
        );
      }
      saved['scope'] = verified.scope;
      saved['customerSubject'] = verified.subject;
      final pendingLogin = _objectOrNull(saved['pendingLogin']);
      if (saved.containsKey('pendingLogin') &&
          (pendingLogin == null ||
              pendingLogin['appUserId'] is! String ||
              !_validIdentity(pendingLogin['appUserId'] as String) ||
              _isAnonymous(pendingLogin['appUserId'] as String) ||
              !_validAttempt(pendingLogin['attemptId']))) {
        _fail('AUTH', 'INVALID_PENDING_LOGIN_CACHE');
      }
      if (saved.containsKey('pendingLogoutAttempt') &&
          !_validAttempt(
            _objectOrNull(saved['pendingLogoutAttempt'])?['attemptId'],
          )) {
        _fail('AUTH', 'INVALID_PENDING_LOGOUT_CACHE');
      }
      for (final key in ['session', 'info', 'offerings']) {
        _objectOrNull(saved[key])
          ?..remove('forceVersion')
          ..remove('hasForceUpdate');
      }
      if (saved['offerings'] != null) {
        OfferingsModel.fromJson(_copy(_object(saved['offerings'])));
      }
      _document = _copy(saved);
      _observeVerifiedTime();
      _emit();
    } catch (_) {
      if (saved.containsKey('pendingLogin')) {
        _fail('AUTH', 'INVALID_PENDING_LOGIN_CACHE');
      }
      if (saved['pendingLogout'] == true) {
        _fail('AUTH', 'INVALID_PENDING_LOGOUT_CACHE');
      }
      final identity = saved['anonymousId'] ?? session['appUserId'];
      _document = {
        if (identity is String && _validIdentity(identity))
          'retainedIdentity': identity,
        if (identity is String &&
            _isAnonymous(identity) &&
            _validIdentity(identity))
          'anonymousId': identity,
        if (_objectOrNull(saved['scope']) != null)
          'scope': _copy(_object(saved['scope'])),
      };
    }
  }

  Future<void> _ensureKey(Map<String, dynamic> envelope) async {
    final key = _objectOrNull(envelope['verification'])?['keyId'];
    if (key is! String) _fail('SIGNATURE', 'MISSING_VERIFICATION');
    if (!_verifier.known(key)) {
      _verifier.refresh(await _transport.request('public-keys'));
    }
  }

  Future<void> _configureOnline(
    String identity, {
    bool keepLoginPending = false,
    bool? keepLogoutPending,
    bool retry = true,
  }) async {
    final response = await _transport.request(
      'configure',
      retry: retry,
      bearer: _options!.apiKey,
      body: {
        'appUserIdentifier': identity,
        'identifierValue': _metadata!.identifierValue,
        'versionName': _options!.appVersion ?? _metadata!.versionName,
        'versionCode': _metadata!.versionCode,
        'sdkVersion': goV2SdkVersion,
        'country': _normalizeCountry(
          _options!.country ?? _document['country'] as String? ?? 'IR',
        ),
      },
    );
    await _accept(
      response,
      identity,
      keepLogoutPending: keepLogoutPending ?? _logoutPending,
      keepLoginPending: keepLoginPending,
    );
  }

  void _validateSession(
    Map<String, dynamic> response, {
    bool allowExpired = false,
    bool allowMissingToken = false,
  }) {
    final token = response['sessionToken'];
    if (response['appId'] is! int ||
        (response['appId'] as int) <= 0 ||
        response['sessionType'] != 'public' ||
        ((token is! String || token.isEmpty) &&
            !(allowMissingToken && token == null)) ||
        response['storePlatform'] is! int ||
        (response['storeInfo'] != null && response['storeInfo'] is! String)) {
      _fail('SIGNATURE', 'INVALID_SESSION');
    }
    final expiry = response['sessionExpiresAt'];
    if (expiry is! String) {
      _fail('SIGNATURE', 'INVALID_SESSION');
    }
    final expiresAt = goV2IsoDate(expiry);
    if (!allowExpired && !expiresAt.isAfter(_now())) {
      _fail('SIGNATURE', 'INVALID_SESSION');
    }
  }

  Future<void> _accept(
    Map<String, dynamic> response,
    String? identity, {
    bool transition = false,
    bool keepLogoutPending = false,
    bool keepLoginPending = false,
  }) async {
    final actualIdentity = response['appUserId'];
    if (actualIdentity is! String ||
        !_validIdentity(actualIdentity) ||
        (identity != null && actualIdentity != identity) ||
        (identity == null && !_isAnonymous(actualIdentity))) {
      _fail('SIGNATURE', 'IDENTITY_MISMATCH');
    }
    _validateSession(response);
    await _ensureKey(response);
    final changed = _session?['appUserId'] != actualIdentity;
    final verified = await _verifier.verify(
      response,
      expectedPublicUserId: actualIdentity,
      expectedScope: _objectOrNull(_document['scope']),
      expectedSubject: changed || transition
          ? null
          : _document['customerSubject'] as String?,
    );
    if (response['appId'] != verified.scope['appId']) {
      _fail('SIGNATURE', 'SCOPE_MISMATCH');
    }
    _customer(verified.info);
    final bindingChanged =
        changed || _document['customerSubject'] != verified.subject;
    final next = bindingChanged ? <String, dynamic>{} : _copy(_document);
    next['scope'] = verified.scope;
    next['customerSubject'] = verified.subject;
    final v2Response = _copy(response)
      ..remove('forceVersion')
      ..remove('hasForceUpdate');
    next['session'] = _copy(v2Response);
    next['info'] = v2Response;
    next['infoFetchedAt'] = _now().millisecondsSinceEpoch;
    next['country'] = _normalizeCountry(
      _options!.country ?? _document['country'] as String? ?? 'IR',
    );
    next['appVersion'] = _options!.appVersion ?? _metadata!.versionName;
    if (keepLoginPending && _loginPending) {
      next['pendingLogin'] = _copy(_object(_document['pendingLogin']));
    } else {
      next.remove('pendingLogin');
    }
    if (keepLogoutPending) {
      next['pendingLogout'] = true;
      if (_document['pendingLogoutAttempt'] != null) {
        next['pendingLogoutAttempt'] = _copy(
          _object(_document['pendingLogoutAttempt']),
        );
      }
    } else {
      next.remove('pendingLogout');
      next.remove('pendingLogoutAttempt');
    }
    next.remove('sessionInvalid');
    next.remove('offerings');
    if (_isAnonymous(actualIdentity)) next['anonymousId'] = actualIdentity;
    await _commit(next);
  }

  Future<Map<String, dynamic>> _request(
    String endpoint, {
    Map<String, Object?> body = const {},
    bool retry = true,
    bool allowLogout = false,
  }) async {
    _requireSession(allowLogout: allowLogout);
    var session = _session!;
    if (_document['sessionInvalid'] == true ||
        !goV2IsoDate(session['sessionExpiresAt'] as String).isAfter(_now())) {
      await _renew(session['appUserId'] as String);
      session = _session!;
    }
    Future<Map<String, dynamic>> send() => _transport.request(
      endpoint,
      bearer: session['sessionToken'] as String,
      body: body,
      retry: retry,
    );
    try {
      return await send();
    } on GoV2ProtocolException catch (error) {
      if (error.code != 'SESSION_EXPIRED' ||
          error.details['httpStatus'] != 401) {
        rethrow;
      }
      await _renew(session['appUserId'] as String);
      session = _session!;
      return send();
    }
  }

  Future<void> _renew(String identity, {bool retry = true}) async {
    if (_renewalBlockedUntil?.isAfter(_now()) == true &&
        _renewalFailure != null) {
      throw _renewalFailure!;
    }
    try {
      await _configureOnline(identity, retry: retry);
      _renewalBlockedUntil = null;
      _renewalFailure = null;
    } on GoV2ProtocolException catch (error) {
      _renewalFailure = error;
      _renewalBlockedUntil = _now().add(const Duration(seconds: 15));
      rethrow;
    }
  }

  @override
  Future<InappifySdkResult<void>> login(InappifyLoginRequest request) =>
      _run('login', () async {
        if (!_validIdentity(request.appUserIdentifier) ||
            _isAnonymous(request.appUserIdentifier)) {
          _fail('VALIDATION', 'APP_USER_ID_INVALID');
        }
        if (_logoutPending) _fail('AUTH', 'LOGOUT_PENDING');
        _requireNetwork();
        final pending = _objectOrNull(_document['pendingLogin']);
        if (pending != null) {
          if (pending['appUserId'] != request.appUserIdentifier) {
            _fail('AUTH', 'LOGIN_PENDING');
          }
        } else {
          await _readySession();
          await _commit({
            ..._copy(_document),
            'pendingLogin': {
              'appUserId': request.appUserIdentifier,
              'attemptId': _attemptIdFactory(),
            },
          });
        }
        await _resumeLogin();
        _scheduleRecovery();
      });

  Future<void> _resumeLogin({bool allowFreshPredecessor = true}) async {
    _requireNetwork();
    final pending = _object(_document['pendingLogin']);
    final session = _session!;
    Map<String, dynamic> response;
    try {
      // Replay the durable attempt using the original predecessor, even after
      // its expiry. A lost response must not cause a second identity transition.
      response = await _transport.request(
        'login',
        bearer: session['sessionToken'] as String,
        body: {'appUserIdentifier': pending['appUserId']},
        headers: {'X-Inappify-Login-Attempt': pending['attemptId'] as String},
      );
    } on GoV2ProtocolException catch (error) {
      if (allowFreshPredecessor && error.code == 'LOGIN_ATTEMPT_NOT_FOUND') {
        await _configureOnline(
          session['appUserId'] as String,
          keepLoginPending: true,
        );
        return _resumeLogin(allowFreshPredecessor: false);
      }
      if (const {
        'APP_USER_ID_INVALID',
        'CUSTOMER_MERGE_FAILED',
      }.contains(error.code)) {
        await _commit(_copy(_document)..remove('pendingLogin'));
      }
      rethrow;
    }
    await _accept(response, pending['appUserId'] as String, transition: true);
  }

  @override
  Future<InappifySdkResult<void>> logout() => _run('logout', _logout);

  Future<void> _logout({bool allowFreshPredecessor = true}) async {
    if (_loginPending) _fail('AUTH', 'LOGIN_PENDING');
    _requireNetwork();
    if (!_logoutPending) {
      await _readySession();
      await _commit({
        ..._copy(_document),
        'pendingLogout': true,
        'pendingLogoutAttempt': {
          'attemptId': '${_attemptIdFactory()}${_attemptIdFactory()}',
        },
      });
    }
    // Upgrade the old boolean-only barrier before issuing any HTTP.
    if (!_document.containsKey('pendingLogoutAttempt')) {
      await _commit({
        ..._copy(_document),
        'pendingLogoutAttempt': {
          'attemptId': '${_attemptIdFactory()}${_attemptIdFactory()}',
        },
      });
    }
    var session = _session!;
    if (_document['sessionInvalid'] == true &&
        session['sessionToken'] == null) {
      await _configureOnline(session['appUserId'] as String);
      session = _session!;
    }
    try {
      final response = await _transport.request(
        'logout',
        bearer: session['sessionToken'] as String,
        retry: false,
        headers: {
          'X-Inappify-Logout-Attempt':
              _object(_document['pendingLogoutAttempt'])['attemptId'] as String,
        },
      );
      await _accept(response, null, transition: true);
      _scheduleRecovery();
    } on GoV2ProtocolException catch (error) {
      if (allowFreshPredecessor && error.code == 'LOGOUT_ATTEMPT_NOT_FOUND') {
        await _configureOnline(session['appUserId'] as String);
        return _logout(allowFreshPredecessor: false);
      }
      if (const {'SESSION_REVOKED', 'SESSION_EXPIRED'}.contains(error.code)) {
        final anonymous = _anonymousIdFactory();
        if (!_isAnonymous(anonymous)) {
          _fail('VALIDATION', 'APP_USER_ID_INVALID');
        }
        await _commit({..._copy(_document), 'anonymousId': anonymous});
        await _configureOnline(anonymous, keepLogoutPending: false);
        _scheduleRecovery();
        return;
      }
      rethrow;
    }
  }

  void _requireNetwork() {
    if (_closed) _fail('CONFIGURATION', 'CLIENT_CLOSED');
    if (!_transport.enabled) _fail('CONFIGURATION', 'V2_DISABLED');
  }

  Future<void> _readySession() async {
    _requireNetwork();
    _requireSession();
    final session = _session!;
    if (_document['sessionInvalid'] == true ||
        !goV2IsoDate(session['sessionExpiresAt'] as String).isAfter(_now())) {
      await _renew(session['appUserId'] as String);
    }
  }

  @override
  Future<InappifySdkResult<CustomerInfo>> getCustomerInfo(
    InappifyRefreshRequest request,
  ) {
    final policy = request.fetchPolicy;
    if (policy == null) {
      return customerInfoWithPolicy(
        request.force
            ? InappifyFetchPolicy.networkOnly
            : InappifyFetchPolicy.cacheFirst,
      );
    }
    if (policy == InappifyCacheFetchPolicy.cacheOnly) {
      return customerInfoWithPolicy(InappifyFetchPolicy.cacheOnly);
    }
    if (policy == InappifyCacheFetchPolicy.fetchCurrent) {
      return customerInfoWithPolicy(InappifyFetchPolicy.networkOnly);
    }
    final cached = snapshot.customerInfo;
    final fetchedAt = _document['infoFetchedAt'];
    final age = fetchedAt is int
        ? _now().millisecondsSinceEpoch - fetchedAt
        : null;
    final fresh = age != null && age >= 0 && age < 300000;
    if (policy == InappifyCacheFetchPolicy.notStaleCachedOrCurrent) {
      return customerInfoWithPolicy(
        cached != null && fresh
            ? InappifyFetchPolicy.cacheOnly
            : InappifyFetchPolicy.networkOnly,
      );
    }
    if (cached != null) {
      if (!fresh && backgroundRecovery) {
        unawaited(customerInfoWithPolicy(InappifyFetchPolicy.networkOnly));
      }
      return customerInfoWithPolicy(InappifyFetchPolicy.cacheOnly);
    }
    return customerInfoWithPolicy(InappifyFetchPolicy.networkOnly);
  }

  @override
  Future<InappifySdkResult<CustomerInfo>> customerInfoWithPolicy(
    InappifyFetchPolicy policy,
  ) async {
    final cached = snapshot.customerInfo;
    if (cached != null &&
        (policy == InappifyFetchPolicy.cacheOnly ||
            policy == InappifyFetchPolicy.cacheFirst)) {
      if (policy == InappifyFetchPolicy.cacheFirst && backgroundRecovery) {
        unawaited(customerInfoWithPolicy(InappifyFetchPolicy.networkOnly));
      }
      return InappifySdkResult.success(data: cached, snapshot: snapshot);
    }
    // CACHE_ONLY never joins a request already fetching over the network.
    if (policy == InappifyFetchPolicy.cacheOnly) {
      return InappifySdkResult.failure(
        _failure(
          const GoV2ProtocolException('CONFIGURATION', 'CACHE_MISS'),
          'customerInfo',
        ),
        snapshot: snapshot,
      );
    }
    final identity = _session?['appUserId'];
    final result = await _share<CustomerInfo>(
      'customer:$identity',
      () => _run<CustomerInfo>('customerInfo', () async {
        await _refreshCustomer();
        return snapshot.customerInfo!;
      }),
    );
    // Policy belongs to each caller, never to the shared network Future.
    if (!result.isSuccess &&
        policy == InappifyFetchPolicy.networkFirst &&
        _session?['appUserId'] == identity &&
        snapshot.customerInfo != null) {
      return InappifySdkResult.success(
        data: snapshot.customerInfo,
        snapshot: snapshot,
      );
    }
    return result;
  }

  Future<void> _refreshCustomer() async {
    final response = await _request('customerInfo');
    await _ensureKey(response);
    final verified = await _verifier.verify(
      response,
      expectedPublicUserId: _session!['appUserId'] as String,
      expectedScope: _objectOrNull(_document['scope']),
      expectedSubject: _document['customerSubject'] as String?,
    );
    _customer(verified.info);
    await _commit({
      ..._copy(_document),
      'info': response,
      'infoFetchedAt': _now().millisecondsSinceEpoch,
    });
  }

  @override
  Future<InappifySdkResult<OfferingsModel>> getOfferings(
    InappifyRefreshRequest request,
  ) => offeringsWithPolicy(
    request.force
        ? InappifyFetchPolicy.networkOnly
        : InappifyFetchPolicy.cacheFirst,
  );

  @override
  Future<InappifySdkResult<OfferingsModel>> offeringsWithPolicy(
    InappifyFetchPolicy policy,
  ) async {
    final cached = snapshot.offerings;
    if (cached != null &&
        (policy == InappifyFetchPolicy.cacheOnly ||
            policy == InappifyFetchPolicy.cacheFirst)) {
      if (policy == InappifyFetchPolicy.cacheFirst && backgroundRecovery) {
        unawaited(offeringsWithPolicy(InappifyFetchPolicy.networkOnly));
      }
      return InappifySdkResult.success(data: cached, snapshot: snapshot);
    }
    if (policy == InappifyFetchPolicy.cacheOnly) {
      return InappifySdkResult.failure(
        _failure(
          const GoV2ProtocolException('CONFIGURATION', 'CACHE_MISS'),
          'offerings',
        ),
        snapshot: snapshot,
      );
    }
    final identity = _session?['appUserId'];
    final result = await _share<OfferingsModel>(
      'offerings:$identity',
      () => _run<OfferingsModel>('offerings', () async {
        await _refreshOfferings();
        return snapshot.offerings!;
      }),
    );
    if (!result.isSuccess &&
        policy == InappifyFetchPolicy.networkFirst &&
        _session?['appUserId'] == identity &&
        snapshot.offerings != null) {
      return InappifySdkResult.success(
        data: snapshot.offerings,
        snapshot: snapshot,
      );
    }
    return result;
  }

  @override
  Future<InappifySdkResult<OfferingsModel>>
  syncAttributesAndOfferingsIfNeeded() =>
      _run('syncAttributesAndOfferingsIfNeeded', () async {
        _requireSession();
        final retryAfterMillis = _targetingSyncLimiter.acquire();
        if (retryAfterMillis != null) {
          final cached = snapshot.offerings;
          if (cached != null) return cached;
          throw GoV2ProtocolException(
            'RATE_LIMIT',
            'RATE_LIMITED_NO_CACHE',
            retryable: true,
            details: {
              'reason': 'RATE_LIMITED_NO_CACHE',
              'retryAfterMillis': retryAfterMillis,
            },
          );
        }
        await _refreshOfferings();
        return snapshot.offerings!;
      });

  Future<void> _refreshOfferings() async {
    await _flushAttributes();
    final response = await _request(
      'offerings',
      body: {
        'appVersion': snapshot.versionName,
        'sdkVersion': goV2SdkVersion,
        'country': snapshot.country,
        'paywallSchemaVersion': 1,
        'paywallRendererVersion': 1,
      },
    );
    if (response['offerings'] != null && response['offerings'] is! List) {
      _fail('DECODING', 'INVALID_OFFERINGS');
    }
    final safe = _copy(response)
      ..remove('rules')
      ..remove('forceVersion')
      ..remove('hasForceUpdate');
    OfferingsModel.fromJson(_copy(safe));
    final next = _copy(_document);
    next['offerings'] = safe;
    await _commit(next);
  }

  @override
  Future<InappifySdkResult<OfferingModel>> getCurrentOffering(
    InappifyCurrentOfferingRequest request,
  ) async {
    final fetched = await getOfferings(
      InappifyRefreshRequest(force: request.forceRefresh),
    );
    if (!fetched.isSuccess) {
      return InappifySdkResult.failure(fetched.failure!, snapshot: snapshot);
    }
    return _run('getCurrentOffering', () async {
      final raw = _objectOrNull(_document['offerings']);
      final placement = _objectOrNull(
        raw?['placements'],
      )?[request.placementIdentifier];
      final current = raw?['currentOffering'];
      final offerings = snapshot.offerings?.offerings ?? [];
      for (final identity in [placement, current]) {
        if (identity is! String) continue;
        for (final offering in offerings) {
          if (offering.identifier == identity) return offering;
        }
      }
      for (final offering in offerings) {
        if (offering.isDefault == true) return offering;
      }
      return null;
    });
  }

  @override
  Future<InappifySdkResult<void>> setTargetingContext(
    InappifyTargetingContextRequest request,
  ) => _run('setTargetingContext', () async {
    _requireSession();
    _validateTargeting(request.country, request.appVersion);
    final next = _copy(_document)..remove('offerings');
    if (request.country != null) {
      next['country'] = _normalizeCountry(request.country!);
    }
    if (request.appVersion != null) next['appVersion'] = request.appVersion;
    await _commit(next);
  });

  @override
  Future<InappifySdkResult<bool>> checkEntitlement(
    InappifyEntitlementCheckRequest request,
  ) async {
    final info = await customerInfoWithPolicy(
      request.forceRefresh
          ? InappifyFetchPolicy.networkOnly
          : InappifyFetchPolicy.cacheFirst,
    );
    if (!info.isSuccess) {
      return InappifySdkResult.failure(info.failure!, snapshot: snapshot);
    }
    return InappifySdkResult.success(
      data:
          snapshot.customerInfo?.entitlements.any(
            (e) => e.identifier == request.identifier && e.isActive == true,
          ) ??
          false,
      snapshot: snapshot,
    );
  }

  @override
  Future<InappifySdkResult<void>> queueAttributes(
    Map<String, String?> values,
  ) => _run('queueAttributes', () async {
    _requireSession();
    for (final entry in values.entries) {
      if (!_validAttribute(entry.key, entry.value)) {
        _fail('VALIDATION', 'ATTRIBUTE_INVALID');
      }
    }
    final next = _copy(_document)..remove('offerings');
    final queue = _objectOrNull(next['attributes']) ?? <String, dynamic>{};
    for (final entry in values.entries) {
      queue[entry.key] = entry.value?.isEmpty == true ? null : entry.value;
    }
    if (queue.length > 1000) _fail('VALIDATION', 'ATTRIBUTE_QUEUE_FULL');
    next['attributes'] = queue;
    await _commit(next);
    if (backgroundRecovery) unawaited(flushAttributes());
  });

  @override
  Future<InappifySdkResult<void>> flushAttributes() =>
      _share('attributes', () => _run('flushAttributes', _flushAttributes));

  Future<void> _flushAttributes() async {
    _requireSession();
    while (true) {
      final queue = _objectOrNull(_document['attributes']);
      if (queue == null || queue.isEmpty) return;
      final batch = Map<String, Object?>.fromEntries(queue.entries.take(50));
      try {
        await _request('attributes', body: {'attributes': batch});
      } on GoV2ProtocolException catch (error) {
        if (error.details['httpStatus'] == 422) {
          final next = _copy(_document);
          final quarantine =
              _objectOrNull(next['quarantine']) ?? <String, dynamic>{};
          quarantine.addAll(batch);
          next['quarantine'] = quarantine;
          final pending = _object(next['attributes']);
          batch.keys.forEach(pending.remove);
          await _commit(next);
        }
        rethrow;
      }
      final next = _copy(_document);
      batch.keys.forEach(_object(next['attributes']).remove);
      await _commit(next);
    }
  }

  @override
  Future<InappifySdkResult<List<Attribute>>> setAttributes(
    InappifyAttributesRequest request,
  ) async {
    final queued = await queueAttributes({
      for (final value in request.attributes) value.key ?? '': value.value,
    });
    if (!queued.isSuccess) {
      return InappifySdkResult.failure(queued.failure!, snapshot: snapshot);
    }
    final flushed = await flushAttributes();
    return flushed.isSuccess
        ? InappifySdkResult.success(
            data: const <Attribute>[],
            snapshot: snapshot,
          )
        : InappifySdkResult.failure(flushed.failure!, snapshot: snapshot);
  }

  @override
  Future<InappifySdkResult<List<Attribute>>> deleteAttributes(
    InappifyDeleteAttributesRequest request,
  ) => setAttributes(
    InappifyAttributesRequest(
      attributes: [for (final key in request.keys) Attribute(key: key)],
    ),
  );

  @override
  Future<InappifySdkResult<List<Attribute>>> syncAttributeValues(
    InappifyAttributesRequest request,
  ) => setAttributes(request);

  @override
  Future<InappifySdkResult<List<Attribute>>> syncAttributes() async {
    final result = await flushAttributes();
    return result.isSuccess
        ? InappifySdkResult.success(
            data: const <Attribute>[],
            snapshot: snapshot,
          )
        : InappifySdkResult.failure(result.failure!, snapshot: snapshot);
  }

  @override
  Future<InappifySdkResult<void>> setReservedAttribute(
    InappifyReservedAttributeRequest request,
  ) async {
    final result = await setAttributes(
      InappifyAttributesRequest(
        attributes: [
          Attribute(
            key: _reservedKeys[request.attribute.index],
            value: request.value,
          ),
        ],
      ),
    );
    return result.isSuccess
        ? InappifySdkResult.success(snapshot: snapshot)
        : InappifySdkResult.failure(result.failure!, snapshot: snapshot);
  }

  @override
  Future<InappifySdkResult<bool>> canSetReservedAttribute(
    InappifyReservedAttributeCapabilityRequest request,
  ) => _run(
    'canSetReservedAttribute',
    () async => _reservedKeys.contains(request.key) && request.key != r'$ip',
  );

  @override
  Future<InappifySdkResult<ValidateDiscountCodeData>> validateDiscountCode(
    InappifyDiscountCodeRequest request,
  ) => _run('validateDiscountCode', () async {
    final response = await _request(
      'validateDiscountCode',
      body: {'code': request.discountCode},
    );
    final data = _object(response['data']);
    if (data['is_valid'] is! bool || data['error_code'] is! int) {
      _fail('DECODING', 'INVALID_DISCOUNT');
    }
    final parsed = ValidateDiscountCodeData.fromJson(data);
    for (final link in parsed.paymentLinks ?? []) {
      if (!_allowedPaymentUrl(link.url)) {
        _fail('DECODING', 'UNTRUSTED_PAYMENT_URL');
      }
    }
    return parsed;
  });

  // Called under _run's serial queue. Renewal is verified and durably committed
  // before one replay; ambiguous checkout/ACK failures never auto-retry.
  Future<Map<String, dynamic>> _commerceRequest(
    String endpoint, {
    Map<String, Object?> body = const {},
  }) async {
    _requireNetwork();
    _requireSession();
    if (!_commerceTransport.enabled) _fail('CONFIGURATION', 'V2_DISABLED');
    if (_session!['storePlatform'] != 1) {
      _fail('CONFIGURATION', 'UNSUPPORTED_IOS_STORE');
    }
    var session = _session!;
    if (_document['sessionInvalid'] == true ||
        !goV2IsoDate(session['sessionExpiresAt'] as String).isAfter(_now())) {
      await _renew(session['appUserId'] as String, retry: false);
    }
    Future<Map<String, dynamic>> send() {
      if (_session!['storePlatform'] != 1) {
        _fail('CONFIGURATION', 'PURCHASE_ROUTE_CHANGED');
      }
      return _commerceTransport.request(
        endpoint,
        body: body,
        bearer: _session!['sessionToken'] as String,
        retry: false,
      );
    }

    try {
      return await send();
    } on GoV2ProtocolException catch (error) {
      if (error.code != 'SESSION_EXPIRED' ||
          error.details['httpStatus'] != 401) {
        rethrow;
      }
      await _renew(_session!['appUserId'] as String, retry: false);
      return send();
    }
  }

  @override
  Future<InappifySdkResult<PurchaseResult>> purchase(
    InappifyPurchaseRequest request,
  ) => _afterPurchase(
    _run('purchase', () async {
      _requireSession();
      if (request.apiKey != null ||
          request.marketKey != null ||
          request.isLostPurchase ||
          request.dynamicPriceToken != null) {
        _fail('VALIDATION', 'PURCHASE_OVERRIDE_NOT_ALLOWED');
      }
      _validateTargeting(request.country, request.appVersion);
      if (request.market != Market.none || _session!['storePlatform'] != 1) {
        _fail('CONFIGURATION', 'UNSUPPORTED_IOS_STORE');
      }
      final purchase = await _purchaseDirectGo(request);
      if (purchase.url != null && !_allowedPaymentUrl(purchase.url)) {
        _fail('DECODING', 'UNTRUSTED_PAYMENT_URL');
      }
      if (!_closed) {
        _events.add(
          InappifyPlatformEvent(
            type: InappifyPlatformEventType.purchaseUpdated,
            snapshot: snapshot,
            data: purchase.toJson(),
          ),
        );
      }
      return purchase;
    }),
  );

  Future<PurchaseResult> _purchaseDirectGo(
    InappifyPurchaseRequest request,
  ) async {
    if (request.country != null ||
        request.appVersion != null ||
        request.discount != 0 ||
        request.discountCode != null) {
      _fail('VALIDATION', 'PURCHASE_OVERRIDE_NOT_ALLOWED');
    }
    if (!_validAttempt(request.idempotencyKey)) {
      _fail('VALIDATION', 'PURCHASE_ATTEMPT_INVALID');
    }
    if ((request.paywallId == null) != (request.paywallRevision == null) ||
        (request.paywallId != null &&
            (request.paywallId! <= 0 || request.paywallRevision! <= 0))) {
      _fail('VALIDATION', 'INVALID_PAYWALL_ATTRIBUTION');
    }
    String? packageIdentifier;
    var found = false;
    for (final offering in snapshot.offerings?.offerings ?? <OfferingModel>[]) {
      if (offering.identifier != request.offeringIdentifier) continue;
      for (final package in offering.packages ?? []) {
        if (package.product?.identifier == request.productIdentifier &&
            (request.packageIdentifier == null ||
                package.identifier == request.packageIdentifier)) {
          packageIdentifier = package.identifier;
          found = true;
          break;
        }
      }
    }
    if (!found) _fail('VALIDATION', 'PRODUCT_NOT_IN_OFFERING');
    final response = await _commerceRequest(
      'purchase',
      body: {
        'productIdentifier': request.productIdentifier,
        'offeringIdentifier': request.offeringIdentifier,
        'isCrypto': request.isCrypto,
        if (request.paywallId != null) 'paywallId': request.paywallId,
        if (request.paywallRevision != null)
          'paywallRevision': request.paywallRevision,
      },
    );
    final data = _objectOrNull(response['data']);
    if (data == null) _fail('DECODING', 'INVALID_PURCHASE');
    final status = switch (data['purchaseStatus']) {
      'DONE' => PurchaseStatus.DONE,
      'NEEDTOPAY' => PurchaseStatus.NEEDTOPAY,
      _ => _fail('DECODING', 'INVALID_PURCHASE_STATUS'),
    };
    final url = data['url'];
    if (url != null && url is! String) _fail('DECODING', 'INVALID_PAYMENT_URL');
    if (status == PurchaseStatus.NEEDTOPAY &&
        (url == null || (url as String).trim().isEmpty)) {
      _fail('DECODING', 'MISSING_PAYMENT_URL');
    }
    return PurchaseResult(
      url: url as String?,
      purchaseStatus: status,
      mobile: InappifyMobilePurchaseData.fromMap({
        'idempotencyKey': request.idempotencyKey,
        'productIdentifier': request.productIdentifier,
        'offeringIdentifier': request.offeringIdentifier,
        'packageIdentifier': packageIdentifier,
        'market': 'none',
        'alreadyProcessed': false,
      }),
    );
  }

  Map<String, dynamic> _directRecords() {
    final saved = _objectOrNull(_document['directDeliveries']);
    return saved?['endpoint'] == _commerceTransport.commerceScope
        ? _copy(_object(saved!['records']))
        : <String, dynamic>{};
  }

  Future<void> _saveDirectRecords(Map<String, dynamic> records) async {
    final terminal = records.keys
        .where(
          (key) =>
              _object(_object(records[key])['delivery'])['status'] ==
              'COMPLETED',
        )
        .toList();
    for (final key in terminal.take(max(0, terminal.length - 128))) {
      records.remove(key);
    }
    if (records.length > 1000) _fail('STORAGE', 'DELIVERY_JOURNAL_FULL');
    await _commit({
      ..._copy(_document),
      'directDeliveries': {
        'endpoint': _commerceTransport.commerceScope,
        'records': records,
      },
    });
  }

  Map<String, dynamic> _directDelivery(Object? value) {
    final delivery = _object(value);
    final id = delivery['deliveryId'];
    final product = delivery['productIdentifier'];
    final status = delivery['status'];
    if (id is! int ||
        id <= 0 ||
        product is! String ||
        product.trim().isEmpty ||
        delivery['source'] != 'direct' ||
        !{'DELIVERY_REQUIRED', 'COMPLETED'}.contains(status) ||
        (delivery['transactionId'] != null &&
            delivery['transactionId'] is! String) ||
        (delivery['alreadyDelivered'] != null &&
            delivery['alreadyDelivered'] is! bool) ||
        (status == 'COMPLETED' && delivery['alreadyDelivered'] == false) ||
        (status == 'DELIVERY_REQUIRED' &&
            delivery['alreadyDelivered'] == true) ||
        (delivery['paymentId'] != null &&
            (delivery['paymentId'] is! int ||
                (delivery['paymentId'] as int) <= 0)) ||
        (delivery['consumeAttempts'] != null &&
            (delivery['consumeAttempts'] is! int ||
                (delivery['consumeAttempts'] as int) < 0))) {
      _fail('DECODING', 'INVALID_DIRECT_DELIVERY');
    }
    return _copy(delivery);
  }

  void _checkDeliveryScope(
    Map<String, dynamic> old,
    Map<String, dynamic> next,
  ) {
    if (old['deliveryId'] != next['deliveryId'] ||
        old['productIdentifier'] != next['productIdentifier'] ||
        old['transactionId'] != next['transactionId']) {
      _fail('DECODING', 'DELIVERY_SCOPE_MISMATCH');
    }
    if (old['status'] == 'COMPLETED' && next['status'] != 'COMPLETED') {
      _fail('DECODING', 'DELIVERY_STATE_REGRESSION');
    }
  }

  PurchaseResult _directPurchase(Map<String, dynamic> delivery) =>
      PurchaseResult.fromJson({
        'mobile': {
          'storePurchaseStatus': delivery['status'],
          'deliveryId': delivery['deliveryId'],
          'alreadyProcessed': delivery['status'] == 'COMPLETED',
          'productIdentifier': delivery['productIdentifier'],
          'market': 'none',
        },
      });

  Future<List<Map<String, dynamic>>> _readDirectPending() async {
    _requireNetwork();
    _requireSession();
    if (_session!['storePlatform'] != 1) {
      _fail('CONFIGURATION', 'UNSUPPORTED_IOS_STORE');
    }
    final found = <int, Map<String, dynamic>>{};
    GoV2ProtocolException? firstError;
    // Persisted host-grant assertions survive a lost ACK and a process restart,
    // even when the server no longer includes that delivery in its pending list.
    for (final raw in _directRecords().values) {
      final record = _object(raw);
      final delivery = _directDelivery(record['delivery']);
      if (record['hostDelivered'] == true &&
          delivery['status'] != 'COMPLETED') {
        try {
          await _confirmDirect(delivery['deliveryId'] as int);
          found[delivery['deliveryId'] as int] = _directDelivery(
            _object(
              _directRecords()[delivery['deliveryId'].toString()],
            )['delivery'],
          );
        } on GoV2ProtocolException catch (error) {
          firstError ??= error;
        }
      }
    }
    final response = await _commerceRequest('consumable-deliveries/pending');
    final list = _object(response['data'])['deliveries'];
    if (list is! List || list.length > 1000) {
      _fail('DECODING', 'INVALID_DIRECT_DELIVERIES');
    }
    final ids = <int>{};
    final records = _directRecords();
    for (final raw in list) {
      final delivery = _directDelivery(raw);
      final id = delivery['deliveryId'] as int;
      if (!ids.add(id)) _fail('DECODING', 'DUPLICATE_DELIVERY_ID');
      final previous = _objectOrNull(records[id.toString()]);
      if (previous != null) {
        _checkDeliveryScope(_directDelivery(previous['delivery']), delivery);
      }
      records[id.toString()] = {
        'delivery': delivery,
        'hostDelivered': previous?['hostDelivered'] == true,
      };
      found[id] = delivery;
    }
    if (list.isNotEmpty) await _saveDirectRecords(records);
    if (firstError != null) throw firstError;
    return found.values.toList();
  }

  Future<PurchaseResult> _confirmDirect(int deliveryId) async {
    _requireNetwork();
    _requireSession();
    if (!_commerceTransport.enabled) _fail('CONFIGURATION', 'V2_DISABLED');
    if (_session!['storePlatform'] != 1) {
      _fail('CONFIGURATION', 'UNSUPPORTED_IOS_STORE');
    }
    if (deliveryId <= 0) _fail('VALIDATION', 'INVALID_DELIVERY_ID');
    var records = _directRecords();
    final record = _objectOrNull(records[deliveryId.toString()]);
    if (record == null) _fail('VALIDATION', 'DELIVERY_NOT_FOUND');
    final expected = _directDelivery(record['delivery']);
    if (expected['status'] == 'COMPLETED') return _directPurchase(expected);
    // Calling confirm is the host's assertion that its idempotent grant is durable.
    record['hostDelivered'] = true;
    await _saveDirectRecords(records);
    final response = await _commerceRequest(
      'consumable-deliveries/$deliveryId/delivered',
    );
    final delivered = _directDelivery(response['data']);
    _checkDeliveryScope(expected, delivered);
    if (delivered['status'] != 'COMPLETED') {
      _fail('DECODING', 'DELIVERY_ACK_MISMATCH');
    }
    // A renewed session may have updated other document fields; keep that commit.
    records = _directRecords();
    records[deliveryId.toString()] = {
      'delivery': delivered,
      'hostDelivered': true,
    };
    await _saveDirectRecords(records);
    return _directPurchase(delivered);
  }

  @override
  Future<InappifySdkResult<InappifyConsumableSyncResult>>
  syncPendingConsumables() => _afterPurchase(
    _run('syncPendingConsumables', () async {
      final deliveries = await _readDirectPending();
      return InappifyConsumableSyncResult(
        discoveredCount: deliveries.length,
        completedCount: deliveries
            .where((d) => d['status'] == 'COMPLETED')
            .length,
        pendingDeliveries: deliveries
            .where((d) => d['status'] == 'DELIVERY_REQUIRED')
            .map(
              (d) => InappifyConsumableDelivery(
                deliveryId: d['deliveryId'] as int,
                productIdentifier: d['productIdentifier'] as String,
                transactionIdentifier: d['transactionId'] as String?,
                source: InappifyDeliverySource.direct,
              ),
            )
            .toList(),
      );
    }),
  );

  @override
  Future<InappifySdkResult<PurchaseResult>> confirmDelivery(int deliveryId) =>
      _afterPurchase(_run('confirmDelivery', () => _confirmDirect(deliveryId)));

  @override
  Future<InappifySdkResult<List<PurchaseResult>>> syncStorePurchases() =>
      _afterPurchase(
        _run(
          'syncStorePurchases',
          () async =>
              (await _readDirectPending()).map(_directPurchase).toList(),
        ),
      );

  @override
  Future<InappifySdkResult<InappifyRestoreResult>> restoreStorePurchases() =>
      _afterPurchase(
        _run('restoreStorePurchases', () async {
          final deliveries = await _readDirectPending();
          return InappifyRestoreResult.fromMap({
            'restoredCount': 0,
            'alreadyProcessedCount': deliveries
                .where((d) => d['status'] == 'COMPLETED')
                .length,
            'failedCount': 0,
          });
        }),
      );

  Future<InappifySdkResult<T>> _afterPurchase<T>(
    Future<InappifySdkResult<T>> operation,
  ) async {
    final result = await operation;
    if (result.isSuccess) {
      await customerInfoWithPolicy(InappifyFetchPolicy.networkOnly);
    }
    return result.isSuccess
        ? InappifySdkResult.success(data: result.data, snapshot: snapshot)
        : InappifySdkResult.failure(result.failure!, snapshot: snapshot);
  }

  Future<InappifySdkResult<void>> _recover() => _share(
    'recover',
    () => _run('recover', () async {
      if (_logoutPending) await _logout();
      if (_loginPending) await _resumeLogin();
      _requireSession();
      await _flushAttributes();
      await _refreshCustomer();
      await _refreshOfferings();
      await _readDirectPending();
    }),
  );

  @override
  Future<InappifySdkResult<void>> setNetworkEnabled(bool enabled) async {
    _transport.enabled = enabled;
    _commerceTransport.enabled = enabled;
    return InappifySdkResult.success(snapshot: snapshot);
  }

  @override
  Future<InappifySdkResult<bool>> isPaymentUrlAllowed(String url) async =>
      InappifySdkResult.success(
        data: _allowedPaymentUrl(url),
        snapshot: snapshot,
      );

  @override
  Future<InappifySdkResult<InappifyConfiguration>> getConfiguration() async =>
      InappifySdkResult.success(
        data: InappifyConfiguration({
          'mobileProtocol': 'goV2',
          'sdkVersion': goV2SdkVersion,
          'verifiedSessionScope': verifiedScope,
          'isLogoutPending': _logoutPending,
          'hasForceUpdate': false,
          'paymentHosts': const ['pay.inappify.com'],
        }),
        snapshot: snapshot,
      );

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _stopTraces();
    await _traceEvents.close();
    await _transport.close();
    await _commerceTransport.close();
    await _events.close();
  }

  void _scheduleRecovery() {
    if (backgroundRecovery && !_closed && !_identityPending) {
      unawaited(_recover());
    }
  }

  void _requireSession({bool allowLogout = false}) {
    if (_loginPending) _fail('AUTH', 'LOGIN_PENDING');
    if (_logoutPending && !allowLogout) _fail('AUTH', 'LOGOUT_PENDING');
    if (_options == null || _session == null) {
      _fail('CONFIGURATION', 'NOT_CONFIGURED');
    }
  }

  Future<void> _commit(Map<String, dynamic> next) async {
    if (_closed) _fail('CONFIGURATION', 'CLIENT_CLOSED');
    final candidate = _copy({...next, 'fingerprint': _fingerprint});
    try {
      await _storage.write(jsonEncode(candidate));
    } catch (_) {
      _fail('STORAGE', 'WRITE_FAILED');
    }
    if (_closed) _fail('CONFIGURATION', 'CLIENT_CLOSED');
    _document = candidate;
    _observeVerifiedTime();
    _revision++;
    SdkLogger.debug('Verified SDK state updated.');
    _emit();
  }

  void _emit() {
    if (!_closed) {
      _events.add(
        InappifyPlatformEvent(
          type: InappifyPlatformEventType.stateChanged,
          snapshot: snapshot,
          data: {'revision': _revision},
        ),
      );
    }
  }

  Future<InappifySdkResult<T>> _run<T>(
    String operation,
    Future<T?> Function() action,
  ) {
    final scheduled = _tail.then((_) async {
      try {
        if (_closed) _fail('CONFIGURATION', 'CLIENT_CLOSED');
        SdkLogger.debug('Starting $operation.');
        final data = await action();
        if (const {'configure', 'login', 'logout', 'purchase'}.contains(operation)) {
          SdkLogger.info('SDK operation $operation returned a successful result.');
        }
        return InappifySdkResult<T>.success(
          data: data,
          snapshot: snapshot,
        );
      } on GoV2ProtocolException catch (error) {
        SdkLogger.error('SDK operation $operation failed.');
        return InappifySdkResult<T>.failure(
          _failure(error, operation),
          snapshot: snapshot,
        );
      } catch (_) {
        return InappifySdkResult<T>.failure(
          InappifyFailure(
            code: InappifyFailureCode.malformedResponse,
            message: 'The Go V2 operation returned invalid data.',
            details: {'operation': operation},
          ),
          snapshot: snapshot,
        );
      }
    });
    _tail = scheduled.then<void>((_) {}, onError: (_) {});
    return scheduled;
  }

  Future<InappifySdkResult<T>> _share<T>(
    String key,
    Future<InappifySdkResult<T>> Function() action,
  ) {
    final existing = _shared[key];
    if (existing != null) {
      return existing.then((value) => value as InappifySdkResult<T>);
    }
    final future = action();
    _shared[key] = future;
    unawaited(
      future.then(
        (_) {
          if (identical(_shared[key], future)) _shared.remove(key);
        },
        onError: (Object _) {
          if (identical(_shared[key], future)) _shared.remove(key);
        },
      ),
    );
    return future;
  }

  InappifyFailure _failure(GoV2ProtocolException error, String operation) =>
      InappifyFailure(
        code: switch (error.category) {
          'STORAGE' => InappifyFailureCode.storageUnavailable,
          'CONFIGURATION' || 'VALIDATION' =>
            error.code == 'NOT_CONFIGURED'
                ? InappifyFailureCode.notConfigured
                : InappifyFailureCode.invalidConfiguration,
          'AUTH' => InappifyFailureCode.unauthorized,
          'SIGNATURE' || 'DECODING' => InappifyFailureCode.malformedResponse,
          'NETWORK' => InappifyFailureCode.network,
          'TIMEOUT' => InappifyFailureCode.timeout,
          _ => InappifyFailureCode.unknown,
        },
        message: 'Inappify Go V2 ${error.category} failure (${error.code}).',
        isRetryable: error.retryable,
        details: {
          ...error.details,
          'operation': operation,
          'category': error.category,
          'serverCode': error.code,
          if (error.category == 'SIGNATURE' &&
              {
                'configure',
                'login',
                'logout',
                'customerInfo',
              }.contains(operation))
            'httpStatus': 200,
          if ({'configure', 'login', 'logout'}.contains(operation))
            'outcomeMayHaveCommitted': true,
          if ({'purchase', 'confirmDelivery'}.contains(operation))
            'outcomeMayHaveCommitted':
                error.details['outcomeMayHaveCommitted'] == true ||
                {
                  'NETWORK',
                  'TIMEOUT',
                  'DECODING',
                  'STORAGE',
                }.contains(error.category) ||
                (error.details['httpStatus'] is int &&
                    (error.details['httpStatus'] as int) >= 500),
        },
      );

  CustomerInfo _customer(Map<String, dynamic> value) {
    final copy = _copy(value)..remove('attributes');
    final entitlements = copy['entitlements'];
    if (entitlements is List) {
      for (final item in entitlements) {
        final entitlement = _object(item);
        final expiry = entitlement['expiration_date'];
        if (expiry is String &&
            expiry.isNotEmpty &&
            !goV2IsoDate(expiry).isAfter(_trustedClock.now())) {
          entitlement['is_active'] = false;
        }
      }
    }
    copy['entitlementEvaluationTimeMillis'] = _trustedClock
        .now()
        .millisecondsSinceEpoch;
    return CustomerInfo.fromJson(copy);
  }

  // Called only after the signed session/info has been verified and committed.
  // Across process restart the verified signed requestDate restores the floor;
  // an unsigned persisted wall-clock value can never establish trusted time.
  void _observeVerifiedTime() {
    final envelope = _objectOrNull(_document['info']) ?? _session;
    final value = _objectOrNull(envelope?['customerInfo'])?['requestDate'];
    if (value is String) _trustedClock.observe(goV2IsoDate(value));
  }

  static bool _allowedPaymentUrl(String? value) {
    final url = value == null ? null : Uri.tryParse(value);
    return url != null &&
        url.scheme == 'https' &&
        url.host == 'pay.inappify.com' &&
        url.userInfo.isEmpty &&
        (!url.hasPort || url.port == 443);
  }

  static void _validateTargeting(String? country, String? version) {
    if (country != null && !RegExp(r'^[A-Za-z]{2}$').hasMatch(country.trim())) {
      _fail('VALIDATION', 'INVALID_COUNTRY');
    }
    if (version != null && (version.trim().isEmpty || version.length > 50)) {
      _fail('VALIDATION', 'INVALID_VERSION');
    }
  }

  static const _reservedKeys = [
    r'$email',
    r'$apnsTokens',
    r'$displayName',
    r'$ip',
    r'$fcmTokens',
    r'$idfa',
    r'$idfv',
    r'$ip',
    r'$phoneNumber',
    r'$campaign',
    r'$keyword',
  ];

  static bool _validAttribute(String key, String? value) =>
      ((_reservedKeys.contains(key) && key != r'$ip') ||
          RegExp(r'^[A-Za-z][A-Za-z0-9_-]{0,39}$').hasMatch(key)) &&
      (value == null || value.runes.length <= 500);

  static bool _isAnonymous(String identity) =>
      RegExp(
        r'^\$INAAnonymousID:[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-4[0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$',
      ).hasMatch(identity) ||
      RegExp(r'^\$InaAnonymousId_[0-9A-HJKMNP-TV-Z]{26}$').hasMatch(identity);

  static bool _validIdentity(String identity) {
    if (_isAnonymous(identity)) return true;
    final lower = identity.toLowerCase();
    return identity.isNotEmpty &&
        identity.trim() == identity &&
        identity.runes.length <= 100 &&
        !identity.runes.any(
          (rune) =>
              rune <= 31 ||
              (rune >= 127 && rune <= 159) ||
              (rune >= 0xd800 && rune <= 0xdfff),
        ) &&
        !lower.startsWith(r'$inaanonymousid:') &&
        !lower.startsWith(r'$inaanonymousid_');
  }

  static String _normalizeCountry(String value) => value.trim().toUpperCase();
  static bool _validAttempt(Object? value) =>
      value is String && RegExp(r'^[A-Za-z0-9_.:-]{1,128}$').hasMatch(value);
  static String _newAttemptId() => _newAnonymousId().split(':').last;

  static String _newAnonymousId() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    bytes[6] = (bytes[6] & 15) | 64;
    bytes[8] = (bytes[8] & 63) | 128;
    final raw = bytes.map((v) => v.toRadixString(16).padLeft(2, '0')).join();
    return '\$INAAnonymousID:${raw.substring(0, 8)}-${raw.substring(8, 12)}-${raw.substring(12, 16)}-${raw.substring(16, 20)}-${raw.substring(20)}';
  }

  static String _hash(String value) =>
      sha256.convert(utf8.encode(value)).toString();
  static Map<String, dynamic> _copy(Map<String, dynamic> value) =>
      jsonDecode(jsonEncode(value)) as Map<String, dynamic>;
  static Map<String, dynamic> _object(Object? value) =>
      value is Map<String, dynamic>
      ? value
      : throw const FormatException('Expected an object.');
  static Map<String, dynamic>? _objectOrNull(Object? value) =>
      value is Map<String, dynamic> ? value : null;
  static Never _fail(String category, String code) =>
      throw GoV2ProtocolException(category, code);
}

/// Per-client admission starts survive identity changes, including failures.
class _TargetingSyncRateLimiter {
  _TargetingSyncRateLimiter(int Function()? monotonicMilliseconds) {
    final stopwatch = Stopwatch()..start();
    _elapsed = monotonicMilliseconds ?? (() => stopwatch.elapsedMilliseconds);
  }

  late final int Function() _elapsed;
  final List<int> _starts = [];
  int? _lastNow;

  int? acquire() {
    final elapsed = _elapsed();
    final now = max(_lastNow ?? elapsed, elapsed);
    _lastNow = now;
    _starts.removeWhere((start) => now - start >= 60000);
    if (_starts.length < 5) {
      _starts.add(now);
      return null;
    }
    return 60000 - (now - _starts.first);
  }
}

/// Wall time cannot move behind signed server time or observed monotonic time.
class _TrustedGoV2Clock {
  _TrustedGoV2Clock(this.wallClock, int Function()? monotonicMilliseconds) {
    final stopwatch = Stopwatch()..start();
    _elapsed = monotonicMilliseconds ?? (() => stopwatch.elapsedMilliseconds);
    _anchor = _elapsed();
  }
  final DateTime Function() wallClock;
  late final int Function() _elapsed;
  int _floor = 0;
  late int _anchor;

  DateTime now() {
    final elapsed = _elapsed();
    _floor = max(
      wallClock().millisecondsSinceEpoch,
      _floor + max(0, elapsed - _anchor),
    );
    _anchor = elapsed;
    return DateTime.fromMillisecondsSinceEpoch(_floor, isUtc: true);
  }

  void observe(DateTime signedTime) {
    _floor = max(
      now().millisecondsSinceEpoch,
      signedTime.millisecondsSinceEpoch,
    );
    _anchor = _elapsed();
  }
}
