import 'dart:async';

import 'package:inappify_sdk/inappify_sdk_platform_interface.dart'
    show InappifySdkPlatform;
import 'package:inappify_sdk/models/attribute.dart';
import 'package:inappify_sdk/models/authentication_result.dart';
import 'package:inappify_sdk/models/captcha_challenge.dart';
import 'package:inappify_sdk/models/checkout_result.dart';
import 'package:inappify_sdk/models/customer_info.dart';
import 'package:inappify_sdk/models/enums/purchase_status.dart';
import 'package:inappify_sdk/models/inappify_configuration.dart';
import 'package:inappify_sdk/models/mobile_v2.dart';
import 'package:inappify_sdk/models/offering_model.dart';
import 'package:inappify_sdk/models/offerings_model.dart';
import 'package:inappify_sdk/models/otp_challenge.dart';
import 'package:inappify_sdk/models/purchase_result.dart';
import 'package:inappify_sdk/models/validate_discount_code_data.dart';
import 'package:inappify_sdk/request_cancellation.dart';
import 'package:inappify_sdk/session_state.dart';
import 'package:inappify_sdk/src/platform/contracts/backend_capabilities.dart';
import 'package:inappify_sdk/src/platform/contracts/platform_event.dart';
import 'package:inappify_sdk/src/platform/contracts/sdk_failure.dart';
import 'package:inappify_sdk/src/platform/contracts/sdk_requests.dart';
import 'package:inappify_sdk/src/platform/contracts/sdk_result.dart';
import 'package:inappify_sdk/src/platform/contracts/sdk_snapshot.dart';
import 'package:inappify_sdk/src/platform/web/web_inappify_bridge.dart';
import 'package:inappify_sdk/src/platform/web/web_payload_codec.dart';

/// Complete browser adapter for `@inappifylabs/web-sdk`.
///
/// This adapter owns exactly one JavaScript session. Tokens, IndexedDB data,
/// Web Locks, and refresh rotation remain private to the JavaScript SDK. Dart
/// receives only compatibility models and complete snapshots. The browser
/// bridge is injected so tests never need to expose secrets or depend on a
/// real payment service.
class WebInappifyPlatform extends InappifySdkPlatform {
  /// Creates a browser platform adapter backed by [bridge].
  WebInappifyPlatform({required InappifyWebBridge bridge}) : _bridge = bridge {
    _bridgeSubscription = _bridge.events.listen(
      _handleBridgeEvent,
      onError: _ignoreBridgeEventError,
    );
  }

  static const Set<InappifyOperation> _supportedOperations =
      <InappifyOperation>{
        InappifyOperation.configure,
        InappifyOperation.logout,
        InappifyOperation.purchase,
        InappifyOperation.validateDiscountCode,
        InappifyOperation.getCustomerInfo,
        InappifyOperation.getConfiguration,
        InappifyOperation.getOfferings,
        InappifyOperation.setAttributes,
        InappifyOperation.setReservedAttribute,
        InappifyOperation.syncAttributes,
        InappifyOperation.exchangeIdentityTicket,
        InappifyOperation.requestOtp,
        InappifyOperation.createOtpCaptcha,
        InappifyOperation.verifyOtp,
        InappifyOperation.setTargetingContext,
        InappifyOperation.getCurrentOffering,
        InappifyOperation.checkEntitlement,
        InappifyOperation.deleteAttributes,
        InappifyOperation.syncAttributeValues,
        InappifyOperation.canSetReservedAttribute,
        InappifyOperation.handlePaymentReturn,
        InappifyOperation.getPendingCheckoutId,
        InappifyOperation.createCheckout,
        InappifyOperation.getCheckoutStatus,
      };

  static const String _defaultBaseUrl = 'https://api.inappify.com/api/web/v1';

  final InappifyWebBridge _bridge;
  final StreamController<InappifyPlatformEvent> _eventController =
      StreamController<InappifyPlatformEvent>.broadcast(sync: true);
  late final StreamSubscription<InappifyWebBridgeEvent> _bridgeSubscription;

  bool _configured = false;
  String _apiKey = '';
  String _country = 'IR';
  String _appVersion = '';
  int? _appId;
  int _forceVersion = 1;
  CustomerInfo? _customerInfo;
  OfferingsModel? _offerings;
  bool _failedToLoadCustomerInfo = false;
  bool _failedToLoadOfferings = false;
  InappifySessionState _sessionState = InappifySessionState.unconfigured;
  InappifySessionPersistenceMode _persistenceMode =
      InappifySessionPersistenceMode.unknown;
  Map<String, Object?>? _configuredOptions;
  int _sessionStateRevision = 0;
  int _identityRevision = 0;
  int _customerReadRevision = 0;
  int _customerMirrorRevision = 0;
  int _snapshotRevision = 0;

  bool get _supportsTargetingSync =>
      _supportsSafeSessionContract(_bridge.sdkVersion) &&
      (_bridge is! InappifyWebProviderCapabilities ||
          (_bridge as InappifyWebProviderCapabilities).supportsMethod(
            'syncAttributesAndOfferingsIfNeeded',
          ));

  @override
  Stream<InappifyPlatformEvent> get events => _eventController.stream;

  @override
  Future<InappifyBackendCapabilities> getCapabilities() async {
    if (!_bridge.isAvailable ||
        !_supportsSafeSessionContract(_bridge.sdkVersion)) {
      return InappifyBackendCapabilities.unavailable(
        backendKind: InappifyBackendKind.webJavaScript,
      );
    }
    return InappifyBackendCapabilities(
      backendKind: InappifyBackendKind.webJavaScript,
      protocolVersion: InappifyBackendCapabilities.currentProtocolVersion,
      ownsSession: true,
      supportedOperations: <InappifyOperation>{
        ..._supportedOperations,
        if (_supportsTargetingSync)
          InappifyOperation.syncAttributesAndOfferingsIfNeeded,
      },
      sdkVersion: _bridge.sdkVersion,
    );
  }

  @override
  Future<InappifySdkResult<void>> configure(
    InappifyConfigureRequest request,
  ) async {
    final apiKey = request.apiKey.trim();
    final country = request.country?.trim().toUpperCase();
    final appVersion = request.appVersion?.trim();
    if (apiKey.isEmpty) {
      return _invalid<void>('configure', 'A public Web App Key is required.');
    }
    final customerIdentifier = request.appUserIdentifier;
    if (customerIdentifier != null &&
        customerIdentifier.isNotEmpty &&
        !customerIdentifier.startsWith(r'$InaAnonymousId_')) {
      return _invalid<void>(
        'configure',
        'Authenticated Web sessions require an Identity Ticket or OTP.',
      );
    }

    final options = <String, Object?>{
      'apiKey': apiKey,
      'baseUrl': _defaultBaseUrl,
      if (country?.isNotEmpty ?? false) 'country': country,
      if (appVersion?.isNotEmpty ?? false) 'appVersion': appVersion,
    };

    if (_configured &&
        _sameConfiguration(_configuredOptions, options) &&
        (_sessionState == InappifySessionState.anonymous ||
            _sessionState == InappifySessionState.authenticated)) {
      _readSessionMetadataBestEffort();
      return InappifySdkResult<void>.success(snapshot: _snapshot);
    }

    return _run<void>(
      'configure',
      requiresConfiguration: false,
      action: () async {
        final replacesConfiguredApp = _configured && _apiKey != apiKey;
        await _bridge.configure(options);
        _identityRevision += 1;
        _customerInfo = null;
        _offerings = null;
        _appId = null;
        _forceVersion = 1;
        _apiKey = apiKey;
        _country = country?.isNotEmpty ?? false ? country! : 'IR';
        _appVersion = appVersion ?? '';
        _configured = true;
        _configuredOptions = Map<String, Object?>.unmodifiable(options);
        if (replacesConfiguredApp) _bridge.clearPendingCheckout();
        _readSessionMetadataBestEffort();
        _readConfigurationMetadataBestEffort();
        await _refreshCachedStateBestEffort(includeOfferings: true);
      },
      mutationMayHaveCommitted: true,
    );
  }

