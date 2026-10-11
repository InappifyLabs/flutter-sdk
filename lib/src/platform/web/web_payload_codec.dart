import 'dart:convert';

import 'package:inappify_sdk/models/attribute.dart';
import 'package:inappify_sdk/models/authentication_result.dart';
import 'package:inappify_sdk/models/captcha_challenge.dart';
import 'package:inappify_sdk/models/checkout_result.dart';
import 'package:inappify_sdk/models/customer_info.dart';
import 'package:inappify_sdk/models/offering_model.dart';
import 'package:inappify_sdk/models/offerings_model.dart';
import 'package:inappify_sdk/models/otp_challenge.dart';
import 'package:inappify_sdk/models/validate_discount_code_data.dart';

/// Converts documented Web SDK values into the package's compatibility
/// models without allowing JavaScript objects into shared layers.
abstract final class InappifyWebPayloadCodec {
  /// Decodes the current customer snapshot.
  static CustomerInfo customerInfo(Object? raw) {
    final source = requiredMap(raw, field: 'customerInfo');
    final normalized = Map<String, dynamic>.from(source);

    final entitlements = source['entitlements'];
    if (entitlements is Map) {
      normalized['entitlements'] = entitlements.entries
          .map((entry) {
            final value = requiredMap(entry.value, field: 'entitlement');
            return _normalizeEntitlement(<String, dynamic>{
              'identifier': entry.key.toString(),
              ...value,
            });
          })
          .toList(growable: false);
    } else if (entitlements is List) {
      normalized['entitlements'] = entitlements
          .map(
            (value) =>
                _normalizeEntitlement(requiredMap(value, field: 'entitlement')),
          )
          .toList(growable: false);
    } else if (entitlements != null) {
      throw const FormatException(
        'Web customerInfo entitlements must be a list or map.',
      );
    }

    final attributes = source['attributes'];
    if (attributes is Map) {
      normalized['attributes'] = attributes.entries
          .map(
            (entry) => <String, Object?>{
              'key': entry.key.toString(),
              'value': entry.value?.toString(),
            },
          )
          .toList(growable: false);
    }

    final transactions = source['transactions'];
    if (transactions is List) {
      normalized['transactions'] = transactions
          .map(
            (value) =>
                _normalizeTransaction(requiredMap(value, field: 'transaction')),
          )
          .toList(growable: false);
    }

    _copyAlias(normalized, source, 'originalAppUserId', 'original_app_user_id');
    _copyAlias(normalized, source, 'firstSeen', 'first_seen');
    _copyAlias(normalized, source, 'requestDate', 'request_date');
    _copyAlias(
      normalized,
      source,
      'latestExpirationDate',
      'latest_expiration_date',
    );
    _copyAlias(normalized, source, 'hasUsedTrial', 'has_used_trial');
    return CustomerInfo.fromJson(normalized);
  }

  /// Decodes an offerings collection returned by `getOfferings()`.
  static OfferingsModel offerings(Object? raw) {
    final source = raw is List
        ? <String, dynamic>{'offerings': raw}
        : requiredMap(raw, field: 'offerings');
    final rawItems = source['offerings'] ?? source['all'] ?? source['items'];
    final current = optionalMap(source['current'], field: 'offerings.current');
    final items = <Map<String, dynamic>>[];

    if (rawItems is List) {
      for (final value in rawItems) {
        items.add(_normalizeOffering(requiredMap(value, field: 'offering')));
      }
    } else if (rawItems != null) {
      throw const FormatException('Web offerings items must be a list.');
    }

    if (current != null) {
      final normalizedCurrent = _normalizeOffering(current);
      final currentIdentifier = normalizedCurrent['identifier'];
      final match = items.indexWhere(
        (item) => item['identifier'] == currentIdentifier,
      );
      if (match < 0) {
        items.add(<String, dynamic>{...normalizedCurrent, 'isDefault': true});
      } else if (!items.any((item) => item['isDefault'] == true)) {
        items[match] = <String, dynamic>{...items[match], 'isDefault': true};
      }
    }

    final rules = source['rules'];
    return OfferingsModel.fromJson(<String, dynamic>{
      'offerings': items,
      'rules': rules is List
          ? rules
                .map(
                  (value) => _normalizeRule(
                    requiredMap(value, field: 'targetingRule'),
                  ),
                )
                .toList(growable: false)
          : null,
      'forceVersion': source['forceVersion'] ?? source['force_version'],
      'fetchedAt': source['fetchedAt'] ?? source['fetched_at'],
    });
  }

