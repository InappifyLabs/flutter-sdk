import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:inappify_sdk/inappify_sdk_platform_interface.dart'
    show InappifySdkPlatform;
import 'package:inappify_sdk/models/attribute.dart';
import 'package:inappify_sdk/models/mobile_v2.dart';
import 'package:inappify_sdk/models/authentication_result.dart';
import 'package:inappify_sdk/models/captcha_challenge.dart';
import 'package:inappify_sdk/models/checkout_result.dart';
import 'package:inappify_sdk/models/customer_info.dart';
import 'package:inappify_sdk/models/inappify_configuration.dart';
import 'package:inappify_sdk/models/offering_model.dart';
import 'package:inappify_sdk/models/offerings_model.dart';
import 'package:inappify_sdk/models/otp_challenge.dart';
import 'package:inappify_sdk/models/purchase_result.dart';
import 'package:inappify_sdk/models/validate_discount_code_data.dart';
import 'package:inappify_sdk/src/platform/channel/channel_codec.dart';
import 'package:inappify_sdk/src/platform/channel/channel_contract.dart';
import 'package:inappify_sdk/src/platform/contracts/app_version_info.dart';
import 'package:inappify_sdk/src/platform/contracts/backend_capabilities.dart';
import 'package:inappify_sdk/src/platform/contracts/platform_event.dart';
import 'package:inappify_sdk/src/platform/contracts/sdk_failure.dart';
import 'package:inappify_sdk/src/platform/contracts/sdk_requests.dart';
import 'package:inappify_sdk/src/platform/contracts/sdk_result.dart';

/// MethodChannel implementation of the complete Inappify platform contract.
///
/// Android advertises and owns the complete protocol-v1 mobile lifecycle.
/// Bazaar and Myket use the same configure, purchase, recovery and delivery
/// commands; native Kotlin SDK owns billing, receipt validation and consumption.
/// iOS intentionally reports a non-owning capability, so the same façade keeps
/// its existing Dart backend there without platform checks in public code.
class MethodChannelInappifySdk extends InappifySdkPlatform {
  MethodChannelInappifySdk({
    MethodChannel? methodChannel,
    EventChannel? eventChannel,
    EventChannel? httpEventChannel,
    String Function()? requestIdGenerator,
  }) : methodChannel =
           methodChannel ??
           const MethodChannel(InappifyChannelContract.channelName),
       eventChannel =
           eventChannel ??
           const EventChannel(InappifyChannelContract.eventChannelName),
       httpEventChannel =
           httpEventChannel ??
           const EventChannel(InappifyChannelContract.httpEventChannelName),
       _requestIdGenerator = requestIdGenerator;

  /// Method channel used to communicate with the native plugin.
  @visibleForTesting
  final MethodChannel methodChannel;

  /// Event channel reserved for redirects and native state changes.
  @visibleForTesting
  final EventChannel eventChannel;
  final EventChannel httpEventChannel;
  Stream<InappifyHttpTrace>? _httpTraces;

  @override
  Stream<InappifyHttpTrace> get httpTraces =>
      _httpTraces ??= httpEventChannel.receiveBroadcastStream().map((raw) {
        final normalized = InappifyChannelCodec.normalize(raw);
        if (normalized is! Map<String, Object?>) {
          throw const FormatException('Invalid HTTP diagnostic.');
        }
        return InappifyHttpTrace.fromMap(normalized.cast<String, dynamic>());
      });

  @override
  Future<InappifySdkResult<List<PurchaseResult>>> syncPurchases() =>
      _invokeResult(
        method: InappifyChannelContract.syncPurchases,
        payload: const {},
        decodeData: (map) {
          final purchases = map['purchases'];
          if (purchases is! List) {
            throw const FormatException('Missing purchases.');
          }
          return List.unmodifiable(
            purchases.map((value) {
              if (value is! Map) {
                throw const FormatException('Invalid purchase.');
              }
              return PurchaseResult.fromJson(Map<String, dynamic>.from(value));
            }),
          );
        },
      );