  @override
  Future<InappifySdkResult<void>> login(InappifyLoginRequest request) async {
    return InappifySdkResult<void>.failure(
      InappifyFailure.unsupported('login'),
      snapshot: _snapshot,
    );
  }

  @override
  Future<InappifySdkResult<InappifyAuthenticationResult>>
  exchangeIdentityTicket(InappifyIdentityTicketRequest request) async {
    final cancelled = _preCancelled<InappifyAuthenticationResult>(
      'exchangeIdentityTicket',
      request.cancellation,
    );
    if (cancelled != null) return cancelled;
    return _run<InappifyAuthenticationResult>(
      'exchangeIdentityTicket',
      action: () async {
        final previousCustomer = _customerInfo;
        final previousOfferings = _offerings;
        final raw = await _callSessionMutation(
          method: 'exchangeIdentityTicket',
          positionalArguments: <Object?>[
            request.identityTicket,
            if (request.cancellation != null) const <String, Object?>{},
          ],
          cancellation: request.cancellation,
          injectAbortSignal: request.cancellation != null,
          previousCustomer: previousCustomer,
          previousOfferings: previousOfferings,
        );
        _clearUnchangedSessionMirrors(previousCustomer, previousOfferings);
        final result = InappifyWebPayloadCodec.authentication(raw);
        _bridge.clearPendingCheckout();
        await _refreshCachedStateBestEffort(includeOfferings: true);
        return result;
      },
      cancellation: request.cancellation,
      mutationMayHaveCommitted: true,
    );
  }

  @override
  Future<InappifySdkResult<InappifyOtpChallenge>> requestOtp(
    InappifyOtpRequest request,
  ) async {
    final cancelled = _preCancelled<InappifyOtpChallenge>(
      'requestOtp',
      request.cancellation,
    );
    if (cancelled != null) return cancelled;
    return _run<InappifyOtpChallenge>(
      'requestOtp',
      action: () async {
        final raw = await _bridge.call(
          'requestOtp',
          positionalArguments: <Object?>[
            <String, Object?>{
              'phone': request.phone,
              if (request.captchaKey != null) 'captchaKey': request.captchaKey,
              if (request.captchaAnswer != null)
                'captchaAnswer': request.captchaAnswer,
            },
            if (request.cancellation != null) const <String, Object?>{},
          ],
          cancellation: request.cancellation,
          injectAbortSignal: request.cancellation != null,
        );
        return InappifyWebPayloadCodec.otpChallenge(raw);
      },
      cancellation: request.cancellation,
      mutationMayHaveCommitted: true,
    );
  }

  @override
  Future<InappifySdkResult<InappifyCaptchaChallenge>> createOtpCaptcha(
    InappifyNetworkRequest request,
  ) async {
    final cancelled = _preCancelled<InappifyCaptchaChallenge>(
      'createOtpCaptcha',
      request.cancellation,
    );
    if (cancelled != null) return cancelled;
    return _run<InappifyCaptchaChallenge>(
      'createOtpCaptcha',
      action: () async {
        final raw = await _bridge.call(
          'createOtpCaptcha',
          positionalArguments: request.cancellation == null
              ? const <Object?>[]
              : const <Object?>[<String, Object?>{}],
          cancellation: request.cancellation,
          injectAbortSignal: request.cancellation != null,
        );
        return InappifyWebPayloadCodec.captchaChallenge(raw);
      },
      cancellation: request.cancellation,
      mutationMayHaveCommitted: true,
    );
  }

  @override
  Future<InappifySdkResult<InappifyAuthenticationResult>> verifyOtp(
    InappifyOtpVerificationRequest request,
  ) async {
    final cancelled = _preCancelled<InappifyAuthenticationResult>(
      'verifyOtp',
      request.cancellation,
    );
    if (cancelled != null) return cancelled;
    return _run<InappifyAuthenticationResult>(
      'verifyOtp',
      action: () async {
        final previousCustomer = _customerInfo;
        final previousOfferings = _offerings;
        final raw = await _callSessionMutation(
          method: 'verifyOtp',
          positionalArguments: <Object?>[
            request.challengeId,
            request.code,
            if (request.cancellation != null) const <String, Object?>{},
          ],
          cancellation: request.cancellation,
          injectAbortSignal: request.cancellation != null,
          previousCustomer: previousCustomer,
          previousOfferings: previousOfferings,
        );
        _clearUnchangedSessionMirrors(previousCustomer, previousOfferings);
        final result = InappifyWebPayloadCodec.authentication(raw);
        _bridge.clearPendingCheckout();
        await _refreshCachedStateBestEffort(includeOfferings: true);
        return result;
      },
      cancellation: request.cancellation,
      mutationMayHaveCommitted: true,
    );
  }

  @override
  Future<InappifySdkResult<void>> logout() {
    return logoutWithRequest(const InappifyNetworkRequest());
  }

  @override
  Future<InappifySdkResult<void>> logoutWithRequest(
    InappifyNetworkRequest request,
  ) async {
    final cancelled = _preCancelled<void>('logout', request.cancellation);
    if (cancelled != null) return cancelled;
    return _run<void>(
      'logout',
      action: () async {
        final previousCustomer = _customerInfo;
        final previousOfferings = _offerings;
        await _callSessionMutation(
          method: 'logout',
          positionalArguments: request.cancellation == null
              ? const <Object?>[]
              : const <Object?>[<String, Object?>{}],
          cancellation: request.cancellation,
          injectAbortSignal: request.cancellation != null,
          previousCustomer: previousCustomer,
          previousOfferings: previousOfferings,
        );
        _clearUnchangedSessionMirrors(previousCustomer, previousOfferings);
        _bridge.clearPendingCheckout();
        await _refreshCachedStateBestEffort(includeOfferings: true);
      },
      cancellation: request.cancellation,
      mutationMayHaveCommitted: true,
    );
  }

