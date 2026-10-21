import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

/// Mobile behavior version, independent of the host application's version.
const goV2SdkVersion = '0.2.0';

/// Public trust anchor shared with the native Kotlin SDK.
/// Downloaded keys may alias these bytes, but may never establish new trust.
const officialGoV2SigningKeys = <String, String>{
  'sdk-v2-2026-09-09': 'AJr7nlATgLmPOiCoY1W28UucpkLw_DWMjD-trvv73Ak',
};

/// A bounded semantic error. Provider messages and credential values are not retained.
class GoV2ProtocolException implements Exception {
  const GoV2ProtocolException(
    this.category,
    this.code, {
    this.retryable = false,
    this.details = const <String, Object?>{},
  });

  final String category;
  final String code;
  final bool retryable;
  final Map<String, Object?> details;

  @override
  String toString() => 'Inappify Go V2 $category failure ($code).';
}

Never _fail(String category, String code) =>
    throw GoV2ProtocolException(category, code);

/// Parses bounded JSON without silently accepting duplicate object members.
Map<String, dynamic> strictGoV2Json(String raw) {
  if (utf8.encode(raw).length > 1024 * 1024) {
    _fail('DECODING', 'BODY_TOO_LARGE');
  }
  try {
    final parser = _StrictJsonParser(raw);
    final value = parser.value(0);
    parser.whitespace();
    if (value is! Map<String, dynamic> || parser.offset != raw.length) {
      throw const FormatException();
    }
    return value;
  } on GoV2ProtocolException {
    rethrow;
  } catch (_) {
    _fail('DECODING', 'INVALID_JSON');
  }
}

/// Strict JSON structure validation; cryptography is delegated to Ed25519.
class _StrictJsonParser {
  _StrictJsonParser(this.raw);
  final String raw;
  int offset = 0;
  int nodes = 0;

  void whitespace() {
    while (offset < raw.length &&
        const <int>[32, 9, 10, 13].contains(raw.codeUnitAt(offset))) {
      offset++;
    }
  }

  Object? value(int depth) {
    whitespace();
    if (depth > 32 || ++nodes > 50000 || offset >= raw.length) {
      throw const FormatException();
    }
    final char = raw[offset];
    if (char == '{') {
      offset++;
      final object = <String, dynamic>{};
      whitespace();
      if (_take('}')) return object;
      while (true) {
        whitespace();
        final key = string();
        if (object.containsKey(key)) throw const FormatException();
        whitespace();
        if (!_take(':')) throw const FormatException();
        object[key] = value(depth + 1);
        whitespace();
        if (_take('}')) return object;
        if (!_take(',')) throw const FormatException();
      }
    }
    if (char == '[') {
      offset++;
      final array = <Object?>[];
      whitespace();
      if (_take(']')) return array;
      while (true) {
        array.add(value(depth + 1));
        whitespace();
        if (_take(']')) return array;
        if (!_take(',')) throw const FormatException();
      }
    }
    if (char == '"') return string();
    for (final literal in const <String>['true', 'false', 'null']) {
      if (raw.startsWith(literal, offset)) {
        offset += literal.length;
        return switch (literal) {
          'true' => true,
          'false' => false,
          _ => null,
        };
      }
    }
    final match = RegExp(
      r'-?(?:0|[1-9][0-9]*)(?:\.[0-9]+)?(?:[eE][+-]?[0-9]+)?',
    ).matchAsPrefix(raw, offset);
    if (match == null) throw const FormatException();
    offset = match.end;
    final lexeme = match.group(0)!;
    final number = num.parse(lexeme);
    // Do not collapse distinct signed/unsigned values through double rounding.
    if (!number.isFinite ||
        _canonicalDecimal(lexeme) != _canonicalDecimal(number.toString())) {
      throw const FormatException();
    }
    return number;
  }

  String string() {
    final start = offset;
    if (!_take('"')) throw const FormatException();
    var escaped = false;
    while (offset < raw.length) {
      final code = raw.codeUnitAt(offset++);
      if (code < 32) throw const FormatException();
      if (!escaped && code == 34) {
        return jsonDecode(raw.substring(start, offset)) as String;
      }
      if (!escaped && code == 92) {
        escaped = true;
      } else {
        escaped = false;
      }
    }
    throw const FormatException();
  }