  @override
  Future<InappifySdkResult<InappifyRestoreResult>> restorePurchases() =>
      _invokeResult(
        method: InappifyChannelContract.restorePurchases,
        payload: const {},
        decodeData: InappifyRestoreResult.fromMap,
      );
  @override
  Future<InappifySdkResult<InappifyConsumableSyncResult>>
  syncPendingConsumables() => _invokeResult(
    method: InappifyChannelContract.syncPendingConsumables,
    payload: const {},
    decodeData: InappifyConsumableSyncResult.fromMap,
  );
  @override
  Future<InappifySdkResult<PurchaseResult>> confirmDelivery(int deliveryId) =>
      _invokeResult(
        method: InappifyChannelContract.confirmDelivery,
        payload: {'deliveryId': deliveryId},
        decodeData: PurchaseResult.fromJson,
      );
  @override
  Future<InappifySdkResult<CustomerInfo>> customerInfoWithPolicy(
    InappifyFetchPolicy policy,
  ) => _invokeResult(
    method: InappifyChannelContract.customerInfoWithPolicy,
    payload: {'policy': policy.name},
    decodeData: CustomerInfo.fromJson,
  );
  @override
  Future<InappifySdkResult<OfferingsModel>> offeringsWithPolicy(
    InappifyFetchPolicy policy,
  ) => _invokeResult(
    method: InappifyChannelContract.offeringsWithPolicy,
    payload: {'policy': policy.name},
    decodeData: OfferingsModel.fromJson,
  );
  @override
  Future<InappifySdkResult<void>> queueAttributes(
    Map<String, String?> values,
  ) => _invokeResult(
    method: InappifyChannelContract.queueAttributes,
    payload: {'values': values},
  );
  @override
  Future<InappifySdkResult<void>> flushAttributes() => _invokeResult(
    method: InappifyChannelContract.flushAttributes,
    payload: const {},
  );
  @override
  Future<InappifySdkResult<void>> recover() =>
      _invokeResult(method: InappifyChannelContract.recover, payload: const {});
  @override
  Future<InappifySdkResult<void>> setNetworkEnabled(bool enabled) =>
      _invokeResult(
        method: InappifyChannelContract.setNetworkEnabled,
        payload: {'enabled': enabled},
      );
  @override
  Future<InappifySdkResult<bool>> isPaymentUrlAllowed(String url) =>
      _invokeResult(
        method: InappifyChannelContract.isPaymentUrlAllowed,
        payload: {'url': url},
        decodeData: _decodeBoolean,
      );

  final String Function()? _requestIdGenerator;
  int _requestCounter = 0;

  @override
  Stream<InappifyPlatformEvent> get events => eventChannel
      .receiveBroadcastStream()
      .map<InappifyPlatformEvent>(InappifyChannelCodec.decodeEvent);

  @override
  Future<String?> getPlatformVersion() async {
    return methodChannel.invokeMethod<String>('getPlatformVersion');
  }

  @override
  Future<InappifyAppVersionInfo?> getAppVersionInfo() async {
    final raw = await methodChannel.invokeMethod<Object?>('getVersionInfo');
    final normalized = InappifyChannelCodec.normalize(raw);
    if (normalized is! Map<String, Object?>) {
      throw const FormatException('getVersionInfo must return a map.');
    }
    return InappifyAppVersionInfo.fromMap(normalized.cast<String, dynamic>());
  }

