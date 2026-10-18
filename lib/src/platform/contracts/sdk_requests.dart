import 'package:flutter/foundation.dart';
import 'package:inappify_sdk/models/attribute.dart';
import 'package:inappify_sdk/models/enums/market.dart';
import 'package:inappify_sdk/models/mobile_v2.dart';
import 'package:inappify_sdk/request_cancellation.dart';

/// Configuration input shared by every Inappify backend.
///
/// [apiKey] and [marketKey] are secrets and must not be included in logs.
@immutable
class InappifyConfigureRequest {
  const InappifyConfigureRequest({
    required this.apiKey,
    this.appUserIdentifier,
    this.market,
    this.marketKey,
    this.country,
    this.appVersion,
    this.mobileProtocol = InappifyMobileProtocol.goV2,
    this.enableSubscriptionRecoveryWithoutPayload = true,
  });

  final String apiKey;
  final String? appUserIdentifier;
  final Market? market;
  final String? marketKey;
  final String? country;
  final String? appVersion;
  final InappifyMobileProtocol mobileProtocol;

  /// Android Bazaar only. Requires the V2 subscription recovery endpoint.
  /// Set false to preserve pending checkpoints without discovering or polling
  /// payloadless subscriptions. Ignored by iOS and Web.
  final bool enableSubscriptionRecoveryWithoutPayload;

  Map<String, Object?> toMap() => <String, Object?>{
    'apiKey': apiKey,
    'appUserIdentifier': appUserIdentifier,
    'market': market == null ? null : _marketWireName(market!),
    'marketKey': marketKey,
    'country': country,
    'appVersion': appVersion,
    'mobileProtocol': mobileProtocol.name,
    'enableSubscriptionRecoveryWithoutPayload':
        enableSubscriptionRecoveryWithoutPayload,
  };
}

/// Login input shared by every Inappify backend.
@immutable
class InappifyLoginRequest {
  const InappifyLoginRequest({required this.appUserIdentifier});

  final String appUserIdentifier;

  Map<String, Object?> toMap() => <String, Object?>{
    'appUserIdentifier': appUserIdentifier,
  };
}

/// Purchase input shared by Dart, JavaScript, and native SDK backends.
///
/// [idempotencyKey] identifies this logical attempt. Implementations must keep
/// it unchanged when retrying the same platform request and must not log store
/// purchase tokens returned by a billing provider.
@immutable
class InappifyPurchaseRequest {
  const InappifyPurchaseRequest({
    required this.productIdentifier,
    required this.offeringIdentifier,
    required this.idempotencyKey,
    this.packageIdentifier,
    this.discountCode,
    this.country,
    this.appVersion,
    this.apiKey,
    this.discount = 0,
    this.isCrypto = false,
    this.market = Market.none,
    this.marketKey,
    this.isLostPurchase = false,
    this.lostPurchaseToken,
    this.lostPurchaseTime,
    this.productType,
    this.dynamicPriceToken,
    this.paywallId,
    this.paywallRevision,
    this.cancellation,
  });

  final String productIdentifier;
  final String offeringIdentifier;
  final String idempotencyKey;
  final String? packageIdentifier;
  final String? discountCode;
  final String? country;
  final String? appVersion;
  final String? apiKey;
  final int discount;
  final bool isCrypto;
  final Market market;
  final String? marketKey;
  final bool isLostPurchase;
  final String? lostPurchaseToken;
  final int? lostPurchaseTime;

  /// Omit for the native SDK's unknown in-app product classification when omitted.
  final InappifyProductType? productType;
  final String? dynamicPriceToken;
  final int? paywallId;
  final int? paywallRevision;

  /// Cooperative browser request cancellation; never serialized to a channel.
  final InappifyRequestCancellation? cancellation;

  Map<String, Object?> toMap() => <String, Object?>{
    'productIdentifier': productIdentifier,
    'offeringIdentifier': offeringIdentifier,
    'idempotencyKey': idempotencyKey,
    'packageIdentifier': packageIdentifier,
    'discountCode': discountCode,
    'country': country,
    'appVersion': appVersion,
    'apiKey': apiKey,
    'discount': discount,
    'isCrypto': isCrypto,
    'market': _marketWireName(market),
    'marketKey': marketKey,
    'isLostPurchase': isLostPurchase,
    'lostPurchaseToken': lostPurchaseToken,
    'lostPurchaseTime': lostPurchaseTime,
    if (productType != null) 'productType': productType!.wireName,
    if (dynamicPriceToken != null) 'dynamicPriceToken': dynamicPriceToken,
    if (paywallId != null) 'paywallId': paywallId,
    if (paywallRevision != null) 'paywallRevision': paywallRevision,
  };
}