  @override
  Future<InappifySdkResult<PurchaseResult>> purchase(
    InappifyPurchaseRequest request,
  ) async {
    final cancelled = _preCancelled<PurchaseResult>(
      'purchase',
      request.cancellation,
    );
    if (cancelled != null) return cancelled;
    final packageIdentifier = _resolvePackageIdentifier(request);
    if (packageIdentifier == null) {
      return _invalid<PurchaseResult>(
        'purchase',
        'A packageIdentifier could not be inferred unambiguously.',
      );
    }
    if (_hasUnsupportedNativePurchaseOptions(request)) {
      return _invalid<PurchaseResult>(
        'purchase',
        'Native-store purchase options are not supported by Web checkout.',
      );
    }
    return _run<PurchaseResult>(
      'purchase',
      action: () async {
        final raw = await _bridge.call(
          'purchase',
          positionalArguments: <Object?>[
            _checkoutParameters(request, packageIdentifier),
            const <String, Object?>{'redirect': false},
          ],
          cancellation: request.cancellation,
          injectAbortSignal: request.cancellation != null,
        );
        final checkout = InappifyWebPayloadCodec.checkout(raw);
        final normalizedStatus = checkout.checkout.status.toLowerCase();
        if (normalizedStatus == 'cancelled' || normalizedStatus == 'canceled') {
          _bridge.clearPendingCheckout();
          throw _WebSemanticException(
            code: InappifyFailureCode.purchaseCancelled,
            status: checkout.checkout.status,
          );
        }
        if (normalizedStatus == 'failed' || normalizedStatus == 'expired') {
          _bridge.clearPendingCheckout();
          throw _WebSemanticException(
            code: InappifyFailureCode.unknown,
            status: checkout.checkout.status,
          );
        }
        if (checkout.isPaid) {
          _bridge.clearPendingCheckout();
          _readCustomerPropertyBestEffort();
        } else {
          _bridge.persistPendingCheckout(checkout.checkout.id);
        }
        return PurchaseResult(
          url: checkout.nextAction.url,
          purchaseStatus: checkout.isPaid
              ? PurchaseStatus.DONE
              : PurchaseStatus.NEEDTOPAY,
          checkoutId: checkout.checkout.id,
          checkoutStatus: checkout.checkout.status,
          nextActionType: checkout.nextAction.type,
        );
      },
      cancellation: request.cancellation,
      mutationMayHaveCommitted: true,
    );
  }

  @override
  Future<InappifySdkResult<InappifyCheckoutResult>> createCheckout(
    InappifyPurchaseRequest request,
  ) async {
    final cancelled = _preCancelled<InappifyCheckoutResult>(
      'createCheckout',
      request.cancellation,
    );
    if (cancelled != null) return cancelled;
    final packageIdentifier = _resolvePackageIdentifier(request);
    if (packageIdentifier == null) {
      return _invalid<InappifyCheckoutResult>(
        'createCheckout',
        'A packageIdentifier could not be inferred unambiguously.',
      );
    }
    if (_hasUnsupportedNativePurchaseOptions(request)) {
      return _invalid<InappifyCheckoutResult>(
        'createCheckout',
        'Native-store purchase options are not supported by Web checkout.',
      );
    }
    return _run<InappifyCheckoutResult>(
      'createCheckout',
      action: () async {
        final raw = await _bridge.call(
          'createCheckout',
          positionalArguments: <Object?>[
            _checkoutParameters(request, packageIdentifier),
            if (request.cancellation != null) const <String, Object?>{},
          ],
          cancellation: request.cancellation,
          injectAbortSignal: request.cancellation != null,
        );
        final checkout = InappifyWebPayloadCodec.checkout(raw);
        _recordCheckoutState(checkout);
        return checkout;
      },
      cancellation: request.cancellation,
      mutationMayHaveCommitted: true,
    );
  }

  @override
  Future<InappifySdkResult<InappifyCheckoutResult>> getCheckoutStatus(
    InappifyCheckoutStatusRequest request,
  ) async {
    final cancelled = _preCancelled<InappifyCheckoutResult>(
      'getCheckoutStatus',
      request.cancellation,
    );
    if (cancelled != null) return cancelled;
    if (request.checkoutId.isEmpty) {
      return _invalid<InappifyCheckoutResult>(
        'getCheckoutStatus',
        'A checkoutId is required.',
      );
    }
    return _run<InappifyCheckoutResult>(
      'getCheckoutStatus',
      action: () async {
        final raw = await _bridge.call(
          'getCheckoutStatus',
          positionalArguments: <Object?>[
            request.checkoutId,
            if (request.cancellation != null) const <String, Object?>{},
          ],
          cancellation: request.cancellation,
          injectAbortSignal: request.cancellation != null,
        );
        final checkout = InappifyWebPayloadCodec.checkout(raw);
        _recordCheckoutState(checkout);
        return checkout;
      },
      cancellation: request.cancellation,
    );
  }

  @override
  Future<InappifySdkResult<ValidateDiscountCodeData>> validateDiscountCode(
    InappifyDiscountCodeRequest request,
  ) async {
    final cancelled = _preCancelled<ValidateDiscountCodeData>(
      'validateDiscountCode',
      request.cancellation,
    );
    if (cancelled != null) return cancelled;
    return _run<ValidateDiscountCodeData>(
      'validateDiscountCode',
      action: () async {
        final requestedIdentifier = request.offeringIdentifier;
        String? offeringIdentifier = requestedIdentifier;
        if (offeringIdentifier == null) {
          final currentRaw = await _bridge.call(
            'getCurrentOffering',
            positionalArguments: request.cancellation == null
                ? const <Object?>[]
                : const <Object?>[<String, Object?>{}],
            cancellation: request.cancellation,
            injectAbortSignal: request.cancellation != null,
          );
          final current = currentRaw == null
              ? null
              : InappifyWebPayloadCodec.offering(currentRaw);
          offeringIdentifier = current?.identifier;
        }
        if (offeringIdentifier == null || offeringIdentifier.trim().isEmpty) {
          throw const _WebSemanticException(
            code: InappifyFailureCode.invalidConfiguration,
          );
        }
        final raw = await _bridge.call(
          'validateDiscountCode',
          positionalArguments: <Object?>[
            request.discountCode,
            offeringIdentifier,
            if (request.cancellation != null) const <String, Object?>{},
          ],
          cancellation: request.cancellation,
          injectAbortSignal: request.cancellation != null,
        );
        final result = InappifyWebPayloadCodec.discountValidation(raw);
        if (requestedIdentifier != null &&
            result.offering != null &&
            result.offering!.identifier != requestedIdentifier) {
          throw const FormatException(
            'Web discount validation returned a different offering.',
          );
        }
        return result;
      },
      cancellation: request.cancellation,
    );
  }

  @override
  Future<InappifySdkResult<CustomerInfo>> getCustomerInfo(
    InappifyRefreshRequest request,
  ) async {
    final cancellation = request.cancellation;
    if (cancellation?.isCancelled ?? false) {
      return _cancelled<CustomerInfo>('getCustomerInfo');
    }
    return _run<CustomerInfo>(
      'getCustomerInfo',
      action: () async {
        final identityRevision = _identityRevision;
        final mirrorRevision = _customerMirrorRevision;
        final policy =
            request.fetchPolicy ??
            (request.force
                ? InappifyCacheFetchPolicy.fetchCurrent
                : InappifyCacheFetchPolicy.cachedOrFetched);
        final readRevision = policy == InappifyCacheFetchPolicy.cacheOnly
            ? _customerReadRevision
            : ++_customerReadRevision;
        try {
          final raw = await _bridge.call(
            'getCustomerInfo',
            positionalArguments: <Object?>[
              _customerFetchPolicy(policy),
              const <String, Object?>{},
            ],
            cancellation: cancellation,
            injectAbortSignal: cancellation != null,
          );
          final customer = InappifyWebPayloadCodec.customerInfo(raw);
          if (identityRevision != _identityRevision ||
              (policy != InappifyCacheFetchPolicy.cacheOnly &&
                  readRevision != _customerReadRevision)) {
            throw const InappifyWebBridgeException(
              code: 'CUSTOMER_INFO_REQUEST_SUPERSEDED',
              kind: 'configuration',
            );
          }
          // An event may have published a newer background result before the
          // cached Promise crossed the bridge. Keep that newer mirror.
          if (mirrorRevision == _customerMirrorRevision) {
            _customerInfo = customer;
            _customerMirrorRevision += 1;
          }
          _failedToLoadCustomerInfo = false;
          return customer;
        } catch (_) {
          if (identityRevision == _identityRevision &&
              readRevision == _customerReadRevision) {
            _failedToLoadCustomerInfo = true;
          }
          rethrow;
        }
      },
      cancellation: cancellation,
    );
  }