  bool _take(String char) {
    if (offset < raw.length && raw[offset] == char) {
      offset++;
      return true;
    }
    return false;
  }
}

String _canonicalDecimal(String value) {
  final parts = value.toLowerCase().split('e');
  final exponent = parts.length == 1 ? 0 : int.tryParse(parts[1]);
  if (exponent == null || exponent.abs() > 10000) {
    throw const FormatException();
  }
  final negative = parts[0].startsWith('-');
  final significand = negative ? parts[0].substring(1) : parts[0];
  final decimalIndex = significand.indexOf('.');
  var scale =
      exponent - (decimalIndex < 0 ? 0 : significand.length - decimalIndex - 1);
  var digits = significand.replaceAll('.', '').replaceFirst(RegExp(r'^0+'), '');
  if (digits.isEmpty) return '0';
  while (digits.endsWith('0')) {
    digits = digits.substring(0, digits.length - 1);
    scale++;
  }
  return '${negative ? '-' : ''}${digits}e$scale';
}

DateTime goV2IsoDate(String value) {
  // DateTime.parse normalizes impossible dates, so compare the calendar fields.
  final match = RegExp(
    r'^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})(?:\.\d{1,9})?(Z|[+-]\d{2}:?\d{2})$',
  ).firstMatch(value);
  if (match == null) _fail('DECODING', 'INVALID_DATE');
  final year = int.parse(match.group(1)!);
  final month = int.parse(match.group(2)!);
  final day = int.parse(match.group(3)!);
  final hour = int.parse(match.group(4)!);
  final minute = int.parse(match.group(5)!);
  final second = int.parse(match.group(6)!);
  final calendar = DateTime.utc(year, month, day);
  if (calendar.year != year ||
      calendar.month != month ||
      calendar.day != day ||
      hour > 23 ||
      minute > 59 ||
      second > 59) {
    _fail('DECODING', 'INVALID_DATE');
  }
  final zone = match.group(7)!;
  if (zone != 'Z') {
    final digits = zone.substring(1).replaceAll(':', '');
    if (int.parse(digits.substring(0, 2)) > 23 ||
        int.parse(digits.substring(2)) > 59) {
      _fail('DECODING', 'INVALID_DATE');
    }
  }
  return DateTime.tryParse(value)?.toUtc() ?? _fail('DECODING', 'INVALID_DATE');
}

Uint8List goV2Base64Url(String value) {
  if (!RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(value)) {
    _fail('SIGNATURE', 'INVALID_BASE64URL');
  }
  try {
    final bytes = base64Url.decode(base64Url.normalize(value));
    if (base64Url.encode(bytes).replaceAll('=', '') != value) {
      _fail('SIGNATURE', 'INVALID_BASE64URL');
    }
    return bytes;
  } on GoV2ProtocolException {
    rethrow;
  } catch (_) {
    _fail('SIGNATURE', 'INVALID_BASE64URL');
  }
}

class GoV2VerifiedCustomer {
  GoV2VerifiedCustomer({
    required this.info,
    required this.scope,
    required this.subject,
    required this.expiresAt,
  });
  final Map<String, dynamic> info;
  final Map<String, Object?> scope;
  final String subject;
  final DateTime expiresAt;
}

/// Validates signed CustomerInfo before it can be published or restored.
class GoV2Verifier {
  GoV2Verifier({
    Map<String, String> pinnedSigningKeys = officialGoV2SigningKeys,
    DateTime Function()? now,
    this.expectedScope,
  }) : _now = now ?? DateTime.now {
    if (pinnedSigningKeys.isEmpty) {
      _fail('CONFIGURATION', 'MISSING_TRUST_ANCHOR');
    }
    for (final entry in pinnedSigningKeys.entries) {
      final bytes = goV2Base64Url(entry.value);
      if (bytes.length != 32 || entry.key.isEmpty) {
        _fail('CONFIGURATION', 'INVALID_TRUST_ANCHOR');
      }
      _keys[entry.key] = bytes;
    }
  }

  final Map<String, Object?>? expectedScope;
  final DateTime Function() _now;
  final Map<String, Uint8List> _keys = <String, Uint8List>{};

  bool known(String kid) => _keys.containsKey(kid);