  /// Decodes one placement-selected offering.
  static OfferingModel offering(Object? raw) {
    return OfferingModel.fromJson(
      _normalizeOffering(requiredMap(raw, field: 'offering')),
    );
  }

  /// Decodes the token-free authentication result.
  static InappifyAuthenticationResult authentication(Object? raw) {
    return InappifyAuthenticationResult.fromMap(
      requiredMap(raw, field: 'authentication'),
    );
  }

  /// Decodes an OTP challenge.
  static InappifyOtpChallenge otpChallenge(Object? raw) {
    return InappifyOtpChallenge.fromMap(
      requiredMap(raw, field: 'otpChallenge'),
    );
  }

  /// Decodes the CAPTCHA payload used by the documented Web OTP flow.
  static InappifyCaptchaChallenge captchaChallenge(Object? raw) {
    return InappifyCaptchaChallenge.fromMap(
      requiredMap(raw, field: 'captchaChallenge'),
    );
  }

  /// Decodes a checkout creation or payment-return response.
  static InappifyCheckoutResult checkout(Object? raw) {
    final source = requiredMap(raw, field: 'checkoutResult');
    final nextAction = optionalMap(
      source['nextAction'] ?? source['next_action'],
      field: 'checkoutResult.nextAction',
    );
    final url = nextAction?['url'];
    if (url != null) {
      if (url is! String) {
        throw const FormatException('Web checkout URL must be a string.');
      }
      final parsed = Uri.tryParse(url);
      if (parsed == null ||
          !parsed.hasAuthority ||
          (parsed.scheme != 'http' && parsed.scheme != 'https')) {
        throw const FormatException(
          'Web checkout URL must be an absolute HTTP(S) URL.',
        );
      }
    }
    return InappifyCheckoutResult.fromMap(source);
  }

  /// Decodes discount-code validation while accepting Web camel-case fields.
  static ValidateDiscountCodeData discountValidation(Object? raw) {
    final source = requiredMap(raw, field: 'discountValidation');
    final normalized = Map<String, dynamic>.from(source);
    final discount = optionalMap(
      source['discount'],
      field: 'discountValidation.discount',
    );
    if (discount != null) {
      final code = discount['code'];
      final isValid = discount['isValid'] ?? discount['is_valid'];
      final percent = discount['percent'];
      if (code is! String ||
          isValid is! bool ||
          (percent != null && percent is! num)) {
        throw const FormatException(
          'Web discount validation has invalid fields.',
        );
      }
      final rawOffering = source['offering'];
      if (rawOffering == null) {
        throw const FormatException(
          'Web discount validation is missing its offering.',
        );
      }
      normalized['offering'] = _normalizeOffering(
        requiredMap(rawOffering, field: 'discountValidation.offering'),
      );
      normalized['code'] = code;
      normalized['is_valid'] = isValid;
      normalized['percent'] = percent;
    } else {
      _copyAlias(normalized, source, 'is_valid', 'isValid');
      _copyAlias(normalized, source, 'error_code', 'errorCode');
      _copyAlias(normalized, source, 'discount_id', 'discountId');
      _copyAlias(normalized, source, 'discount_code_id', 'discountCodeId');
      _copyAlias(normalized, source, 'payment_links', 'paymentLinks');
    }
    return ValidateDiscountCodeData.fromJson(normalized);
  }

