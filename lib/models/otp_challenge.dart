import 'package:flutter/foundation.dart';

/// OTP challenge created by the selected Inappify backend.
///
/// The challenge identifier is opaque and must be passed back unchanged to
/// OTP verification. Implementations must not log the identifier or OTP code.
@immutable
class InappifyOtpChallenge {
  /// Creates an OTP challenge.
  const InappifyOtpChallenge({
    required this.challengeId,
    this.status,
    this.expiresAt,
    this.expiresIn,
  });

  /// Opaque identifier correlating the verification attempt.
  final String challengeId;

  /// Provider-defined challenge state.
  final String? status;

  /// Optional ISO-8601 expiration timestamp supplied by the backend.
  final String? expiresAt;

  /// Optional remaining validity in seconds.
  final int? expiresIn;

  /// Decodes a challenge response from JavaScript or a future native SDK.
  factory InappifyOtpChallenge.fromMap(Map<String, dynamic> map) {
    final challengeId = map['challengeId'] ?? map['challenge_id'] ?? map['id'];
    if (challengeId is! String || challengeId.isEmpty) {
      throw const FormatException(
        'OTP challengeId must be a non-empty string.',
      );
    }
    final expiresAt = map['expiresAt'] ?? map['expires_at'];
    final status = map['status'];
    final expiresIn = map['expiresIn'] ?? map['expires_in'];
    if (expiresAt != null && expiresAt is! String) {
      throw const FormatException('OTP expiresAt must be a string or null.');
    }
    if (status != null && status is! String) {
      throw const FormatException('OTP status must be a string or null.');
    }
    if (expiresIn != null &&
        (expiresIn is! num ||
            !expiresIn.isFinite ||
            expiresIn != expiresIn.toInt())) {
      throw const FormatException('OTP expiresIn must be an integer or null.');
    }
    return InappifyOtpChallenge(
      challengeId: challengeId,
      status: status as String?,
      expiresAt: expiresAt as String?,
      expiresIn: (expiresIn as num?)?.toInt(),
    );
  }

  /// Encodes this challenge using standard message-codec values.
  Map<String, Object?> toMap() => <String, Object?>{
    'challengeId': challengeId,
    'status': status,
    'expiresAt': expiresAt,
    'expiresIn': expiresIn,
  };
}