  @override
  Future<InappifySdkResult<OfferingsModel>>
  syncAttributesAndOfferingsIfNeeded() {
    if (!_supportsTargetingSync) {
      return Future.value(
        InappifySdkResult<OfferingsModel>.failure(
          InappifyFailure.unsupported('syncAttributesAndOfferingsIfNeeded'),
          snapshot: _snapshot,
        ),
      );
    }
    return _run<OfferingsModel>(
      'syncAttributesAndOfferingsIfNeeded',
      action: () async {
        final identityRevision = _identityRevision;
        try {
          final raw = await _bridge.call('syncAttributesAndOfferingsIfNeeded');
          if (identityRevision != _identityRevision) {
            throw const InappifyWebBridgeException(
              code: 'CUSTOMER_INFO_REQUEST_SUPERSEDED',
              kind: 'configuration',
            );
          }
          final offerings = InappifyWebPayloadCodec.offerings(raw);
          _commitOfferings(offerings);
          _failedToLoadOfferings = false;
          return offerings;
        } catch (_) {
          if (identityRevision == _identityRevision) {
            _failedToLoadOfferings = true;
          }
          rethrow;
        } finally {
          // This also keeps a successful customer refresh when the following
          // offerings read fails. Never fetch again or fall back to success.
          if (identityRevision == _identityRevision) {
            _readCustomerPropertyBestEffort();
          }
        }
      },
    );
  }

  @override
  Future<InappifySdkResult<InappifyConfiguration>> getConfiguration() {
    return _run<InappifyConfiguration>(
      'getConfiguration',
      action: () async {
        final raw = _bridge.readProperty('configuration');
        final map = InappifyWebPayloadCodec.requiredMap(
          raw,
          field: 'configuration',
        );
        _commitConfigurationMetadata(map);
        return InappifyConfiguration.fromMap(_sanitizeConfiguration(map));
      },
    );
  }

  @override
  Future<InappifySdkResult<OfferingsModel>> getOfferings(
    InappifyRefreshRequest request,
  ) async {
    final cancellation = request.cancellation;
    if (cancellation?.isCancelled ?? false) {
      return _cancelled<OfferingsModel>('getOfferings');
    }
    return _run<OfferingsModel>(
      'getOfferings',
      action: () async {
        try {
          final raw = await _bridge.call(
            'getOfferings',
            positionalArguments: <Object?>[
              <String, Object?>{'forceRefresh': request.force},
            ],
            cancellation: cancellation,
            injectAbortSignal: cancellation != null,
          );
          final offerings = InappifyWebPayloadCodec.offerings(raw);
          _commitOfferings(offerings);
          _failedToLoadOfferings = false;
          return offerings;
        } catch (_) {
          _failedToLoadOfferings = true;
          rethrow;
        }
      },
      cancellation: cancellation,
    );
  }

  @override
  Future<InappifySdkResult<void>> setTargetingContext(
    InappifyTargetingContextRequest request,
  ) {
    final country = request.country?.trim().toUpperCase();
    final appVersion = request.appVersion?.trim();
    return _run<void>(
      'setTargetingContext',
      action: () async {
        await _bridge.call(
          'setTargetingContext',
          positionalArguments: <Object?>[
            <String, Object?>{
              if (country != null) 'country': country,
              if (appVersion != null) 'appVersion': appVersion,
            },
          ],
        );
        if (country != null) _country = country;
        if (appVersion != null) _appVersion = appVersion;
        _offerings = null;
      },
    );
  }

  @override
  Future<InappifySdkResult<OfferingModel>> getCurrentOffering(
    InappifyCurrentOfferingRequest request,
  ) async {
    final cancelled = _preCancelled<OfferingModel>(
      'getCurrentOffering',
      request.cancellation,
    );
    if (cancelled != null) return cancelled;
    return _run<OfferingModel>(
      'getCurrentOffering',
      action: () async {
        final raw = await _bridge.call(
          'getCurrentOffering',
          positionalArguments: <Object?>[
            <String, Object?>{
              if (request.placementIdentifier != null)
                'placementIdentifier': request.placementIdentifier,
              if (request.context != null) 'context': request.context,
              'forceRefresh': request.forceRefresh,
            },
          ],
          cancellation: request.cancellation,
          injectAbortSignal: request.cancellation != null,
        );
        if (raw == null) return null;
        return InappifyWebPayloadCodec.offering(raw);
      },
      cancellation: request.cancellation,
    );
  }

  @override
  Future<InappifySdkResult<bool>> checkEntitlement(
    InappifyEntitlementCheckRequest request,
  ) async {
    final cancelled = _preCancelled<bool>(
      'checkEntitlement',
      request.cancellation,
    );
    if (cancelled != null) return cancelled;
    return _run<bool>(
      'checkEntitlement',
      action: () async {
        final raw = await _bridge.call(
          'checkEntitlement',
          positionalArguments: <Object?>[
            request.identifier,
            <String, Object?>{'forceRefresh': request.forceRefresh},
          ],
          cancellation: request.cancellation,
          injectAbortSignal: request.cancellation != null,
        );
        if (request.forceRefresh) _readCustomerPropertyBestEffort();
        return InappifyWebPayloadCodec.boolean(
          raw,
          field: 'entitlement result',
        );
      },
      cancellation: request.cancellation,
    );
  }

  @override
  Future<InappifySdkResult<List<Attribute>>> setAttributes(
    InappifyAttributesRequest request,
  ) async {
    final cancelled = _preCancelled<List<Attribute>>(
      'setAttributes',
      request.cancellation,
    );
    if (cancelled != null) return cancelled;
    return _run<List<Attribute>>(
      'setAttributes',
      action: () async {
        final values = InappifyWebPayloadCodec.attributeMap(request.attributes);
        final updates = <String, Object?>{
          for (final entry in values.entries)
            if (entry.value != null) entry.key: entry.value,
        };
        final deletions = <String>[
          for (final entry in values.entries)
            if (entry.value == null) entry.key,
        ];
        final idempotencyKey = request.idempotencyKey;
        final requiresAtomicSync =
            (updates.isNotEmpty && deletions.isNotEmpty) ||
            (idempotencyKey?.isNotEmpty ?? false);
        if (requiresAtomicSync) {
          final options = <String, Object?>{
            if (idempotencyKey?.isNotEmpty ?? false)
              'idempotencyKey': idempotencyKey,
          };
          await _bridge.call(
            'syncAttributes',
            positionalArguments: <Object?>[
              <Map<String, Object?>>[
                for (final entry in values.entries)
                  <String, Object?>{'key': entry.key, 'value': entry.value},
              ],
              if (options.isNotEmpty || request.cancellation != null) options,
            ],
            cancellation: request.cancellation,
            injectAbortSignal: request.cancellation != null,
          );
        } else if (updates.isNotEmpty) {
          await _bridge.call(
            'updateAttributes',
            positionalArguments: <Object?>[
              updates,
              if (request.cancellation != null) const <String, Object?>{},
            ],
            cancellation: request.cancellation,
            injectAbortSignal: request.cancellation != null,
          );
        } else if (deletions.isNotEmpty) {
          await _bridge.call(
            'deleteAttributes',
            positionalArguments: <Object?>[
              deletions,
              if (request.cancellation != null) const <String, Object?>{},
            ],
            cancellation: request.cancellation,
            injectAbortSignal: request.cancellation != null,
          );
        }
        _readCustomerPropertyBestEffort();
        return _currentAttributes;
      },
      mutationMayHaveCommitted: true,
      cancellation: request.cancellation,
    );
  }