  /// Decodes a strict JavaScript boolean.
  static bool boolean(Object? raw, {required String field}) {
    if (raw is bool) return raw;
    throw FormatException('Web $field must be a boolean.');
  }

  /// Converts an attribute list to the map accepted by `updateAttributes`.
  static Map<String, Object?> attributeMap(List<Attribute> attributes) {
    final result = <String, Object?>{};
    for (final attribute in attributes) {
      final key = attribute.key;
      if (key == null || key.isEmpty) {
        throw const FormatException(
          'Web attribute keys must be non-empty strings.',
        );
      }
      result[key] = attribute.value;
    }
    return result;
  }

  /// Converts attributes to the array accepted by `syncAttributes`.
  static List<Map<String, Object?>> attributeList(List<Attribute> attributes) {
    return attributes
        .map((attribute) {
          final key = attribute.key;
          if (key == null || key.isEmpty) {
            throw const FormatException(
              'Web attribute keys must be non-empty strings.',
            );
          }
          return <String, Object?>{'key': key, 'value': attribute.value};
        })
        .toList(growable: false);
  }

  /// Returns a recursively string-keyed map or throws a sanitized error.
  static Map<String, dynamic> requiredMap(
    Object? raw, {
    required String field,
  }) {
    final value = optionalMap(raw, field: field);
    if (value == null) throw FormatException('Web $field must be a map.');
    return value;
  }

  /// Returns a recursively string-keyed map when [raw] is non-null.
  static Map<String, dynamic>? optionalMap(
    Object? raw, {
    required String field,
  }) {
    if (raw == null) return null;
    if (raw is! Map) throw FormatException('Web $field must be a map.');
    return raw.map<String, dynamic>(
      (key, value) =>
          MapEntry<String, dynamic>(key.toString(), _normalize(value)),
    );
  }

  static Map<String, dynamic> _normalizeEntitlement(
    Map<String, dynamic> source,
  ) {
    final result = Map<String, dynamic>.from(source);
    _copyAlias(result, source, 'is_active', 'isActive');
    _copyAlias(result, source, 'is_sandbox', 'isSandbox');
    _copyAlias(result, source, 'period_type', 'periodType');
    _copyAlias(result, source, 'purchase_date', 'purchaseDate');
    _copyAlias(result, source, 'expiration_date', 'expirationDate');
    _copyAlias(result, source, 'ownership_type', 'ownershipType');
    _copyAlias(result, source, 'entitlement_type', 'entitlementType');
    _copyAlias(
      result,
      source,
      'purchase_store_ref_hash',
      'purchaseStoreRefHash',
    );
    _copyAlias(result, source, 'purchase_store_time', 'purchaseStoreTime');
    return result;
  }

  static Map<String, dynamic> _normalizeTransaction(
    Map<String, dynamic> source,
  ) {
    final result = Map<String, dynamic>.from(source);
    _copyAlias(result, source, 'isCryptoGate', 'is_crypto_gate');
    _copyAlias(result, source, 'packageName', 'package_name');
    _copyAlias(result, source, 'trackingNumber', 'tracking_number');
    _copyAlias(result, source, 'transactionDate', 'transaction_date');
    _copyAlias(result, source, 'storePurchaseRefId', 'store_purchase_ref_id');
    _copyAlias(result, source, 'isTrial', 'is_trial');
    return result;
  }

  static Map<String, dynamic> _normalizeOffering(Map<String, dynamic> source) {
    final result = Map<String, dynamic>.from(source);
    _copyAlias(result, source, 'isDefault', 'is_default');
    _copyAlias(result, source, 'serverDescription', 'server_description');
    _copyAlias(result, source, 'trialDays', 'trial_days');
    final packages = source['packages'];
    if (packages is List) {
      result['packages'] = packages
          .map((value) {
            final package = requiredMap(value, field: 'package');
            final normalized = Map<String, dynamic>.from(package);
            _copyAlias(normalized, package, 'packageType', 'package_type');
            _copyAlias(
              normalized,
              package,
              'discountPercent',
              'discount_percent',
            );
            final product = optionalMap(package['product'], field: 'product');
            if (product != null) {
              normalized['product'] = _normalizeProduct(product);
            }
            return normalized;
          })
          .toList(growable: false);
    }
    return result;
  }

