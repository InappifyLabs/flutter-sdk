import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:inappify_sdk/models/customer_info.dart';
import 'package:inappify_sdk/models/mobile_v2.dart';
import 'package:inappify_sdk/models/offerings_model.dart';
import 'package:inappify_sdk/session_state.dart';

/// Complete Flutter-visible state returned after a platform operation.
///
/// Backends own their persistence, while the coordinator mirrors this snapshot
/// for the synchronous legacy getters exposed by `InappifySdk`. A backend must
/// return a complete snapshot rather than a partial patch so logout and user
/// changes can explicitly clear stale values.
@immutable
class InappifySdkSnapshot {
  const InappifySdkSnapshot({
    this.accessToken = '',
    this.apiKey = '',
    this.customerInfo,
    this.offerings,
    this.storeInfo,
    this.forceVersion = 1,
    this.appId,
    this.country = 'IR',
    this.versionName = '',
    this.versionCode,
    this.sdkVersion,
    this.sessionState = InappifySessionState.unknown,
    this.persistenceMode = InappifySessionPersistenceMode.unknown,
    this.failedToLoadOfferings = false,
    this.failedToLoadCustomerInfo = false,
    this.revision,
    this.isConfigured,
    this.isAuthenticated,
    this.appUserIdentifier,
    this.storePlatform,
    this.market,
    this.mobileProtocol,
    this.isLogoutPending,
  });

  final String? accessToken;
  final String? apiKey;
  final CustomerInfo? customerInfo;
  final OfferingsModel? offerings;
  final String? storeInfo;
  final int? forceVersion;
  final int? appId;
  final String country;
  final String versionName;
  final int? versionCode;

  /// Version of the backend SDK that owns the current session.
  final String? sdkVersion;

  /// Token-free lifecycle state reported by the session-owning backend.
  final InappifySessionState sessionState;

  /// Whether the active session can survive a process or page reload.
  final InappifySessionPersistenceMode persistenceMode;

  final bool failedToLoadOfferings;
  final bool failedToLoadCustomerInfo;

  /// Mobile state and ordered Web mirror revision; null for older adapters.
  final int? revision, storePlatform;
  final bool? isConfigured, isAuthenticated, isLogoutPending;
  final String? appUserIdentifier, market;
  final InappifyMobileProtocol? mobileProtocol;

  /// Encodes this snapshot using only standard message-codec values.
  Map<String, Object?> toMap() => <String, Object?>{
    'accessToken': accessToken,
    'apiKey': apiKey,
    'customerInfo': _toCodecSafeMap(customerInfo),
    'offerings': _toCodecSafeMap(offerings),
    'storeInfo': storeInfo,
    'forceVersion': forceVersion,
    'appId': appId,
    'country': country,
    'versionName': versionName,
    'versionCode': versionCode,
    'sdkVersion': sdkVersion,
    'sessionState': sessionState.wireName,
    'persistenceMode': persistenceMode.wireName,
    'failedToLoadOfferings': failedToLoadOfferings,
    'failedToLoadCustomerInfo': failedToLoadCustomerInfo,
    if (revision != null) 'revision': revision,
    if (isConfigured != null) 'isConfigured': isConfigured,
    if (isAuthenticated != null) 'isAuthenticated': isAuthenticated,
    if (appUserIdentifier != null) 'appUserIdentifier': appUserIdentifier,
    if (storePlatform != null) 'storePlatform': storePlatform,
    if (market != null) 'market': market,
    if (mobileProtocol != null) 'mobileProtocol': mobileProtocol!.name,
    if (isLogoutPending != null) 'isLogoutPending': isLogoutPending,
  };