  @override
  Future<InappifyBackendCapabilities> getCapabilities() async {
    try {
      final response = await _invoke(
        method: InappifyChannelContract.handshake,
        payload: <String, Object?>{
          'clientProtocolVersions': const <int>[
            InappifyChannelContract.protocolVersion,
          ],
        },
      );
      if (!response.isSuccess || response.data == null) {
        return InappifyBackendCapabilities.unavailable(
          backendKind: InappifyBackendKind.methodChannel,
        );
      }
      return InappifyBackendCapabilities.fromMap(response.data!);
    } on MissingPluginException {
      return InappifyBackendCapabilities.unavailable(
        backendKind: InappifyBackendKind.methodChannel,
      );
    } on PlatformException {
      return InappifyBackendCapabilities.unavailable(
        backendKind: InappifyBackendKind.methodChannel,
      );
    } on FormatException {
      return InappifyBackendCapabilities.unavailable(
        backendKind: InappifyBackendKind.methodChannel,
      );
    } catch (_) {
      return InappifyBackendCapabilities.unavailable(
        backendKind: InappifyBackendKind.methodChannel,
      );
    }
  }

  @override
  Future<InappifySdkResult<void>> configure(InappifyConfigureRequest request) {
    return _invokeResult<void>(
      method: InappifyChannelContract.configure,
      payload: request.toMap(),
    );
  }

  @override
  Future<InappifySdkResult<bool>> restoreCachedSession(
    InappifyConfigureRequest request,
  ) => _invokeResult<bool>(
    method: InappifyChannelContract.restoreCachedSession,
    payload: request.toMap(),
    decodeData: _decodeBoolean,
  );

  @override
  Future<InappifySdkResult<void>> login(InappifyLoginRequest request) {
    return _invokeResult<void>(
      method: InappifyChannelContract.login,
      payload: request.toMap(),
    );
  }

  @override
  Future<InappifySdkResult<InappifyAuthenticationResult>>
  exchangeIdentityTicket(InappifyIdentityTicketRequest request) {
    return _invokeResult<InappifyAuthenticationResult>(
      method: InappifyChannelContract.exchangeIdentityTicket,
      payload: request.toMap(),
      decodeData: InappifyAuthenticationResult.fromMap,
    );
  }

  @override
  Future<InappifySdkResult<InappifyOtpChallenge>> requestOtp(
    InappifyOtpRequest request,
  ) {
    return _invokeResult<InappifyOtpChallenge>(
      method: InappifyChannelContract.requestOtp,
      payload: request.toMap(),
      decodeData: InappifyOtpChallenge.fromMap,
    );
  }

  @override
  Future<InappifySdkResult<InappifyCaptchaChallenge>> createOtpCaptcha(
    InappifyNetworkRequest request,
  ) {
    return _invokeResult<InappifyCaptchaChallenge>(
      method: InappifyChannelContract.createOtpCaptcha,
      payload: request.toMap(),
      decodeData: InappifyCaptchaChallenge.fromMap,
    );
  }

  @override
  Future<InappifySdkResult<InappifyAuthenticationResult>> verifyOtp(
    InappifyOtpVerificationRequest request,
  ) {
    return _invokeResult<InappifyAuthenticationResult>(
      method: InappifyChannelContract.verifyOtp,
      payload: request.toMap(),
      decodeData: InappifyAuthenticationResult.fromMap,
    );
  }

  @override
  Future<InappifySdkResult<void>> logout() {
    return _invokeResult<void>(
      method: InappifyChannelContract.logout,
      payload: const <String, Object?>{},
    );
  }

  @override
  Future<InappifySdkResult<PurchaseResult>> purchase(
    InappifyPurchaseRequest request,
  ) {
    return _invokeResult<PurchaseResult>(
      method: InappifyChannelContract.purchase,
      payload: request.toMap(),
      requestId: request.idempotencyKey,
      decodeData: PurchaseResult.fromJson,
    );
  }

  @override
  Future<InappifySdkResult<InappifyCheckoutResult>> createCheckout(
    InappifyPurchaseRequest request,
  ) {
    return _invokeResult<InappifyCheckoutResult>(
      method: InappifyChannelContract.createCheckout,
      payload: request.toMap(),
      requestId: request.idempotencyKey,
      decodeData: InappifyCheckoutResult.fromMap,
    );
  }