/// Discount-code validation input.
@immutable
class InappifyDiscountCodeRequest {
  const InappifyDiscountCodeRequest({
    required this.discountCode,
    this.offeringIdentifier,
    this.cancellation,
  });

  final String discountCode;
  final String? offeringIdentifier;
  final InappifyRequestCancellation? cancellation;

  Map<String, Object?> toMap() => <String, Object?>{
    'discountCode': discountCode,
    'offeringIdentifier': offeringIdentifier,
  };
}

/// One-time Identity Ticket exchange input.
///
/// The ticket is short-lived, single-use, and secret. It must never be stored
/// in the Flutter snapshot, included in errors, or written to logs.
@immutable
class InappifyIdentityTicketRequest {
  const InappifyIdentityTicketRequest({
    required this.identityTicket,
    this.cancellation,
  });

  final String identityTicket;
  final InappifyRequestCancellation? cancellation;

  Map<String, Object?> toMap() => <String, Object?>{
    'identityTicket': identityTicket,
  };
}

/// OTP challenge creation input.
@immutable
class InappifyOtpRequest {
  const InappifyOtpRequest({
    required this.phone,
    this.captchaKey,
    this.captchaAnswer,
    this.cancellation,
  });

  final String phone;
  final String? captchaKey;
  final String? captchaAnswer;
  final InappifyRequestCancellation? cancellation;

  Map<String, Object?> toMap() => <String, Object?>{
    'phone': phone,
    'captchaKey': captchaKey,
    'captchaAnswer': captchaAnswer,
  };
}

/// OTP challenge verification input.
@immutable
class InappifyOtpVerificationRequest {
  const InappifyOtpVerificationRequest({
    required this.challengeId,
    required this.code,
    this.cancellation,
  });

  final String challengeId;
  final String code;
  final InappifyRequestCancellation? cancellation;

  Map<String, Object?> toMap() => <String, Object?>{
    'challengeId': challengeId,
    'code': code,
  };
}

/// Runtime targeting context used for offering and placement evaluation.
@immutable
class InappifyTargetingContextRequest {
  const InappifyTargetingContextRequest({this.country, this.appVersion});

  final String? country;
  final String? appVersion;

  Map<String, Object?> toMap() => <String, Object?>{
    'country': country,
    'appVersion': appVersion,
  };
}

/// Offering selection input for a placement-aware backend.
@immutable
class InappifyCurrentOfferingRequest {
  InappifyCurrentOfferingRequest({
    this.placementIdentifier,
    this.forceRefresh = false,
    Map<String, Object?>? context,
    this.cancellation,
  }) : context = context == null
           ? null
           : Map<String, Object?>.unmodifiable(context);

  final String? placementIdentifier;
  final bool forceRefresh;
  final Map<String, Object?>? context;
  final InappifyRequestCancellation? cancellation;

  Map<String, Object?> toMap() => <String, Object?>{
    'placementIdentifier': placementIdentifier,
    'forceRefresh': forceRefresh,
    'context': context,
  };
}

/// Entitlement verification input.
@immutable
class InappifyEntitlementCheckRequest {
  const InappifyEntitlementCheckRequest({
    required this.identifier,
    this.forceRefresh = true,
    this.cancellation,
  });

  final String identifier;
  final bool forceRefresh;
  final InappifyRequestCancellation? cancellation;

  Map<String, Object?> toMap() => <String, Object?>{
    'identifier': identifier,
    'forceRefresh': forceRefresh,
  };
}

/// Custom attribute deletion input.
@immutable
class InappifyDeleteAttributesRequest {
  InappifyDeleteAttributesRequest({
    required List<String> keys,
    this.cancellation,
  }) : keys = List<String>.unmodifiable(keys);

  final List<String> keys;
  final InappifyRequestCancellation? cancellation;

  Map<String, Object?> toMap() => <String, Object?>{'keys': keys};
}