  @override
  Future<InappifySdkResult<List<Attribute>>> deleteAttributes(
    InappifyDeleteAttributesRequest request,
  ) async {
    final cancelled = _preCancelled<List<Attribute>>(
      'deleteAttributes',
      request.cancellation,
    );
    if (cancelled != null) return cancelled;
    return _run<List<Attribute>>(
      'deleteAttributes',
      action: () async {
        await _bridge.call(
          'deleteAttributes',
          positionalArguments: <Object?>[
            request.keys,
            if (request.cancellation != null) const <String, Object?>{},
          ],
          cancellation: request.cancellation,
          injectAbortSignal: request.cancellation != null,
        );
        _readCustomerPropertyBestEffort();
        return _currentAttributes;
      },
      cancellation: request.cancellation,
      mutationMayHaveCommitted: true,
    );
  }

  @override
  Future<InappifySdkResult<void>> setReservedAttribute(
    InappifyReservedAttributeRequest request,
  ) async {
    final cancelled = _preCancelled<void>(
      'setReservedAttribute',
      request.cancellation,
    );
    if (cancelled != null) return cancelled;
    final setter = _documentedReservedSetter(request.attribute);
    if (setter == null) {
      return InappifySdkResult<void>.failure(
        InappifyFailure.unsupported(
          'setReservedAttribute.${request.attribute.name}',
        ),
        snapshot: _snapshot,
      );
    }
    return _run<void>(
      'setReservedAttribute',
      action: () async {
        await _bridge.call(
          setter,
          positionalArguments: <Object?>[
            request.value,
            if (request.cancellation != null) const <String, Object?>{},
          ],
          cancellation: request.cancellation,
          injectAbortSignal: request.cancellation != null,
        );
        _readCustomerPropertyBestEffort();
      },
      cancellation: request.cancellation,
      mutationMayHaveCommitted: true,
    );
  }

  @override
  Future<InappifySdkResult<List<Attribute>>> syncAttributes() {
    return _run<List<Attribute>>(
      'syncAttributes',
      action: () async {
        if (_customerInfo == null) {
          final raw = await _bridge.call(
            'getCustomerInfo',
            positionalArguments: const <Object?>[
              'FETCH_CURRENT',
              <String, Object?>{},
            ],
          );
          _customerInfo = InappifyWebPayloadCodec.customerInfo(raw);
          _failedToLoadCustomerInfo = false;
        }
        final attributes = _currentAttributes;
        await _bridge.call(
          'syncAttributes',
          positionalArguments: <Object?>[
            InappifyWebPayloadCodec.attributeList(attributes),
          ],
        );
        _readCustomerPropertyBestEffort();
        return _currentAttributes;
      },
      mutationMayHaveCommitted: true,
    );
  }

  @override
  Future<InappifySdkResult<List<Attribute>>> syncAttributeValues(
    InappifyAttributesRequest request,
  ) async {
    final cancelled = _preCancelled<List<Attribute>>(
      'syncAttributeValues',
      request.cancellation,
    );
    if (cancelled != null) return cancelled;
    return _syncAttributeList(
      request.attributes,
      operation: 'syncAttributeValues',
      idempotencyKey: request.idempotencyKey,
      cancellation: request.cancellation,
    );
  }

  @override
  Future<InappifySdkResult<bool>> canSetReservedAttribute(
    InappifyReservedAttributeCapabilityRequest request,
  ) {
    return _run<bool>(
      'canSetReservedAttribute',
      action: () async {
        final key = _reservedCapabilityKey(request.key);
        final raw = await _bridge.call(
          'canSetReservedAttribute',
          positionalArguments: <Object?>[key],
        );
        return InappifyWebPayloadCodec.boolean(
          raw,
          field: 'reserved attribute capability',
        );
      },
    );
  }

  @override
  Future<InappifySdkResult<InappifyCheckoutResult>> handlePaymentReturn(
    InappifyPaymentReturnRequest request,
  ) async {
    final cancelled = _preCancelled<InappifyCheckoutResult>(
      'handlePaymentReturn',
      request.cancellation,
    );
    if (cancelled != null) return cancelled;
    if (request.checkoutId.isEmpty) {
      return _invalid<InappifyCheckoutResult>(
        'handlePaymentReturn',
        'A checkoutId is required.',
      );
    }
    return _run<InappifyCheckoutResult>(
      'handlePaymentReturn',
      action: () async {
        final raw = await _bridge.call(
          'handlePaymentReturn',
          positionalArguments: <Object?>[
            request.checkoutId,
            <String, Object?>{
              'timeoutMs': request.timeoutMs,
              'intervalMs': request.intervalMs,
            },
          ],
          cancellation: request.cancellation,
          injectAbortSignal: request.cancellation != null,
        );
        final result = InappifyWebPayloadCodec.checkout(raw);
        _recordCheckoutState(result);
        return result;
      },
      cancellation: request.cancellation,
    );
  }

  @override
  Future<InappifySdkResult<String>> getPendingCheckoutId() {
    return _run<String>(
      'getPendingCheckoutId',
      requiresConfiguration: false,
      action: () async => _bridge.readPendingCheckout(),
    );
  }

  Future<InappifySdkResult<List<Attribute>>> _syncAttributeList(
    List<Attribute> attributes, {
    required String operation,
    String? idempotencyKey,
    InappifyRequestCancellation? cancellation,
  }) {
    final options = <String, Object?>{
      if (idempotencyKey != null && idempotencyKey.isNotEmpty)
        'idempotencyKey': idempotencyKey,
    };
    return _run<List<Attribute>>(
      operation,
      action: () async {
        await _bridge.call(
          'syncAttributes',
          positionalArguments: <Object?>[
            InappifyWebPayloadCodec.attributeList(attributes),
            if (options.isNotEmpty || cancellation != null) options,
          ],
          cancellation: cancellation,
          injectAbortSignal: cancellation != null,
        );
        _readCustomerPropertyBestEffort();
        return _currentAttributes;
      },
      cancellation: cancellation,
      mutationMayHaveCommitted: true,
    );
  }

  Future<InappifySdkResult<T>> _run<T>(
    String operation, {
    required Future<T?> Function() action,
    bool requiresConfiguration = true,
    InappifyRequestCancellation? cancellation,
    bool mutationMayHaveCommitted = false,
  }) async {
    if (!_bridge.isAvailable) {
      return _failure<T>(operation, InappifyFailureCode.bridgeUnavailable);
    }
    if (requiresConfiguration && !_configured) {
      return _failure<T>(operation, InappifyFailureCode.notConfigured);
    }
    try {
      final value = await action();
      return InappifySdkResult<T>.success(data: value, snapshot: _snapshot);
    } catch (error) {
      if (cancellation?.isCancelled ?? false) {
        return _cancelled<T>(
          operation,
          outcomeMayHaveCommitted: mutationMayHaveCommitted,
        );
      }
      var failure = _normalizeFailure(error, operation: operation);
      _applySessionFailureState(operation, failure);
      if (mutationMayHaveCommitted &&
          (failure.code == InappifyFailureCode.network ||
              failure.code == InappifyFailureCode.timeout ||
              failure.code == InappifyFailureCode.malformedResponse)) {
        failure = InappifyFailure(
          code: failure.code,
          message: failure.message,
          isRetryable: failure.isRetryable,
          details: <String, Object?>{
            ...failure.details,
            'outcomeMayHaveCommitted': true,
          },
        );
      }
      return InappifySdkResult<T>.failure(failure, snapshot: _snapshot);
    }
  }