  @override
  Future<InappifySdkResult<InappifyCheckoutResult>> getCheckoutStatus(
    InappifyCheckoutStatusRequest request,
  ) {
    return _invokeResult<InappifyCheckoutResult>(
      method: InappifyChannelContract.getCheckoutStatus,
      payload: request.toMap(),
      decodeData: InappifyCheckoutResult.fromMap,
    );
  }

  @override
  Future<InappifySdkResult<ValidateDiscountCodeData>> validateDiscountCode(
    InappifyDiscountCodeRequest request,
  ) {
    return _invokeResult<ValidateDiscountCodeData>(
      method: InappifyChannelContract.validateDiscountCode,
      payload: request.toMap(),
      decodeData: ValidateDiscountCodeData.fromJson,
    );
  }

  @override
  Future<InappifySdkResult<CustomerInfo>> getCustomerInfo(
    InappifyRefreshRequest request,
  ) {
    return _invokeResult<CustomerInfo>(
      method: InappifyChannelContract.getCustomerInfo,
      payload: request.toMap(),
      decodeData: CustomerInfo.fromJson,
    );
  }

  @override
  Future<InappifySdkResult<InappifyConfiguration>> getConfiguration() {
    return _invokeResult<InappifyConfiguration>(
      method: InappifyChannelContract.getConfiguration,
      payload: const <String, Object?>{},
      decodeData: _decodeConfiguration,
    );
  }

  @override
  Future<InappifySdkResult<OfferingsModel>> getOfferings(
    InappifyRefreshRequest request,
  ) {
    return _invokeResult<OfferingsModel>(
      method: InappifyChannelContract.getOfferings,
      payload: request.toMap(),
      decodeData: OfferingsModel.fromJson,
    );
  }

  @override
  Future<InappifySdkResult<void>> setTargetingContext(
    InappifyTargetingContextRequest request,
  ) {
    return _invokeResult<void>(
      method: InappifyChannelContract.setTargetingContext,
      payload: request.toMap(),
    );
  }

  @override
  Future<InappifySdkResult<OfferingModel>> getCurrentOffering(
    InappifyCurrentOfferingRequest request,
  ) {
    return _invokeResult<OfferingModel>(
      method: InappifyChannelContract.getCurrentOffering,
      payload: request.toMap(),
      decodeData: OfferingModel.fromJson,
      allowMissingData: true,
    );
  }

  @override
  Future<InappifySdkResult<bool>> checkEntitlement(
    InappifyEntitlementCheckRequest request,
  ) {
    return _invokeResult<bool>(
      method: InappifyChannelContract.checkEntitlement,
      payload: request.toMap(),
      decodeData: _decodeBoolean,
    );
  }

  @override
  Future<InappifySdkResult<List<Attribute>>> setAttributes(
    InappifyAttributesRequest request,
  ) {
    return _invokeResult<List<Attribute>>(
      method: InappifyChannelContract.setAttributes,
      payload: request.toMap(),
      decodeData: _decodeAttributes,
    );
  }

  @override
  Future<InappifySdkResult<List<Attribute>>> deleteAttributes(
    InappifyDeleteAttributesRequest request,
  ) {
    return _invokeResult<List<Attribute>>(
      method: InappifyChannelContract.deleteAttributes,
      payload: request.toMap(),
      decodeData: _decodeAttributes,
    );
  }

  @override
  Future<InappifySdkResult<void>> setReservedAttribute(
    InappifyReservedAttributeRequest request,
  ) {
    return _invokeResult<void>(
      method: InappifyChannelContract.setReservedAttribute,
      payload: request.toMap(),
    );
  }

  @override
  Future<InappifySdkResult<List<Attribute>>> syncAttributes() {
    return _invokeResult<List<Attribute>>(
      method: InappifyChannelContract.syncAttributes,
      payload: const <String, Object?>{},
      decodeData: _decodeAttributes,
    );
  }