  /// Accepts new key IDs only when key material equals an existing pin.
  void refresh(Map<String, dynamic> jwks) {
    final candidates = jwks['keys'];
    if (candidates is! List || candidates.length > 100) {
      _fail('SIGNATURE', 'INVALID_JWKS');
    }
    final additions = <String, Uint8List>{};
    for (final raw in candidates) {
      if (raw is! Map) _fail('SIGNATURE', 'INVALID_JWKS');
      if (raw['kty'] == 'OKP' &&
          raw['crv'] == 'Ed25519' &&
          raw['alg'] == 'EdDSA' &&
          raw['use'] == 'sig') {
        if (raw['x'] is! String || raw['kid'] is! String) {
          _fail('SIGNATURE', 'INVALID_JWKS');
        }
        final bytes = goV2Base64Url(raw['x'] as String);
        final kid = raw['kid'] as String;
        if (_keys.values.any((pin) => _equalBytes(pin, bytes)) &&
            !_keys.containsKey(kid) &&
            kid.isNotEmpty) {
          additions[kid] = bytes;
        }
      }
    }
    _keys.addAll(additions);
  }

  Future<GoV2VerifiedCustomer> verify(
    Map<String, dynamic> envelope, {
    required String expectedPublicUserId,
    Map<String, Object?>? expectedScope,
    String? expectedSubject,
    bool allowExpiredCache = false,
  }) async {
    try {
      final verification = envelope['verification'];
      if (verification is! Map) _fail('SIGNATURE', 'MISSING_VERIFICATION');
      final jws = verification['jws'];
      if (jws is! String || utf8.encode(jws).length > 1024 * 1024) {
        _fail('SIGNATURE', 'INVALID_JWS');
      }
      final parts = jws.split('.');
      if (parts.length != 3) _fail('SIGNATURE', 'INVALID_JWS');
      final header = strictGoV2Json(utf8.decode(goV2Base64Url(parts[0])));
      final kid = header['kid'];
      if (header['alg'] != 'EdDSA' ||
          header['typ'] != 'INA-CUSTOMER-INFO' ||
          header.containsKey('crit') ||
          header.containsKey('b64') ||
          kid is! String ||
          kid.isEmpty) {
        _fail('SIGNATURE', 'INVALID_HEADER');
      }
      if (verification['algorithm'] != 'EdDSA' ||
          verification['keyId'] != kid) {
        _fail('SIGNATURE', 'VERIFICATION_MISMATCH');
      }
      final key = _keys[kid];
      if (key == null) _fail('SIGNATURE', 'UNKNOWN_KEY');
      final signature = goV2Base64Url(parts[2]);
      if (signature.length != 64 ||
          !await Ed25519().verify(
            ascii.encode('${parts[0]}.${parts[1]}'),
            signature: Signature(
              signature,
              publicKey: SimplePublicKey(key, type: KeyPairType.ed25519),
            ),
          )) {
        _fail('SIGNATURE', 'INVALID_SIGNATURE');
      }
      final payload = strictGoV2Json(utf8.decode(goV2Base64Url(parts[1])));
      final issuer = _claimString(payload, 'iss');
      final appId = _claimInt(payload, 'app_id');
      final projectId = _claimInt(payload, 'project_id');
      if (!_boundedText(issuer, 2048)) {
        _mismatch('iss', 'valid issuer required');
      }
      if (appId <= 0) _mismatch('app_id', 'positive integer required');
      if (projectId <= 0) _mismatch('project_id', 'positive integer required');
      final scope = <String, Object?>{
        'issuer': issuer,
        'appId': appId,
        'projectId': projectId,
      };
      for (final expected in <Map<String, Object?>?>[
        expectedScope,
        this.expectedScope,
      ]) {
        if (expected == null) continue;
        for (final field in scope.keys) {
          if (scope[field] != expected[field]) {
            _mismatch(field, 'exact scope match');
          }
        }
      }
      if (_claimString(payload, 'aud') != 'inappify-sdk') {
        _mismatch('aud', 'must equal inappify-sdk');
      }
      if (_claimInt(payload, 'ver') != 2) _mismatch('ver', 'must equal 2');
      final subject = _claimString(payload, 'sub');
      if (!_boundedText(subject, 512)) {
        _mismatch('sub', 'valid internal subject required');
      }
      if (expectedSubject != null && subject != expectedSubject) {
        _mismatch('sub', 'exact internal customer match');
      }
      final exp = _claimInt(payload, 'exp');
      // DateTime supports up to 100,000,000 days from the epoch.
      if (exp <= 0 || exp > 8640000000000) _fail('SIGNATURE', 'INVALID_EXPIRY');
      final expiresAt = DateTime.fromMillisecondsSinceEpoch(
        exp * 1000,
        isUtc: true,
      );
      final metadataExpiry = verification['expiresAt'];
      if (metadataExpiry is! String ||
          goV2IsoDate(metadataExpiry).millisecondsSinceEpoch ~/ 1000 != exp) {
        _fail('SIGNATURE', 'EXPIRY_MISMATCH');
      }
      final nowSeconds = _now().millisecondsSinceEpoch ~/ 1000;
      if (!allowExpiredCache && nowSeconds >= exp) {
        _fail('SIGNATURE', 'EXPIRED_SIGNATURE');
      }
      if (payload.containsKey('nbf') &&
          _claimInt(payload, 'nbf') > nowSeconds) {
        _fail('SIGNATURE', 'NOT_YET_VALID');
      }
      final info = payload['customer_info'];
      if (info is! Map<String, dynamic>) {
        _fail('SIGNATURE', 'MISSING_CUSTOMER_INFO');
      }
      if (info['originalAppUserId'] != expectedPublicUserId) {
        _mismatch(
          'customer_info.originalAppUserId',
          'exact public app-user match',
          code: 'CUSTOMER_MISMATCH',
        );
      }
      if (info['requestDate'] is! String ||
          !goV2IsoDate(info['requestDate'] as String).isBefore(expiresAt)) {
        _fail('SIGNATURE', 'INVALID_REQUEST_DATE');
      }
      if (!_deepEquals(info, envelope['customerInfo'])) {
        _fail('SIGNATURE', 'CUSTOMER_INFO_MISMATCH');
      }
      final entitlements = info['entitlements'];
      if (entitlements != null && entitlements is! List) {
        _fail('SIGNATURE', 'INVALID_CUSTOMER_INFO');
      }
      for (final entitlement in (entitlements as List?) ?? const <Object?>[]) {
        if (entitlement is! Map) _fail('SIGNATURE', 'INVALID_CUSTOMER_INFO');
        final expiration = entitlement['expiration_date'];
        if (expiration != null && expiration is! String) {
          _fail('SIGNATURE', 'INVALID_CUSTOMER_INFO');
        }
        if (expiration is String && expiration.isNotEmpty) {
          goV2IsoDate(expiration);
        }
      }
      final projection = Map<String, dynamic>.from(info)..remove('attributes');
      return GoV2VerifiedCustomer(
        info: projection,
        scope: scope,
        subject: subject,
        expiresAt: expiresAt,
      );
    } on GoV2ProtocolException {
      rethrow;
    } catch (_) {
      _fail('SIGNATURE', 'INVALID_VERIFICATION');
    }
  }
}