  InappifySdkResult<T> _invalid<T>(String operation, String message) {
    return InappifySdkResult<T>.failure(
      InappifyFailure(
        code: InappifyFailureCode.invalidConfiguration,
        message: message,
        details: <String, Object?>{'operation': operation},
      ),
      snapshot: _snapshot,
    );
  }

  InappifySdkResult<T> _cancelled<T>(
    String operation, {
    bool outcomeMayHaveCommitted = false,
  }) {
    if (!outcomeMayHaveCommitted) {
      return _failure<T>(operation, InappifyFailureCode.requestCancelled);
    }
    return InappifySdkResult<T>.failure(
      InappifyFailure(
        code: InappifyFailureCode.requestCancelled,
        message: 'Inappify Web $operation was cancelled.',
        details: <String, Object?>{
          'operation': operation,
          'outcomeMayHaveCommitted': true,
        },
      ),
      snapshot: _snapshot,
    );
  }

  InappifySdkResult<T>? _preCancelled<T>(
    String operation,
    InappifyRequestCancellation? cancellation,
  ) {
    return cancellation?.isCancelled ?? false ? _cancelled<T>(operation) : null;
  }

  InappifySdkResult<T> _failure<T>(String operation, InappifyFailureCode code) {
    return InappifySdkResult<T>.failure(
      InappifyFailure(
        code: code,
        message: 'Inappify Web $operation failed.',
        details: <String, Object?>{'operation': operation},
      ),
      snapshot: _snapshot,
    );
  }

  InappifyFailure _normalizeFailure(Object error, {required String operation}) {
    if (error is _WebSemanticException) {
      return InappifyFailure(
        code: error.code,
        message: 'Inappify Web $operation failed.',
        details: <String, Object?>{
          'operation': operation,
          if (error.status != null) 'checkoutStatus': error.status,
        },
      );
    }
    if (error is FormatException || error is TypeError) {
      return InappifyFailure(
        code: InappifyFailureCode.malformedResponse,
        message: 'Inappify Web $operation returned an invalid response.',
        details: <String, Object?>{'operation': operation},
      );
    }
    if (error is InappifyWebBridgeException) {
      final normalizedCode = error.code.toLowerCase().replaceAll('-', '_');
      final kind = error.kind?.toLowerCase();
      final status = error.status;
      final code = switch ((
        normalizedCode,
        error.name?.toLowerCase(),
        status,
      )) {
        (_, 'aborterror', _) => InappifyFailureCode.requestCancelled,
        ('abort_error' || 'aborted' || 'request_cancelled', _, _) =>
          InappifyFailureCode.requestCancelled,
        ('timeout' || 'request_timeout' || 'checkout_timeout', _, _) =>
          InappifyFailureCode.timeout,
        ('checkout_poll_timeout', _, _) => InappifyFailureCode.timeout,
        (
          'session_recovery_required' ||
              'refresh_token_invalid' ||
              'refresh_token_expired' ||
              'session_expired' ||
              'session_revoked' ||
              'token_reuse_detected',
          _,
          _,
        ) =>
          InappifyFailureCode.sessionRecoveryRequired,
        (
          'session_temporarily_unavailable' || 'temporarily_unavailable',
          _,
          _,
        ) =>
          InappifyFailureCode.sessionTemporarilyUnavailable,
        (
          'storage_unavailable' ||
              'storage_corrupted' ||
              'session_storage_conflict',
          _,
          _,
        ) =>
          InappifyFailureCode.storageUnavailable,
        (_, _, 401 || 403) => InappifyFailureCode.unauthorized,
        ('unauthorized' || 'authentication_required', _, _) =>
          InappifyFailureCode.unauthorized,
        (
          'invalid_configuration' || 'invalid_api_key' || 'invalid_argument',
          _,
          _,
        ) =>
          InappifyFailureCode.invalidConfiguration,
        (
          'api_key_required' ||
              'feature_not_enabled' ||
              'attribute_not_writable' ||
              'invalid_attribute_value' ||
              'authentication_not_enabled' ||
              'fetch_unavailable' ||
              'invalid_base_url',
          _,
          _,
        ) =>
          InappifyFailureCode.invalidConfiguration,
        ('malformed_response', _, _) => InappifyFailureCode.malformedResponse,
        (
          'invalid_response' ||
              'invalid_session_response' ||
              'invalid_redirect_url',
          _,
          _,
        ) =>
          InappifyFailureCode.malformedResponse,
        ('not_configured', _, _) => InappifyFailureCode.notConfigured,
        ('network_error' || 'fetch_error' || 'network', _, _) =>
          InappifyFailureCode.network,
        ('purchase_cancelled' || 'checkout_cancelled' || 'cancelled', _, _) =>
          InappifyFailureCode.purchaseCancelled,
        ('unsupported_operation' || 'method_unavailable', _, _) =>
          InappifyFailureCode.unsupportedOperation,
        ('bridge_unavailable', _, _) => InappifyFailureCode.bridgeUnavailable,
        (_, _, final httpStatus) when httpStatus != null && httpStatus >= 500 =>
          InappifyFailureCode.network,
        _ when kind == 'configuration' =>
          InappifyFailureCode.invalidConfiguration,
        _ when kind == 'network' => InappifyFailureCode.network,
        _ when kind == 'timeout' => InappifyFailureCode.timeout,
        _ when kind == 'storage' => InappifyFailureCode.storageUnavailable,
        _ => InappifyFailureCode.unknown,
      };
      return InappifyFailure(
        code: code,
        message: 'Inappify Web $operation failed.',
        isRetryable:
            code == InappifyFailureCode.network ||
            code == InappifyFailureCode.timeout ||
            code == InappifyFailureCode.sessionTemporarilyUnavailable ||
            code == InappifyFailureCode.storageUnavailable ||
            normalizedCode == 'rate_limited_no_cache',
        details: <String, Object?>{
          'operation': operation,
          'serverCode': error.code,
          if (normalizedCode == 'rate_limited_no_cache' &&
              error.retryAfterMillis != null &&
              error.retryAfterMillis! >= 0 &&
              error.retryAfterMillis! <= 9007199254740991)
            'retryAfterMillis': error.retryAfterMillis,
          if (status != null) 'status': status,
          if (error.requestId != null) 'requestId': error.requestId,
          if (kind != null) 'kind': kind,
        },
      );
    }
    return InappifyFailure(
      code: InappifyFailureCode.unknown,
      message: 'Inappify Web $operation failed.',
      details: <String, Object?>{'operation': operation},
    );
  }

  void _applySessionFailureState(String operation, InappifyFailure failure) {
    if (failure.code == InappifyFailureCode.sessionRecoveryRequired) {
      _sessionState = InappifySessionState.recoveryRequired;
      return;
    }
    if (failure.code == InappifyFailureCode.sessionTemporarilyUnavailable) {
      _sessionState = InappifySessionState.temporarilyUnavailable;
      return;
    }
    if (operation != 'configure') return;
    final isTransient =
        failure.code == InappifyFailureCode.network ||
        failure.code == InappifyFailureCode.timeout ||
        failure.code == InappifyFailureCode.storageUnavailable;
    if (isTransient &&
        (!_configured ||
            _sessionState == InappifySessionState.recoveryRequired ||
            _sessionState == InappifySessionState.temporarilyUnavailable)) {
      _sessionState = InappifySessionState.temporarilyUnavailable;
    }
  }

