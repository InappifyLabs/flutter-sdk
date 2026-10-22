import 'package:inappify_sdk/src/platform/channel/channel_contract.dart';
import 'package:inappify_sdk/src/platform/contracts/platform_event.dart';
import 'package:inappify_sdk/src/platform/contracts/sdk_failure.dart';
import 'package:inappify_sdk/src/platform/contracts/sdk_snapshot.dart';
import 'package:inappify_sdk/models/purchase_attempt.dart';

/// Decoded response envelope returned by a platform bridge.
class InappifyChannelResponse {
  const InappifyChannelResponse({
    required this.isSuccess,
    required this.requestId,
    this.data,
    this.snapshot,
    this.failure,
  });

  final bool isSuccess;
  final String requestId;
  final Map<String, dynamic>? data;
  final InappifySdkSnapshot? snapshot;
  final InappifyFailure? failure;
}

/// Converts StandardMessageCodec values into typed protocol objects.
abstract final class InappifyChannelCodec {
  /// Recursively normalizes platform maps to string-keyed Dart maps.
  static Object? normalize(Object? value) {
    if (value is Map) {
      return value.map<String, Object?>(
        (key, item) =>
            MapEntry<String, Object?>(key.toString(), normalize(item)),
      );
    }
    if (value is List) {
      return value.map<Object?>((item) => normalize(item)).toList();
    }
    return value;
  }

  /// Decodes and validates a protocol-v1 response envelope.
  static InappifyChannelResponse decodeResponse(
    Object? raw, {
    required String expectedRequestId,
  }) {
    final normalized = normalize(raw);
    if (normalized is! Map<String, Object?>) {
      throw const FormatException('Platform response must be a map.');
    }

    final protocolVersion = _protocolVersion(normalized, valueName: 'response');
    if (protocolVersion != InappifyChannelContract.protocolVersion) {
      throw FormatException(
        'Unsupported platform protocol version: $protocolVersion.',
      );
    }

    final requestId = normalized[InappifyChannelContract.requestIdKey];
    if (requestId is! String) {
      throw const FormatException(
        'Platform response requestId must be a string.',
      );
    }
    if (requestId != expectedRequestId) {
      throw const FormatException('Platform response requestId mismatch.');
    }

    final ok = normalized[InappifyChannelContract.okKey];
    if (ok is! bool) {
      throw const FormatException('Platform response ok must be a bool.');
    }

    final data = _optionalMap(
      normalized[InappifyChannelContract.dataKey],
      fieldName: InappifyChannelContract.dataKey,
    );
    final snapshotMap = _optionalMap(
      normalized[InappifyChannelContract.snapshotKey],
      fieldName: InappifyChannelContract.snapshotKey,
    );
    final snapshot = snapshotMap == null
        ? null
        : InappifySdkSnapshot.fromMap(snapshotMap);

    if (ok) {
      return InappifyChannelResponse(
        isSuccess: true,
        requestId: requestId,
        data: data,
        snapshot: snapshot,
      );
    }

    final error = _requiredMap(
      normalized[InappifyChannelContract.errorKey],
      fieldName: InappifyChannelContract.errorKey,
    );
    final rawCode = error[InappifyChannelContract.errorCodeKey];
    final rawMessage = error[InappifyChannelContract.errorMessageKey];
    final rawRetryable = error[InappifyChannelContract.errorRetryableKey];
    if (rawCode is! String || rawMessage is! String || rawRetryable is! bool) {
      throw const FormatException(
        'Platform response error fields have invalid types.',
      );
    }
    final failureCode = _failureCode(rawCode);
    final details =
        _optionalMap(
          error[InappifyChannelContract.errorDetailsKey],
          fieldName: InappifyChannelContract.errorDetailsKey,
        ) ??
        const <String, dynamic>{};

    return InappifyChannelResponse(
      isSuccess: false,
      requestId: requestId,
      snapshot: snapshot,
      failure: InappifyFailure(
        code: failureCode,
        message: rawMessage,
        isRetryable: rawRetryable,
        details: details.cast<String, Object?>(),
      ),
    );
  }

