import 'package:flutter/foundation.dart';

/// CAPTCHA challenge required by an Inappify OTP flow.
///
/// The challenge key is opaque and must be sent back unchanged with the OTP
/// request. The image is provider content intended for display, never logging.
@immutable
class InappifyCaptchaChallenge {
  /// Creates an immutable CAPTCHA challenge.
  const InappifyCaptchaChallenge({
    required this.captchaKey,
    required this.captchaImage,
    required this.expiresIn,
  });

  /// Opaque server challenge identifier.
  final String captchaKey;

  /// Provider-supplied image payload or URL.
  final String captchaImage;

  /// Remaining validity in seconds.
  final int expiresIn;

  /// Decodes the documented Web SDK challenge shape.
  factory InappifyCaptchaChallenge.fromMap(Map<String, dynamic> map) {
    final key = map['captchaKey'] ?? map['captcha_key'];
    final image = map['captchaImage'] ?? map['captcha_image'];
    final expires = map['expiresIn'] ?? map['expires_in'];
    if (key is! String ||
        key.isEmpty ||
        image is! String ||
        image.isEmpty ||
        expires is! num ||
        !expires.isFinite ||
        expires != expires.toInt()) {
      throw const FormatException('OTP CAPTCHA challenge is malformed.');
    }
    return InappifyCaptchaChallenge(
      captchaKey: key,
      captchaImage: image,
      expiresIn: expires.toInt(),
    );
  }

  /// Encodes this challenge using standard message-codec values.
  Map<String, Object?> toMap() => <String, Object?>{
    'captchaKey': captchaKey,
    'captchaImage': captchaImage,
    'expiresIn': expiresIn,
  };
}