  /// Decodes a complete snapshot received from a platform adapter.
  factory InappifySdkSnapshot.fromMap(Map<String, dynamic> map) {
    const requiredKeys = <String>{
      'accessToken',
      'apiKey',
      'customerInfo',
      'offerings',
      'storeInfo',
      'forceVersion',
      'appId',
      'country',
      'versionName',
      'versionCode',
      'failedToLoadOfferings',
      'failedToLoadCustomerInfo',
    };
    for (final key in requiredKeys) {
      if (!map.containsKey(key)) {
        throw FormatException('SDK snapshot is missing $key.');
      }
    }

    final customerMap = _asStringMap(map['customerInfo']);
    final offeringsMap = _asStringMap(map['offerings']);
    if (map['customerInfo'] != null && customerMap == null) {
      throw const FormatException(
        'SDK snapshot customerInfo must be a map or null.',
      );
    }
    if (map['offerings'] != null && offeringsMap == null) {
      throw const FormatException(
        'SDK snapshot offerings must be a map or null.',
      );
    }

    final country = map['country'];
    final versionName = map['versionName'];
    final failedToLoadOfferings = map['failedToLoadOfferings'];
    final failedToLoadCustomerInfo = map['failedToLoadCustomerInfo'];
    if (country is! String || versionName is! String) {
      throw const FormatException(
        'SDK snapshot country and versionName must be strings.',
      );
    }
    if (failedToLoadOfferings is! bool || failedToLoadCustomerInfo is! bool) {
      throw const FormatException(
        'SDK snapshot failure flags must be bool values.',
      );
    }

    return InappifySdkSnapshot(
      accessToken: _nullableString(map['accessToken'], 'accessToken'),
      apiKey: _nullableString(map['apiKey'], 'apiKey'),
      customerInfo: customerMap == null
          ? null
          : CustomerInfo.fromJson(customerMap),
      offerings: offeringsMap == null
          ? null
          : OfferingsModel.fromJson(offeringsMap),
      storeInfo: _nullableString(map['storeInfo'], 'storeInfo'),
      forceVersion: _nullableInt(map['forceVersion'], 'forceVersion'),
      appId: _nullableInt(map['appId'], 'appId'),
      country: country,
      versionName: versionName,
      versionCode: _nullableInt(map['versionCode'], 'versionCode'),
      sdkVersion: _nullableString(map['sdkVersion'], 'sdkVersion'),
      // These fields are additive so protocol-v1 native adapters that have not
      // adopted the token-free session contract remain decodable.
      sessionState: InappifySessionState.fromWire(map['sessionState']),
      persistenceMode: InappifySessionPersistenceMode.fromWire(
        map['persistenceMode'],
      ),
      failedToLoadOfferings: failedToLoadOfferings,
      failedToLoadCustomerInfo: failedToLoadCustomerInfo,
      revision: _exactInt(map['revision'], 'revision'),
      storePlatform: _exactInt(map['storePlatform'], 'storePlatform'),
      isConfigured: _nullableBool(map['isConfigured'], 'isConfigured'),
      isAuthenticated: _nullableBool(map['isAuthenticated'], 'isAuthenticated'),
      isLogoutPending: _nullableBool(map['isLogoutPending'], 'isLogoutPending'),
      appUserIdentifier: _nullableString(
        map['appUserIdentifier'],
        'appUserIdentifier',
      ),
      market: _nullableString(map['market'], 'market'),
      mobileProtocol: map['mobileProtocol'] == null
          ? null
          : InappifyMobileProtocol.values.firstWhere(
              (value) => value.name == map['mobileProtocol'],
              orElse: () =>
                  throw const FormatException('Unknown mobile protocol.'),
            ),
    );
  }

  static int? _nullableInt(Object? value, String fieldName) {
    if (value == null) return null;
    if (value is num) return value.toInt();
    throw FormatException('SDK snapshot $fieldName must be numeric or null.');
  }

  static int? _exactInt(Object? value, String name) {
    if (value == null || value is int && value >= 0) return value as int?;
    throw FormatException(
      'SDK snapshot $name must be an exact non-negative integer.',
    );
  }

  static bool? _nullableBool(Object? value, String name) {
    if (value == null || value is bool) return value as bool?;
    throw FormatException('SDK snapshot $name must be a bool.');
  }

  static String? _nullableString(Object? value, String fieldName) {
    if (value == null || value is String) return value as String?;
    throw FormatException('SDK snapshot $fieldName must be a string or null.');
  }

  static Map<String, Object?>? _toCodecSafeMap(Object? value) {
    if (value == null) return null;
    final decoded = jsonDecode(jsonEncode(value));
    return _asObjectMap(decoded);
  }

  static Map<String, dynamic>? _asStringMap(Object? value) {
    if (value is! Map) return null;
    return value.map<String, dynamic>(
      (key, item) => MapEntry<String, dynamic>(key.toString(), item),
    );
  }

  static Map<String, Object?>? _asObjectMap(Object? value) {
    final map = _asStringMap(value);
    return map?.cast<String, Object?>();
  }
}