  Future<void> _refreshCachedStateBestEffort({
    required bool includeOfferings,
  }) async {
    _readCustomerPropertyBestEffort();
    if (!includeOfferings) return;
    try {
      var raw = _bridge.readProperty('offerings');
      raw ??= await _bridge.call('getOfferings');
      final decoded = raw == null
          ? null
          : InappifyWebPayloadCodec.offerings(raw);
      if (decoded == null) {
        _offerings = null;
      } else {
        _commitOfferings(decoded);
      }
      _failedToLoadOfferings = false;
    } catch (_) {
      _failedToLoadOfferings = true;
    }
  }

  Future<Object?> _callSessionMutation({
    required String method,
    required List<Object?> positionalArguments,
    required CustomerInfo? previousCustomer,
    required OfferingsModel? previousOfferings,
    InappifyRequestCancellation? cancellation,
    bool injectAbortSignal = false,
  }) async {
    final revisionBeforeCall = _sessionStateRevision;
    _identityRevision += 1;
    try {
      return await _bridge.call(
        method,
        positionalArguments: positionalArguments,
        cancellation: cancellation,
        injectAbortSignal: injectAbortSignal,
      );
    } catch (_) {
      // beta.3 applies new session credentials before refreshing customer and
      // offering caches. If that later refresh fails, a state event proves the
      // mutation committed. Never retain mirrors belonging to the old user.
      if (_sessionStateRevision != revisionBeforeCall) {
        _clearUnchangedSessionMirrors(previousCustomer, previousOfferings);
        _readCustomerPropertyBestEffort();
        _readSessionMetadataBestEffort();
      }
      rethrow;
    }
  }

  void _readSessionMetadataBestEffort() {
    try {
      final rawState = _bridge.readProperty('sessionState');
      final state = InappifySessionState.fromWire(rawState);
      if (state != InappifySessionState.unknown) _sessionState = state;

      _persistenceMode = InappifySessionPersistenceMode.fromWire(
        _bridge.readProperty('persistenceMode'),
      );
    } catch (_) {
      // Session metadata is deliberately advisory and token-free. Direct
      // operation results still carry the authoritative success or failure.
    }
  }

  void _readCustomerProperty() {
    final raw = _bridge.readProperty('customerInfo');
    final decoded = raw == null
        ? null
        : InappifyWebPayloadCodec.customerInfo(raw);
    _customerInfo = decoded;
    _customerMirrorRevision += 1;
  }

  void _readCustomerPropertyBestEffort() {
    try {
      _readCustomerProperty();
      _failedToLoadCustomerInfo = false;
    } catch (_) {
      _failedToLoadCustomerInfo = true;
    }
  }

  List<Attribute> get _currentAttributes => List<Attribute>.unmodifiable(
    _customerInfo?.attributes ?? const <Attribute>[],
  );

  String? _resolvePackageIdentifier(InappifyPurchaseRequest request) {
    final requested = request.packageIdentifier;
    if (requested != null && requested.isNotEmpty) return requested;
    return _inferPackageIdentifier(
      offeringIdentifier: request.offeringIdentifier,
      productIdentifier: request.productIdentifier,
    );
  }

  bool _hasUnsupportedNativePurchaseOptions(InappifyPurchaseRequest request) {
    return request.isLostPurchase ||
        request.lostPurchaseToken != null ||
        request.lostPurchaseTime != null ||
        request.discount != 0;
  }

  Map<String, Object?> _checkoutParameters(
    InappifyPurchaseRequest request,
    String packageIdentifier,
  ) {
    // beta.1 falls back to the configured appVersion internally but not to
    // its configured country. Supplying both mirrors the configured targeting
    // context while still giving per-checkout values explicit precedence.
    final country = (request.country ?? _country).trim().toUpperCase();
    final appVersion = (request.appVersion ?? _appVersion).trim();
    return <String, Object?>{
      'offeringIdentifier': request.offeringIdentifier,
      'packageIdentifier': packageIdentifier,
      'productIdentifier': request.productIdentifier,
      'idempotencyKey': request.idempotencyKey,
      if (country.isNotEmpty) 'country': country,
      if (appVersion.isNotEmpty) 'appVersion': appVersion,
      'isCrypto': request.isCrypto,
      if (request.discountCode?.isNotEmpty ?? false)
        'discountCode': request.discountCode,
    };
  }

  void _recordCheckoutState(InappifyCheckoutResult result) {
    final status = result.checkout.status.toLowerCase();
    final isTerminal =
        status == 'paid' ||
        status == 'failed' ||
        status == 'expired' ||
        status == 'cancelled' ||
        status == 'canceled';
    if (isTerminal) {
      _bridge.clearPendingCheckout();
    } else {
      _bridge.persistPendingCheckout(result.checkout.id);
    }
    if (result.isPaid) _readCustomerPropertyBestEffort();
  }

  void _commitOfferings(OfferingsModel offerings) {
    _offerings = offerings;
    final forceVersion = offerings.forceVersion;
    if (forceVersion != null) _forceVersion = forceVersion;
  }

  void _clearUnchangedSessionMirrors(
    CustomerInfo? previousCustomer,
    OfferingsModel? previousOfferings,
  ) {
    // Authentication events may already have committed newer snapshots while
    // the Promise was pending. Clear only values that still belong to the
    // previous session so a failed post-operation refresh cannot expose the
    // prior customer's entitlements or purchase identifiers.
    if (identical(_customerInfo, previousCustomer)) _customerInfo = null;
    if (identical(_offerings, previousOfferings)) _offerings = null;
  }

  void _readConfigurationMetadataBestEffort() {
    try {
      final raw = _bridge.readProperty('configuration');
      if (raw == null) return;
      _commitConfigurationMetadata(
        InappifyWebPayloadCodec.requiredMap(raw, field: 'configuration'),
      );
    } catch (_) {
      // Configuration metadata enriches the compatibility snapshot only. A
      // successful JS session must not be failed by a future schema addition.
    }
  }

  void _commitConfigurationMetadata(Map<String, dynamic> configuration) {
    if (!configuration.containsKey('app')) return;
    final app = InappifyWebPayloadCodec.requiredMap(
      configuration['app'],
      field: 'configuration.app',
    );
    final id = app['id'];
    if (id is! num || !id.isFinite || id != id.toInt()) {
      throw const FormatException(
        'Web configuration app.id must be an integer.',
      );
    }
    _appId = id.toInt();
  }

  String? _inferPackageIdentifier({
    required String offeringIdentifier,
    required String productIdentifier,
  }) {
    final matches = <String>[];
    for (final offering in _offerings?.offerings ?? const <OfferingModel>[]) {
      if (offering.identifier != offeringIdentifier) continue;
      for (final package in offering.packages ?? const []) {
        final identifier = package.identifier;
        if (package.product?.identifier == productIdentifier &&
            identifier != null &&
            identifier.isNotEmpty) {
          matches.add(identifier);
        }
      }
    }
    return matches.length == 1 ? matches.single : null;
  }

