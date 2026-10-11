import 'package:flutter/foundation.dart';

/// Public authentication state returned by an Inappify session backend.
///
/// Web backends obtain this value after exchanging a one-time Identity Ticket
/// or verifying an OTP challenge. Tokens deliberately do not cross this
/// boundary; their storage and rotation remain owned by the selected backend.
@immutable
class InappifyAuthenticationResult {
  /// Creates an immutable authentication result.
  const InappifyAuthenticationResult({
    required this.isAnonymous,
    this.type,
    this.authenticatedAt,
  });

  /// Whether the active customer session is anonymous.
  final bool isAnonymous;

  /// Provider-defined authentication type, when reported by the backend.
  final String? type;

  /// ISO-8601 authentication timestamp, when reported by the backend.
  final String? authenticatedAt;

  /// Decodes the documented, token-free authentication response.
  factory InappifyAuthenticationResult.fromMap(Map<String, dynamic> map) {
    final isAnonymous = map['isAnonymous'] ?? map['is_anonymous'];
    if (isAnonymous is! bool) {
      throw const FormatException(
        'Authentication result isAnonymous must be a boolean.',
      );
    }
    return InappifyAuthenticationResult(
      isAnonymous: isAnonymous,
      type: _nullableString(map['type'], 'type'),
      authenticatedAt: _nullableString(
        map['authenticatedAt'] ?? map['authenticated_at'],
        'authenticatedAt',
      ),
    );
  }

  /// Encodes this result using standard message-codec values.
  Map<String, Object?> toMap() => <String, Object?>{
    'isAnonymous': isAnonymous,
    'type': type,
    'authenticatedAt': authenticatedAt,
  };

  static String? _nullableString(Object? value, String field) {
    if (value == null || value is String) return value as String?;
    throw FormatException('Authentication result $field must be a string.');
  }
}
