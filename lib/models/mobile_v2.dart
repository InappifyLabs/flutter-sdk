import 'package:flutter/foundation.dart';

/// Mobile backend selection. Upgrading the package never switches protocols.
enum InappifyMobileProtocol { goV2 }

/// CustomerInfo cache policy; cachedOrFetched is the default.
enum InappifyCacheFetchPolicy {
  cacheOnly,
  fetchCurrent,
  notStaleCachedOrCurrent,
  cachedOrFetched,
}

enum InappifyDeliveryResult { delivered, retryLater }

typedef InappifyConsumableDeliveryHandler =
    Future<InappifyDeliveryResult> Function(
      InappifyConsumableDelivery delivery,
    );

enum InappifyFetchPolicy { cacheOnly, cacheFirst, networkFirst, networkOnly }

enum InappifyProductType {
  consumable('CONSUMABLE'),
  nonConsumable('NON_CONSUMABLE'),
  subscription('SUBSCRIPTION');

  const InappifyProductType(this.wireName);
  final String wireName;
}

enum InappifyStorePurchaseStatus {
  processing('PROCESSING'),
  completed('COMPLETED'),
  restored('RESTORED'),
  alreadyProcessed('ALREADY_PROCESSED'),
  deliveryRequired('DELIVERY_REQUIRED'),
  consumeRequired('CONSUME_REQUIRED'),
  rejected('REJECTED');

  const InappifyStorePurchaseStatus(this.wireName);
  final String wireName;

  static InappifyStorePurchaseStatus fromWire(String value) =>
      values.firstWhere(
        (entry) => entry.wireName == value,
        orElse: () =>
            throw const FormatException('Unknown mobile purchase status.'),
      );
}

enum InappifyDeliverySource {
  direct('DIRECT'),
  bazaar('BAZAAR'),
  myket('MYKET');

  const InappifyDeliverySource(this.wireName);
  final String wireName;
}

/// Additional mobile workflow state; never substitutes for legacy DONE.
@immutable
class InappifyMobilePurchaseData {
  const InappifyMobilePurchaseData({
    this.storePurchaseStatus,
    this.deliveryId,
    this.verificationRequestId,
    this.alreadyProcessed = false,
    this.productIdentifier,
    this.offeringIdentifier,
    this.packageIdentifier,
    this.idempotencyKey,
    this.market,
  });

  final InappifyStorePurchaseStatus? storePurchaseStatus;
  final int? deliveryId;
  final String? verificationRequestId;
  final bool alreadyProcessed;
  final String? productIdentifier, offeringIdentifier, packageIdentifier;
  final String? idempotencyKey, market;

  bool get requiresDelivery =>
      storePurchaseStatus == InappifyStorePurchaseStatus.deliveryRequired;

  factory InappifyMobilePurchaseData.fromMap(Map<String, dynamic> map) {
    final status = _optionalString(map, 'storePurchaseStatus');
    final deliveryId = map['deliveryId'];
    return InappifyMobilePurchaseData(
      storePurchaseStatus: status == null
          ? null
          : InappifyStorePurchaseStatus.fromWire(status),
      deliveryId: deliveryId == null
          ? null
          : _count(deliveryId, positive: true),
      verificationRequestId: _optionalString(map, 'verificationRequestId'),
      alreadyProcessed: _boolean(map['alreadyProcessed'] ?? false),
      productIdentifier: _optionalString(map, 'productIdentifier'),
      offeringIdentifier: _optionalString(map, 'offeringIdentifier'),
      packageIdentifier: _optionalString(map, 'packageIdentifier'),
      idempotencyKey: _optionalString(map, 'idempotencyKey'),
      market: _optionalString(map, 'market'),
    );
  }

  Map<String, Object?> toMap() => {
    'storePurchaseStatus': storePurchaseStatus?.wireName,
    'deliveryId': deliveryId,
    'verificationRequestId': verificationRequestId,
    'alreadyProcessed': alreadyProcessed,
    'productIdentifier': productIdentifier,
    'offeringIdentifier': offeringIdentifier,
    'packageIdentifier': packageIdentifier,
    'idempotencyKey': idempotencyKey,
    'market': market,
  };
}

/// Grant only in a durable, unique host inventory transaction, then confirm.
/// Scope the uniqueness key by app/customer/source as well as [deliveryId].
@immutable
class InappifyConsumableDelivery {
  const InappifyConsumableDelivery({
    required this.deliveryId,
    required this.productIdentifier,
    required this.source,
    this.transactionIdentifier,
  });

  final int deliveryId;
  final String productIdentifier;
  final String? transactionIdentifier;
  final InappifyDeliverySource source;

  factory InappifyConsumableDelivery.fromMap(Map<String, dynamic> map) =>
      InappifyConsumableDelivery(
        deliveryId: _count(map['deliveryId'], positive: true),
        productIdentifier: _requiredString(map, 'productIdentifier'),
        transactionIdentifier: _optionalString(map, 'transactionIdentifier'),
        source: InappifyDeliverySource.values.firstWhere(
          (value) => value.wireName == map['source'],
          orElse: () => throw const FormatException('Unknown delivery source.'),
        ),
      );