  static Map<String, dynamic> _normalizeProduct(Map<String, dynamic> source) {
    final result = Map<String, dynamic>.from(source);
    _copyAlias(result, source, 'dollarPrice', 'dollar_price');
    _copyAlias(result, source, 'trialDays', 'trial_days');
    final prices = source['prices'] ?? source['price'];
    if (prices is List) {
      result['prices'] = prices
          .map((value) {
            final price = requiredMap(value, field: 'price');
            final normalized = Map<String, dynamic>.from(price);
            _copyAlias(normalized, price, 'price', 'amount');
            _copyAlias(normalized, price, 'originPrice', 'originalAmount');
            _copyAlias(normalized, price, 'originPrice', 'originAmount');
            _copyAlias(normalized, price, 'originalAmount', 'originPrice');
            _copyAlias(normalized, price, 'discountAmount', 'discount_amount');
            _copyAlias(normalized, price, 'app_product_id', 'appProductId');
            _copyAlias(normalized, price, 'created_at', 'createdAt');
            _copyAlias(normalized, price, 'updated_at', 'updatedAt');
            return normalized;
          })
          .toList(growable: false);
    }
    return result;
  }

  static Map<String, dynamic> _normalizeRule(Map<String, dynamic> source) {
    final result = Map<String, dynamic>.from(source);
    _copyAlias(result, source, 'default_offering', 'defaultOfferingIdentifier');
    final conditions = source['conditions'];
    if (conditions is List) {
      result['conditions'] = conditions
          .map((value) {
            final condition = requiredMap(value, field: 'targetingCondition');
            final normalized = Map<String, dynamic>.from(condition);
            final context = normalized['context'];
            if (context != null && context is! String) {
              normalized['context'] = context.toString();
            }
            normalized['value'] = jsonEncode(normalized['value']);
            return normalized;
          })
          .toList(growable: false);
    }
    final placements = optionalMap(source['placements'], field: 'placements');
    if (placements != null) {
      final normalizedPlacements = Map<String, dynamic>.from(placements);
      _copyAlias(
        normalizedPlacements,
        placements,
        'fallback_offering_id',
        'fallbackOfferingIdentifier',
      );
      final placementOfferings =
          placements['placement_offerings'] ?? placements['offerings'];
      if (placementOfferings is List) {
        normalizedPlacements['placement_offerings'] = placementOfferings
            .map((value) {
              final placement = requiredMap(value, field: 'placementOffering');
              final normalized = Map<String, dynamic>.from(placement);
              _copyAlias(
                normalized,
                placement,
                'placement_identifier',
                'placementIdentifier',
              );
              _copyAlias(
                normalized,
                placement,
                'offering_identifier',
                'offeringIdentifier',
              );
              return normalized;
            })
            .toList(growable: false);
      }
      result['placements'] = normalizedPlacements;
    }
    return result;
  }

  static void _copyAlias(
    Map<String, dynamic> target,
    Map<String, dynamic> source,
    String targetKey,
    String alias,
  ) {
    if (!target.containsKey(targetKey) && source.containsKey(alias)) {
      target[targetKey] = source[alias];
    }
  }

  static Object? _normalize(Object? value) {
    if (value is Map) {
      return value.map<String, Object?>(
        (key, item) =>
            MapEntry<String, Object?>(key.toString(), _normalize(item)),
      );
    }
    if (value is List) {
      return value.map<Object?>(_normalize).toList(growable: false);
    }
    if (value == null || value is bool || value is num || value is String) {
      return value;
    }
    throw const FormatException('Web payload contains an unsupported value.');
  }
}