/// Reserved attribute capability query.
@immutable
class InappifyReservedAttributeCapabilityRequest {
  const InappifyReservedAttributeCapabilityRequest({required this.key});

  final String key;

  Map<String, Object?> toMap() => <String, Object?>{'key': key};
}

/// Authoritative payment-return polling input.
@immutable
class InappifyPaymentReturnRequest {
  const InappifyPaymentReturnRequest({
    required this.checkoutId,
    this.timeoutMs = 60000,
    this.intervalMs = 1500,
    this.cancellation,
  });

  final String checkoutId;
  final int timeoutMs;
  final int intervalMs;
  final InappifyRequestCancellation? cancellation;

  Map<String, Object?> toMap() => <String, Object?>{
    'checkoutId': checkoutId,
    'timeoutMs': timeoutMs,
    'intervalMs': intervalMs,
  };
}

/// Custom attribute update input.
@immutable
class InappifyAttributesRequest {
  InappifyAttributesRequest({
    required List<Attribute> attributes,
    this.idempotencyKey,
    this.cancellation,
  }) : attributes = List<Attribute>.unmodifiable(attributes);

  final List<Attribute> attributes;
  final String? idempotencyKey;
  final InappifyRequestCancellation? cancellation;

  Map<String, Object?> toMap() => <String, Object?>{
    'attributes': attributes
        .map(
          (attribute) => <String, Object?>{
            'key': attribute.key,
            'value': attribute.value,
          },
        )
        .toList(growable: false),
    'idempotencyKey': idempotencyKey,
  };
}

/// Reserved customer attributes supported by the compatibility façade.
enum InappifyReservedAttribute {
  email,
  apnsToken,
  displayName,
  fcmToken,
  idfa,
  idfv,
  ip,
  phoneNumber,
  campaign,
  keyword,
}

/// Reserved attribute update input.
@immutable
class InappifyReservedAttributeRequest {
  const InappifyReservedAttributeRequest({
    required this.attribute,
    required this.value,
    this.cancellation,
  });

  final InappifyReservedAttribute attribute;
  final String value;
  final InappifyRequestCancellation? cancellation;

  Map<String, Object?> toMap() => <String, Object?>{
    'attribute': _reservedAttributeWireName(attribute),
    'value': value,
  };
}

/// Checkout-status request used for one authoritative status read.
@immutable
class InappifyCheckoutStatusRequest {
  const InappifyCheckoutStatusRequest({
    required this.checkoutId,
    this.cancellation,
  });

  final String checkoutId;
  final InappifyRequestCancellation? cancellation;

  Map<String, Object?> toMap() => <String, Object?>{'checkoutId': checkoutId};
}

/// Cancellation-only input for network methods without semantic parameters.
@immutable
class InappifyNetworkRequest {
  const InappifyNetworkRequest({this.cancellation});

  final InappifyRequestCancellation? cancellation;

  Map<String, Object?> toMap() => const <String, Object?>{};
}

/// Request used to refresh customer or offering state.
@immutable
class InappifyRefreshRequest {
  const InappifyRefreshRequest({this.force = false, this.cancellation});

  final bool force;
  final InappifyRequestCancellation? cancellation;

  Map<String, Object?> toMap() => <String, Object?>{'force': force};
}

// Wire identifiers are mapped explicitly so renaming a Dart enum cannot
// silently change the native or JavaScript protocol.
String _marketWireName(Market market) {
  return switch (market) {
    Market.bazar => 'bazar',
    Market.myket => 'myket',
    Market.none => 'none',
  };
}

String _reservedAttributeWireName(InappifyReservedAttribute attribute) {
  return switch (attribute) {
    InappifyReservedAttribute.email => 'email',
    InappifyReservedAttribute.apnsToken => 'apnsToken',
    InappifyReservedAttribute.displayName => 'displayName',
    InappifyReservedAttribute.fcmToken => 'fcmToken',
    InappifyReservedAttribute.idfa => 'idfa',
    InappifyReservedAttribute.idfv => 'idfv',
    InappifyReservedAttribute.ip => 'ip',
    InappifyReservedAttribute.phoneNumber => 'phoneNumber',
    InappifyReservedAttribute.campaign => 'campaign',
    InappifyReservedAttribute.keyword => 'keyword',
  };
}