  @override
  Future<InappifySdkResult<List<Attribute>>> syncAttributeValues(
    InappifyAttributesRequest request,
  ) {
    return _invokeResult<List<Attribute>>(
      method: InappifyChannelContract.syncAttributeValues,
      payload: request.toMap(),
      decodeData: _decodeAttributes,
    );
  }

  @override
  Future<InappifySdkResult<bool>> canSetReservedAttribute(
    InappifyReservedAttributeCapabilityRequest request,
  ) {
    return _invokeResult<bool>(
      method: InappifyChannelContract.canSetReservedAttribute,
      payload: request.toMap(),
      decodeData: _decodeBoolean,
    );
  }

  @override
  Future<InappifySdkResult<InappifyCheckoutResult>> handlePaymentReturn(
    InappifyPaymentReturnRequest request,
  ) {
    return _invokeResult<InappifyCheckoutResult>(
      method: InappifyChannelContract.handlePaymentReturn,
      payload: request.toMap(),
      decodeData: InappifyCheckoutResult.fromMap,
    );
  }

  @override
  Future<InappifySdkResult<String>> getPendingCheckoutId() {
    return _invokeResult<String>(
      method: InappifyChannelContract.getPendingCheckoutId,
      payload: const <String, Object?>{},
      decodeData: (data) {
        final value = data['checkoutId'];
        if (value is String && value.isNotEmpty) return value;
        throw const FormatException(
          'Pending checkout response must contain checkoutId.',
        );
      },
      allowMissingData: true,
    );
  }

  Future<InappifySdkResult<T>> _invokeResult<T>({
    required String method,
    required Map<String, Object?> payload,
    String? requestId,
    T Function(Map<String, dynamic>)? decodeData,
    bool allowMissingData = false,
  }) async {
    try {
      final response = await _invoke(
        method: method,
        payload: payload,
        requestId: requestId,
      );
      if (!response.isSuccess) {
        return InappifySdkResult<T>.failure(
          response.failure ??
              const InappifyFailure(
                code: InappifyFailureCode.unknown,
                message: 'Platform SDK operation failed.',
              ),
          snapshot: response.snapshot,
        );
      }

      if (response.snapshot == null) {
        return InappifySdkResult<T>.failure(
          InappifyFailure(
            code: InappifyFailureCode.malformedResponse,
            message: 'Platform SDK success response is missing snapshot.',
            details: _ambiguousPurchaseDetails(method),
          ),
        );
      }
      if (decodeData != null && response.data == null && !allowMissingData) {
        return InappifySdkResult<T>.failure(
          InappifyFailure(
            code: InappifyFailureCode.malformedResponse,
            message: 'Platform SDK success response is missing data.',
            details: _ambiguousPurchaseDetails(method),
          ),
          snapshot: response.snapshot,
        );
      }

      T? data;
      if (decodeData != null && response.data != null) {
        try {
          data = decodeData(response.data!);
        } catch (error) {
          return InappifySdkResult<T>.failure(
            InappifyFailure(
              code: InappifyFailureCode.malformedResponse,
              message: 'Platform SDK data could not be decoded.',
              details: <String, Object?>{
                'errorType': error.runtimeType.toString(),
                ..._ambiguousPurchaseDetails(method),
              },
            ),
            snapshot: response.snapshot,
          );
        }
      }
      return InappifySdkResult<T>.success(
        data: data,
        snapshot: response.snapshot,
      );
    } on MissingPluginException catch (error) {
      return InappifySdkResult<T>.failure(
        InappifyFailure(
          code: InappifyFailureCode.bridgeUnavailable,
          message: error.message ?? 'Native Inappify bridge is unavailable.',
        ),
      );
    } on PlatformException catch (error) {
      return InappifySdkResult<T>.failure(
        InappifyFailure(
          code: _failureCodeForPlatformException(error.code),
          message: 'Native Inappify operation failed.',
          details: <String, Object?>{
            'platformCode': error.code,
            ..._ambiguousPurchaseDetails(method),
          },
        ),
      );
    } on FormatException catch (error) {
      return InappifySdkResult<T>.failure(
        InappifyFailure(
          code: InappifyFailureCode.malformedResponse,
          message: error.message,
          details: _ambiguousPurchaseDetails(method),
        ),
      );
    } catch (error) {
      return InappifySdkResult<T>.failure(
        InappifyFailure(
          code: InappifyFailureCode.malformedResponse,
          message: 'Unexpected native Inappify bridge response.',
          details: <String, Object?>{
            'errorType': error.runtimeType.toString(),
            ..._ambiguousPurchaseDetails(method),
          },
        ),
      );
    }
  }