  /// Decodes an asynchronous protocol-v1 EventChannel envelope.
  static InappifyPlatformEvent decodeEvent(Object? raw) {
    final normalized = normalize(raw);
    if (normalized is! Map<String, Object?>) {
      throw const FormatException('Platform event must be a map.');
    }

    final protocolVersion = _protocolVersion(normalized, valueName: 'event');
    if (protocolVersion != InappifyChannelContract.protocolVersion) {
      throw FormatException(
        'Unsupported platform event protocol version: $protocolVersion.',
      );
    }

    final rawType = normalized[InappifyChannelContract.eventTypeKey];
    if (rawType is! String) {
      throw const FormatException('Platform event type must be a string.');
    }
    final type = _eventType(rawType);

    final rawRequestId = normalized[InappifyChannelContract.requestIdKey];
    if (rawRequestId != null && rawRequestId is! String) {
      throw const FormatException(
        'Platform event requestId must be a string or null.',
      );
    }
    final snapshotMap = _optionalMap(
      normalized[InappifyChannelContract.snapshotKey],
      fieldName: InappifyChannelContract.snapshotKey,
    );
    final data =
        _optionalMap(
          normalized[InappifyChannelContract.dataKey],
          fieldName: InappifyChannelContract.dataKey,
        ) ??
        const <String, dynamic>{};

    final rawAttempt = data['purchaseAttempt'];
    final attempt = rawAttempt == null
        ? null
        : InappifyPurchaseAttempt.fromMap(
            _requiredMap(rawAttempt, fieldName: 'purchaseAttempt'),
          );
    if (attempt != null &&
        (type != InappifyPlatformEventType.purchaseUpdated ||
            attempt.attemptId != rawRequestId)) {
      throw const FormatException(
        'Purchase event attempt correlation mismatch.',
      );
    }
    return InappifyPlatformEvent(
      type: type,
      requestId: rawRequestId as String?,
      snapshot: snapshotMap == null
          ? null
          : InappifySdkSnapshot.fromMap(snapshotMap),
      data: data.cast<String, Object?>(),
      purchaseAttempt: attempt,
    );
  }

  static Map<String, dynamic> _requiredMap(
    Object? value, {
    required String fieldName,
  }) {
    final map = _optionalMap(value, fieldName: fieldName);
    if (map == null) {
      throw FormatException('Platform response $fieldName must be a map.');
    }
    return map;
  }

  static int _protocolVersion(
    Map<String, Object?> envelope, {
    required String valueName,
  }) {
    final value = envelope[InappifyChannelContract.protocolVersionKey];
    if (value is! num || !value.isFinite || value != value.toInt()) {
      throw FormatException(
        'Platform $valueName protocolVersion must be an integer.',
      );
    }
    return value.toInt();
  }

  static InappifyPlatformEventType _eventType(String value) {
    return switch (value) {
      'stateChanged' => InappifyPlatformEventType.stateChanged,
      'customerInfoChanged' => InappifyPlatformEventType.customerInfoChanged,
      'offeringsChanged' => InappifyPlatformEventType.offeringsChanged,
      'authenticationChanged' =>
        InappifyPlatformEventType.authenticationChanged,
      'sessionStateChanged' => InappifyPlatformEventType.sessionStateChanged,
      'purchaseUpdated' => InappifyPlatformEventType.purchaseUpdated,
      _ => throw FormatException('Unsupported platform event type: $value.'),
    };
  }

  static InappifyFailureCode _failureCode(String value) {
    return switch (value) {
      'invalidConfiguration' => InappifyFailureCode.invalidConfiguration,
      'notConfigured' => InappifyFailureCode.notConfigured,
      'unauthorized' => InappifyFailureCode.unauthorized,
      'sessionTemporarilyUnavailable' =>
        InappifyFailureCode.sessionTemporarilyUnavailable,
      'sessionRecoveryRequired' => InappifyFailureCode.sessionRecoveryRequired,
      'identityMismatch' => InappifyFailureCode.identityMismatch,
      'network' => InappifyFailureCode.network,
      'requestCancelled' => InappifyFailureCode.requestCancelled,
      'timeout' => InappifyFailureCode.timeout,
      'storeUnavailable' => InappifyFailureCode.storeUnavailable,
      'storageUnavailable' => InappifyFailureCode.storageUnavailable,
      'purchaseCancelled' => InappifyFailureCode.purchaseCancelled,
      'bridgeUnavailable' => InappifyFailureCode.bridgeUnavailable,
      'unsupportedOperation' => InappifyFailureCode.unsupportedOperation,
      'protocolMismatch' => InappifyFailureCode.protocolMismatch,
      'malformedResponse' => InappifyFailureCode.malformedResponse,
      _ => InappifyFailureCode.unknown,
    };
  }

  static Map<String, dynamic>? _optionalMap(
    Object? value, {
    required String fieldName,
  }) {
    if (value == null) return null;
    if (value is! Map<String, Object?>) {
      throw FormatException('Platform response $fieldName must be a map.');
    }
    return value.cast<String, dynamic>();
  }
}
