import 'package:flutter/foundation.dart';

/// Stable error categories shared by Dart, JavaScript, and native backends.
///
/// These values are semantic SDK failures. Transport-specific errors must be
/// translated to one of these values before they cross the platform boundary.
enum InappifyFailureCode {
  invalidConfiguration,
  notConfigured,
  unauthorized,
  sessionTemporarilyUnavailable,
  sessionRecoveryRequired,
  identityMismatch,
  network,
  requestCancelled,
  timeout,
  storeUnavailable,
  storageUnavailable,
  purchaseCancelled,
  bridgeUnavailable,
  unsupportedOperation,
  protocolMismatch,
  malformedResponse,
  unknown,
}

/// Describes a platform-independent SDK failure.
///
/// [details] must only contain values supported by Flutter's standard message
/// codec. API keys, access tokens, purchase tokens, and other secrets must
/// never be included in this object or written to logs.
@immutable
class InappifyFailure {
  const InappifyFailure({
    required this.code,
    required this.message,
    this.isRetryable = false,
    this.details = const <String, Object?>{},
  });

  /// Machine-readable failure category.
  final InappifyFailureCode code;

  /// Human-readable diagnostic message intended for development logs.
  final String message;

  /// Whether retrying the same semantic operation can be considered safe.
  final bool isRetryable;

  /// Non-sensitive, codec-safe diagnostic metadata.
  final Map<String, Object?> details;

  /// Creates the standard failure used by adapters that do not implement an
  /// operation yet.
  factory InappifyFailure.unsupported(String operation) {
    return InappifyFailure(
      code: InappifyFailureCode.unsupportedOperation,
      message: 'The active backend does not support $operation.',
      details: <String, Object?>{'operation': operation},
    );
  }
}