  Future<InappifyChannelResponse> _invoke({
    required String method,
    required Map<String, Object?> payload,
    String? requestId,
  }) async {
    final resolvedRequestId = requestId ?? _nextRequestId();
    final raw = await methodChannel.invokeMethod<Object?>(
      method,
      InappifyChannelContract.requestEnvelope(
        requestId: resolvedRequestId,
        payload: payload,
      ),
    );
    return InappifyChannelCodec.decodeResponse(
      raw,
      expectedRequestId: resolvedRequestId,
    );
  }

  // Decoding failure after native dispatch cannot prove a payment did not occur.
  static Map<String, Object?> _ambiguousPurchaseDetails(String method) =>
      switch (method) {
        InappifyChannelContract.purchase => {
          'operation': 'purchase',
          'outcomeMayHaveCommitted': true,
        },
        InappifyChannelContract.confirmDelivery => {
          'operation': 'confirmDelivery',
          'outcomeMayHaveCommitted': true,
        },
        _ => const {},
      };

  String _nextRequestId() {
    final generator = _requestIdGenerator;
    if (generator != null) return generator();
    _requestCounter += 1;
    return '${DateTime.now().microsecondsSinceEpoch}-$_requestCounter';
  }

  static List<Attribute> _decodeAttributes(Map<String, dynamic> data) {
    final rawAttributes = data['attributes'];
    if (rawAttributes is! List) {
      throw const FormatException('attributes must be a list.');
    }
    return rawAttributes
        .map<Attribute>((item) {
          if (item is! Map) {
            throw const FormatException('Each attribute must be a map.');
          }
          return Attribute.fromJson(
            item.map<String, dynamic>(
              (key, value) => MapEntry<String, dynamic>(key.toString(), value),
            ),
          );
        })
        .toList(growable: false);
  }

  static bool _decodeBoolean(Map<String, dynamic> data) {
    final value = data['value'] ?? data['allowed'] ?? data['canSet'];
    if (value is! bool) {
      throw const FormatException('Boolean result is missing its value.');
    }
    return value;
  }

  static InappifyConfiguration _decodeConfiguration(Map<String, dynamic> data) {
    final configuration = data['configuration'];
    if (configuration is Map) {
      return InappifyConfiguration.fromMap(
        configuration.map<String, dynamic>(
          (key, value) => MapEntry<String, dynamic>(key.toString(), value),
        ),
      );
    }
    return InappifyConfiguration.fromMap(data);
  }

  static InappifyFailureCode _failureCodeForPlatformException(String code) {
    switch (code) {
      case 'inappify/invalid-arguments':
        return InappifyFailureCode.invalidConfiguration;
      case 'inappify/not-configured':
        return InappifyFailureCode.notConfigured;
      case 'inappify/sdk-unavailable':
        return InappifyFailureCode.bridgeUnavailable;
      case 'inappify/unsupported-protocol':
        return InappifyFailureCode.protocolMismatch;
      default:
        return InappifyFailureCode.unknown;
    }
  }
}