  String? _documentedReservedSetter(InappifyReservedAttribute attribute) {
    return switch (attribute) {
      InappifyReservedAttribute.email => 'setEmail',
      InappifyReservedAttribute.apnsToken => 'setApnsToken',
      InappifyReservedAttribute.displayName => 'setDisplayName',
      InappifyReservedAttribute.fcmToken => 'setFcmToken',
      InappifyReservedAttribute.idfa => 'setIdfa',
      InappifyReservedAttribute.idfv => 'setIdfv',
      InappifyReservedAttribute.phoneNumber => 'setPhoneNumber',
      InappifyReservedAttribute.campaign => 'setCampaign',
      InappifyReservedAttribute.keyword => 'setKeyword',
      InappifyReservedAttribute.ip => null,
    };
  }

  String _reservedCapabilityKey(String input) {
    final key = input.startsWith(r'$') ? input.substring(1) : input;
    return switch (key) {
      'fcmToken' || 'fcmTokens' => r'$fcmTokens',
      'apnsToken' || 'apnsTokens' => r'$apnsTokens',
      _ => r'$' + key,
    };
  }

  void _handleBridgeEvent(InappifyWebBridgeEvent event) {
    try {
      final type = switch (event.name) {
        'customerInfoUpdated' => InappifyPlatformEventType.customerInfoChanged,
        'offeringsUpdated' => InappifyPlatformEventType.offeringsChanged,
        'authenticationChanged' =>
          InappifyPlatformEventType.authenticationChanged,
        'sessionStateChanged' => InappifyPlatformEventType.sessionStateChanged,
        _ => null,
      };
      if (type == null) return;
      var data = const <String, Object?>{};
      if (type == InappifyPlatformEventType.customerInfoChanged) {
        _customerInfo = event.payload == null
            ? null
            : InappifyWebPayloadCodec.customerInfo(event.payload);
        _customerMirrorRevision += 1;
        _failedToLoadCustomerInfo = false;
      } else if (type == InappifyPlatformEventType.offeringsChanged) {
        if (event.payload == null) {
          _offerings = null;
        } else {
          _commitOfferings(InappifyWebPayloadCodec.offerings(event.payload));
        }
        _failedToLoadOfferings = false;
      } else if (type == InappifyPlatformEventType.sessionStateChanged) {
        final change = InappifySessionStateChange.fromMap(
          InappifyWebPayloadCodec.requiredMap(
            event.payload,
            field: 'sessionStateChanged',
          ),
        );
        if ((change.state == InappifySessionState.anonymous ||
                change.state == InappifySessionState.authenticated) &&
            _sessionState != InappifySessionState.refreshing) {
          // The provider publishes replacement credentials before refreshing
          // its caches. Do not expose the preceding customer's mirror during
          // that interval. Token rotation remains the same customer.
          _identityRevision += 1;
          _customerInfo = null;
          _offerings = null;
          _customerMirrorRevision += 1;
        }
        _sessionState = change.state;
        _sessionStateRevision += 1;
        data = change.toMap();
      } else if (event.payload != null) {
        _identityRevision += 1;
        data = InappifyWebPayloadCodec.authentication(event.payload).toMap();
        _readCustomerPropertyBestEffort();
      }
      _eventController.add(
        InappifyPlatformEvent(type: type, snapshot: _snapshot, data: data),
      );
    } catch (_) {
      // Malformed external events are ignored; direct operations remain the
      // authoritative path and no raw JavaScript payload is logged.
    }
  }

  void _ignoreBridgeEventError(Object error, StackTrace stackTrace) {}

  Map<String, dynamic> _sanitizeConfiguration(Map<String, dynamic> map) {
    const blockedFragments = <String>{
      'accesstoken',
      'refreshtoken',
      'authorization',
      'identityticket',
      'serverkey',
      'projectkey',
      'marketkey',
      'apikey',
      'password',
      'clientsecret',
    };
    final result = <String, dynamic>{};
    for (final entry in map.entries) {
      final key = entry.key;
      final compact = key.toLowerCase().replaceAll(RegExp('[^a-z]'), '');
      if (blockedFragments.any(compact.contains)) continue;
      final value = entry.value;
      if (value is Map) {
        result[key] = _sanitizeConfiguration(
          value.map<String, dynamic>(
            (nestedKey, nestedValue) =>
                MapEntry<String, dynamic>(nestedKey.toString(), nestedValue),
          ),
        );
      } else if (value is List) {
        result[key] = value
            .map<Object?>((item) {
              if (item is Map) {
                return _sanitizeConfiguration(
                  item.map<String, dynamic>(
                    (nestedKey, nestedValue) => MapEntry<String, dynamic>(
                      nestedKey.toString(),
                      nestedValue,
                    ),
                  ),
                );
              }
              return item;
            })
            .toList(growable: false);
      } else {
        result[key] = value;
      }
    }
    return result;
  }

  InappifySdkSnapshot get _snapshot => InappifySdkSnapshot(
    revision: ++_snapshotRevision,
    accessToken: null,
    apiKey: _apiKey,
    customerInfo: _customerInfo,
    offerings: _offerings,
    storeInfo: 'web',
    forceVersion: _forceVersion,
    appId: _appId,
    country: _country,
    versionName: _appVersion,
    versionCode: null,
    sdkVersion: _bridge.sdkVersion,
    sessionState: _sessionState,
    persistenceMode: _persistenceMode,
    failedToLoadOfferings: _failedToLoadOfferings,
    failedToLoadCustomerInfo: _failedToLoadCustomerInfo,
  );

  /// Releases bridge listeners. Production registration owns this adapter for
  /// the page lifetime; this method exists for deterministic browser tests.
  Future<void> dispose() async {
    await _bridgeSubscription.cancel();
    await _bridge.dispose();
    await _eventController.close();
  }
}

bool _sameConfiguration(
  Map<String, Object?>? current,
  Map<String, Object?> next,
) {
  if (current == null || current.length != next.length) return false;
  for (final entry in next.entries) {
    if (!current.containsKey(entry.key) || current[entry.key] != entry.value) {
      return false;
    }
  }
  return true;
}

String _customerFetchPolicy(InappifyCacheFetchPolicy policy) =>
    switch (policy) {
      InappifyCacheFetchPolicy.cacheOnly => 'CACHE_ONLY',
      InappifyCacheFetchPolicy.fetchCurrent => 'FETCH_CURRENT',
      InappifyCacheFetchPolicy.notStaleCachedOrCurrent =>
        'NOT_STALE_CACHED_OR_CURRENT',
      InappifyCacheFetchPolicy.cachedOrFetched => 'CACHED_OR_FETCHED',
    };

/// 0.2.0 supplies the policy overload and the combined targeting sync contract.
bool _supportsSafeSessionContract(String? version) {
  if (version == null) return false;
  final match = RegExp(
    r'^(\d+)\.(\d+)\.(\d+)(?:-([0-9A-Za-z.-]+))?(?:\+[0-9A-Za-z.-]+)?$',
  ).firstMatch(version.trim());
  if (match == null) return false;
  final parts = <int>[
    int.parse(match.group(1)!),
    int.parse(match.group(2)!),
    int.parse(match.group(3)!),
  ];
  const minimum = <int>[0, 2, 0];
  for (var index = 0; index < parts.length; index += 1) {
    if (parts[index] > minimum[index]) return true;
    if (parts[index] < minimum[index]) return false;
  }
  return match.group(4) == null;
}

class _WebSemanticException implements Exception {
  const _WebSemanticException({required this.code, this.status});

  final InappifyFailureCode code;
  final String? status;
}