String _claimString(Map<String, dynamic> payload, String field) {
  final value = payload[field];
  if (value is! String) _mismatch(field, 'string required');
  return value;
}

int _claimInt(Map<String, dynamic> payload, String field) {
  final value = payload[field];
  if (value is! num || !value.isFinite || value != value.toInt()) {
    _mismatch(field, 'integer required');
  }
  return value.toInt();
}

Never _mismatch(String field, String rule, {String code = 'SCOPE_MISMATCH'}) =>
    throw GoV2ProtocolException(
      'SIGNATURE',
      code,
      details: <String, Object?>{
        'mismatchField': field,
        'validationRule': rule,
        'signatureVerified': true,
      },
    );

bool _boundedText(String text, int limit) =>
    text.trim().isNotEmpty &&
    text.length <= limit &&
    !RegExp(r'[\x00-\x1f\x7f-\x9f]').hasMatch(text);

bool _equalBytes(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  var difference = 0;
  for (var i = 0; i < a.length; i++) {
    difference |= a[i] ^ b[i];
  }
  return difference == 0;
}

bool _deepEquals(Object? a, Object? b) {
  if (a is Map && b is Map) {
    return a.length == b.length &&
        a.keys.every(
          (key) => b.containsKey(key) && _deepEquals(a[key], b[key]),
        );
  }
  if (a is List && b is List) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (!_deepEquals(a[i], b[i])) return false;
    }
    return true;
  }
  return a == b;
}