  Map<String, Object?> toMap() => {
    'deliveryId': deliveryId,
    'productIdentifier': productIdentifier,
    'transactionIdentifier': transactionIdentifier,
    'source': source.wireName,
  };
}

@immutable
class InappifyConsumableSyncResult {
  InappifyConsumableSyncResult({
    required this.discoveredCount,
    required this.completedCount,
    required List<InappifyConsumableDelivery> pendingDeliveries,
  }) : pendingDeliveries = List.unmodifiable(pendingDeliveries);

  final int discoveredCount, completedCount;
  final List<InappifyConsumableDelivery> pendingDeliveries;

  factory InappifyConsumableSyncResult.fromMap(Map<String, dynamic> map) {
    final discovered = _count(map['discoveredCount']);
    final completed = _count(map['completedCount']);
    final pending = map['pendingDeliveries'];
    if (completed > discovered || pending is! List) {
      throw const FormatException('Invalid consumable sync result.');
    }
    return InappifyConsumableSyncResult(
      discoveredCount: discovered,
      completedCount: completed,
      pendingDeliveries: pending.map((entry) {
        if (entry is! Map) throw const FormatException('Invalid delivery.');
        return InappifyConsumableDelivery.fromMap(
          Map<String, dynamic>.from(entry),
        );
      }).toList(),
    );
  }

  Map<String, Object?> toMap() => {
    'discoveredCount': discoveredCount,
    'completedCount': completedCount,
    'pendingDeliveries': pendingDeliveries
        .map((value) => value.toMap())
        .toList(),
  };
}

@immutable
class InappifyRestoreResult {
  const InappifyRestoreResult({
    required this.restoredCount,
    required this.alreadyProcessedCount,
    required this.failedCount,
  });
  final int restoredCount, alreadyProcessedCount, failedCount;
  int get totalCount => restoredCount + alreadyProcessedCount + failedCount;

  factory InappifyRestoreResult.fromMap(Map<String, dynamic> map) =>
      InappifyRestoreResult(
        restoredCount: _count(map['restoredCount']),
        alreadyProcessedCount: _count(map['alreadyProcessedCount']),
        failedCount: _count(map['failedCount']),
      );
  Map<String, Object?> toMap() => {
    'restoredCount': restoredCount,
    'alreadyProcessedCount': alreadyProcessedCount,
    'failedCount': failedCount,
  };
}

/// Filtered, opt-in HTTP diagnostics. Never enable raw credential logging.
@immutable
class InappifyHttpTrace {
  InappifyHttpTrace({
    required this.method,
    required this.endpoint,
    Map<String, String> requestHeaders = const {},
    this.requestBody,
    this.statusCode,
    Map<String, String> responseHeaders = const {},
    this.responseBody,
    this.requestId,
    required this.durationMillis,
    this.failure,
  }) : requestHeaders = Map.unmodifiable(requestHeaders),
       responseHeaders = Map.unmodifiable(responseHeaders);

  final String method, endpoint;
  final Map<String, String> requestHeaders, responseHeaders;
  final String? requestBody, responseBody, requestId, failure;
  final int? statusCode;
  final int durationMillis;
  bool get containsSensitiveData => false;

  factory InappifyHttpTrace.fromMap(Map<String, dynamic> map) {
    if (map['containsSensitiveData'] == true) {
      throw const FormatException('Raw HTTP traces are not supported.');
    }
    return InappifyHttpTrace(
      method: _requiredString(map, 'method'),
      endpoint: _requiredString(map, 'endpoint'),
      requestHeaders: Map<String, String>.from(
        map['requestHeaders'] as Map? ?? {},
      ),
      requestBody: _optionalString(map, 'requestBody'),
      statusCode: map['statusCode'] == null ? null : _count(map['statusCode']),
      responseHeaders: Map<String, String>.from(
        map['responseHeaders'] as Map? ?? {},
      ),
      responseBody: _optionalString(map, 'responseBody'),
      requestId: _optionalString(map, 'requestId'),
      durationMillis: _count(map['durationMillis']),
      failure: _optionalString(map, 'failure'),
    );
  }
}

int _count(Object? value, {bool positive = false}) {
  if (value is! int || value < (positive ? 1 : 0)) {
    throw const FormatException('Expected an exact non-negative integer.');
  }
  return value;
}

bool _boolean(Object? value) {
  if (value is! bool) throw const FormatException('Expected a boolean.');
  return value;
}

String _requiredString(Map<String, dynamic> map, String key) {
  final value = _optionalString(map, key);
  if (value == null || value.trim().isEmpty) {
    throw FormatException('Missing $key.');
  }
  return value;
}

String? _optionalString(Map<String, dynamic> map, String key) {
  final value = map[key];
  if (value != null && value is! String) {
    throw FormatException('Invalid $key.');
  }
  return value as String?;
}
