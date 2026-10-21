import 'package:inappify_sdk/src/logging/sdk_logger.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart';

import 'go_v2_protocol.dart';

abstract class GoV2Storage {
  Future<String?> read();
  Future<void> write(String document);
}

/// Isolated Keychain persistence. Legacy preferences are never read or removed.
class MethodChannelGoV2Storage implements GoV2Storage {
  MethodChannelGoV2Storage({this.namespace = 'goV2', MethodChannel? channel})
    : _channel = channel ?? const MethodChannel('inappify_sdk') {
    if (namespace != 'goV2') {
      throw const GoV2ProtocolException(
        'CONFIGURATION',
        'INVALID_STORAGE_NAMESPACE',
      );
    }
  }

  final String namespace;
  final MethodChannel _channel;

  @override
  Future<String?> read() async {
    try {
      final value = await _channel.invokeMethod<String>(
        'sdkReadGoState',
        <String, Object?>{'namespace': namespace},
      );
      if (value != null && utf8.encode(value).length > 1024 * 1024) {
        throw const GoV2ProtocolException('STORAGE', 'STATE_TOO_LARGE');
      }
      return value;
    } on GoV2ProtocolException {
      rethrow;
    } catch (_) {
      throw const GoV2ProtocolException('STORAGE', 'READ_FAILED');
    }
  }

  @override
  Future<void> write(String document) async {
    strictGoV2Json(document);
    try {
      await _channel.invokeMethod<void>('sdkWriteGoState', <String, Object?>{
        'namespace': namespace,
        'document': document,
      });
    } catch (_) {
      throw const GoV2ProtocolException('STORAGE', 'WRITE_FAILED');
    }
  }
}

class GoV2Metadata {
  const GoV2Metadata({
    required this.identifierValue,
    required this.versionName,
    required this.versionCode,
  });

  final String identifierValue;
  final String versionName;
  final int versionCode;

  Map<String, Object?> toMap() => <String, Object?>{
    'identifierValue': identifierValue,
    'versionName': versionName,
    'versionCode': versionCode,
  };
}

typedef GoV2MetadataProvider = Future<GoV2Metadata> Function();

Future<GoV2Metadata> readGoV2MobileMetadata() async {
  try {
    final raw = await const MethodChannel(
      'inappify_sdk',
    ).invokeMapMethod<String, Object?>('sdkGetMobileMetadata');
    final identifier = raw?['identifierValue'];
    final name = raw?['versionName'];
    final code = raw?['versionCode'];
    if (identifier is! String ||
        identifier.trim().isEmpty ||
        name is! String ||
        name.trim().isEmpty ||
        name.length > 50 ||
        code is! int ||
        code < 1) {
      throw const GoV2ProtocolException(
        'CONFIGURATION',
        'INVALID_APP_METADATA',
      );
    }
    return GoV2Metadata(
      identifierValue: identifier,
      versionName: name,
      versionCode: code,
    );
  } on GoV2ProtocolException {
    rethrow;
  } catch (_) {
    throw const GoV2ProtocolException(
      'CONFIGURATION',
      'APP_METADATA_UNAVAILABLE',
    );
  }
}

abstract class GoV2Transport {
  /// Canonical commerce endpoint used to bind durable delivery checkpoints.
  String get commerceScope => 'https://api.inappify.com/app/v2/';
  bool enabled = true;
  Stream<Map<String, Object?>> get traces;
  Future<Map<String, dynamic>> request(
    String endpoint, {
    String? bearer,
    Map<String, Object?> body = const <String, Object?>{},
    Map<String, String> headers = const {},
    bool retry = true,
  });
  Future<void> close();
}

/// HTTPS-only Go transport with bounded bodies, no redirects, and safe traces.
class DioGoV2Transport extends GoV2Transport {
  DioGoV2Transport({
    String baseUrl = 'https://service.inappify.com/app/v2/',
    this.commerce = false,
    Dio? dio,
    DateTime Function()? now,
    Future<void> Function(Duration)? sleep,
    this.timeout = const Duration(seconds: 30),
    int Function()? jitterMilliseconds,
  }) : _dio = dio ?? Dio(),
       _now = now ?? DateTime.now,
       _sleep = sleep ?? Future<void>.delayed,
       _jitter = jitterMilliseconds ?? (() => Random.secure().nextInt(251)),
       _base = _validateBase(baseUrl);

  /// Commerce uses Bearer authentication, never legacy JSON credentials.
  factory DioGoV2Transport.commerce({Dio? dio}) => DioGoV2Transport(
    baseUrl: 'https://api.inappify.com/app/v2/',
    commerce: true,
    dio: dio,
  );

  final bool commerce;

  @override
  String get commerceScope => _base.toString();

  final Dio _dio;
  final Uri _base;
  final DateTime Function() _now;
  final Future<void> Function(Duration) _sleep;
  final int Function() _jitter;
  final Duration timeout;
  final StreamController<Map<String, Object?>> _traces =
      StreamController<Map<String, Object?>>.broadcast();
  bool _closed = false;
  final Set<CancelToken> _activeRequests = <CancelToken>{};

  @override
  Stream<Map<String, Object?>> get traces => _traces.stream;

  static Uri _validateBase(String value) {
    final url = Uri.tryParse(value);
    if (url == null ||
        url.scheme != 'https' ||
        url.host.isEmpty ||
        url.userInfo.isNotEmpty ||
        url.query.isNotEmpty ||
        url.fragment.isNotEmpty ||
        url.path != '/app/v2/') {
      throw const GoV2ProtocolException('CONFIGURATION', 'INVALID_BASE_URL');
    }
    return url;
  }

  @override
  Future<Map<String, dynamic>> request(
    String endpoint, {
    String? bearer,
    Map<String, Object?> body = const <String, Object?>{},
    bool retry = true,
    Map<String, String> headers = const {},
  }) async {
    if (!(commerce
            ? <String>{
                'purchase',
                'consumable-deliveries/pending',
                if (RegExp(
                  r'^consumable-deliveries/[1-9][0-9]*/delivered$',
                ).hasMatch(endpoint))
                  endpoint,
              }
            : const <String>{
                'configure',
                'login',
                'logout',
                'customerInfo',
                'offerings',
                'attributes',
                'validateDiscountCode',
                'public-keys',
              })
        .contains(endpoint)) {
      throw const GoV2ProtocolException('CONFIGURATION', 'INVALID_ENDPOINT');
    }
    _ensureEnabled();
    for (final entry in headers.entries) {
      if (!const {
            'X-Inappify-Login-Attempt',
            'X-Inappify-Logout-Attempt',
          }.contains(entry.key) ||
          !RegExp(r'^[A-Za-z0-9_.:-]{1,128}$').hasMatch(entry.value)) {
        throw const GoV2ProtocolException(
          'VALIDATION',
          'INVALID_ATTEMPT_HEADER',
        );
      }
    }
    final attemptHeaders = headers;
    final publicKeys = endpoint == 'public-keys';
    final rawBody = jsonEncode(body);
    if (utf8.encode(rawBody).length > 1024 * 1024) {
      throw const GoV2ProtocolException('VALIDATION', 'BODY_TOO_LARGE');
    }
    for (var attempt = 0; attempt < (retry ? 4 : 1); attempt++) {
      _ensureEnabled();
      final cancel = CancelToken();
      _activeRequests.add(cancel);
      final started = _now();
      final logEndpoint = endpoint.replaceFirst(RegExp(r'/[1-9][0-9]*/delivered$'), '/:id/delivered');
      SdkLogger.debug('HTTP request: $logEndpoint; attempt ${attempt + 1}.');
      Map<String, List<String>> headers = const <String, List<String>>{};
      int? status;
      String? rawResponse;
      GoV2ProtocolException? failure;
      Map<String, dynamic>? decoded;
      try {
        final response = await _dio
            .request<ResponseBody>(
              _base.resolve(endpoint).toString(),
              data: publicKeys ? null : rawBody,
              cancelToken: cancel,
              options: Options(
                method: publicKeys ? 'GET' : 'POST',
                headers: <String, Object?>{
                  'Accept': 'application/json',
                  'Content-Type': 'application/json; charset=utf-8',
                  'User-Agent': 'InAppify-Flutter-iOS/$goV2SdkVersion',
                  ...attemptHeaders,
                  if (!publicKeys && bearer != null)
                    'Authorization': 'Bearer $bearer',
                },
                responseType: ResponseType.stream,
                followRedirects: false,
                maxRedirects: 0,
                validateStatus: (_) => true,
                sendTimeout: timeout,
                receiveTimeout: timeout,
              ),
            )
            .timeout(
              timeout,
              onTimeout: () {
                cancel.cancel();
                throw TimeoutException('Inappify request timed out.');
              },
            );
        status = response.statusCode;
        headers = response.headers.map;
        final responseBody = response.data;
        if (responseBody == null) {
          throw const GoV2ProtocolException('DECODING', 'INVALID_BODY');
        }
        final bytes = <int>[];
        await for (final chunk in responseBody.stream.timeout(timeout)) {
          if (bytes.length + chunk.length > 1024 * 1024) {
            cancel.cancel();
            throw const GoV2ProtocolException('DECODING', 'BODY_TOO_LARGE');
          }
          bytes.addAll(chunk);
        }
        rawResponse = utf8.decode(bytes);
        if (status == 204 && endpoint == 'attributes') {
          decoded = <String, dynamic>{};
        } else {
          try {
            decoded = strictGoV2Json(rawResponse);
          } on GoV2ProtocolException {
            if (status == 200) rethrow;
            decoded = <String, dynamic>{};
          }
          if (status != 200 || decoded['status'] == false) {
            final rawCode = decoded['code'];
            final rawNumericCode = decoded['errorCode'];
            final numericCode = rawNumericCode is int && rawNumericCode >= 0
                ? rawNumericCode
                : null;
            final code =
                rawCode is String &&
                    RegExp(r'^[A-Z0-9_]{1,80}$').hasMatch(rawCode)
                ? rawCode
                : numericCode == null
                ? 'HTTP_${status ?? 0}'
                : 'ERROR_CODE_$numericCode';
            final category =
                code.startsWith('PUBLIC_API_KEY') ||
                    code == 'APP_IDENTIFIER_INVALID'
                ? 'CONFIGURATION'
                : switch (status) {
                    401 || 403 => 'AUTH',
                    400 || 422 => 'VALIDATION',
                    429 => 'RATE_LIMIT',
                    _ => 'SERVER',
                  };
            throw GoV2ProtocolException(
              category,
              code,
              retryable: const <int>{429, 500, 502, 503, 504}.contains(status),
              details: <String, Object?>{
                'httpStatus': status,
                'errorCode': ?numericCode,
              },
            );
          }
          if (!publicKeys && decoded['status'] != true) {
            throw const GoV2ProtocolException('DECODING', 'INVALID_STATUS');
          }
        }
      } on GoV2ProtocolException catch (error) {
        failure = error;
      } on TimeoutException {
        cancel.cancel();
        failure = const GoV2ProtocolException(
          'TIMEOUT',
          'TIMEOUT',
          retryable: true,
        );
      } on DioException catch (error) {
        final timedOut = const <DioExceptionType>{
          DioExceptionType.connectionTimeout,
          DioExceptionType.sendTimeout,
          DioExceptionType.receiveTimeout,
        }.contains(error.type);
        final cancelled = error.type == DioExceptionType.cancel;
        failure = GoV2ProtocolException(
          timedOut ? 'TIMEOUT' : 'NETWORK',
          cancelled ? 'REQUEST_CANCELLED' : (timedOut ? 'TIMEOUT' : 'NETWORK'),
          retryable: !cancelled,
        );
      } on FormatException {
        failure = const GoV2ProtocolException('DECODING', 'INVALID_ENCODING');
      } catch (_) {
        failure = const GoV2ProtocolException(
          'NETWORK',
          'NETWORK',
          retryable: true,
        );
      } finally {
        _activeRequests.remove(cancel);
        if (failure != null) {
          SdkLogger.warn('HTTP request failed.');
        } else if ((status ?? 0) >= 400) {
          SdkLogger.warn('HTTP response: $logEndpoint; status $status.');
        } else {
          SdkLogger.debug('HTTP response: $logEndpoint; status $status.');
        }
        if (!_traces.isClosed) {
          _traces.add(<String, Object?>{
            'method': publicKeys ? 'GET' : 'POST',
            'endpoint': _base
                .resolve(endpoint)
                .toString()
                .replaceFirst(
                  RegExp(r'/[1-9][0-9]*/delivered$'),
                  '/{redacted}/delivered',
                ),
            'attempt': attempt + 1,
            'statusCode': status,
            'durationMillis': max(0, _now().difference(started).inMilliseconds),
            'requestHeaders': <String, Object?>{
              'Accept': 'application/json',
              'Content-Type': 'application/json; charset=utf-8',
              if (!publicKeys && bearer != null) 'Authorization': '<redacted>',
              for (final name in attemptHeaders.keys) name: '<redacted>',
            },
            'requestBody': publicKeys ? null : jsonEncode(_filtered(body)),
            'responseBody': decoded == null
                ? null
                : jsonEncode(_filtered(decoded)),
            'responseBytes': rawResponse == null
                ? 0
                : utf8.encode(rawResponse).length,
            if (failure != null) 'failure': failure.code,
          });
        }
      }
      if (failure == null) return decoded!;
      if (retry && failure.retryable && attempt < 3) {
        await _sleep(_retryDelay(attempt, headers));
        continue;
      }
      throw failure;
    }
    throw const GoV2ProtocolException('NETWORK', 'RETRY_EXHAUSTED');
  }

  Duration _retryDelay(int attempt, Map<String, List<String>> headers) {
    // Duration stores microseconds in a signed VM integer. Saturate before
    // multiplication so hostile rate-limit headers cannot wrap to a short retry.
    const maximumMillis = 0x7fffffffffffffff ~/ 1000 - 250;
    String? header(String key) {
      for (final entry in headers.entries) {
        if (entry.key.toLowerCase() == key.toLowerCase() &&
            entry.value.isNotEmpty) {
          return entry.value.first;
        }
      }
      return null;
    }

    var milliseconds = 2000 << attempt;
    final retryAfter = header('Retry-After');
    if (retryAfter != null) {
      final seconds = int.tryParse(retryAfter);
      if (seconds != null && seconds >= 0) {
        milliseconds = max(
          milliseconds,
          min(seconds, maximumMillis ~/ 1000) * 1000,
        );
      } else {
        try {
          milliseconds = max(
            milliseconds,
            HttpDate.parse(retryAfter).difference(_now()).inMilliseconds,
          );
        } catch (_) {
          /* Ignore invalid header. */
        }
      }
    }
    final reset = int.tryParse(header('X-RateLimit-Reset') ?? '');
    if (reset != null && reset >= 0) {
      milliseconds = max(
        milliseconds,
        min(reset, maximumMillis ~/ 1000) * 1000 -
            _now().millisecondsSinceEpoch,
      );
    }
    // Keep Duration representable without truncating a valid server retry floor.
    return Duration(
      milliseconds: min(milliseconds, maximumMillis) + _jitter().clamp(0, 250),
    );
  }

  void _ensureEnabled() {
    if (_closed || !enabled) {
      throw const GoV2ProtocolException('CONFIGURATION', 'V2_DISABLED');
    }
  }

  @override
  Future<void> close() async {
    _closed = true;
    for (final token in _activeRequests.toList()) {
      token.cancel();
    }
    _dio.close(force: true);
    await _traces.close();
  }
}

/// Keep shapes useful while redacting all untrusted strings and identifiers.
Object? _filtered(Object? value, [String key = '', int depth = 0]) {
  if (depth > 12) return '<truncated>';
  if (RegExp(
    r'api.?key|token|signature|jws|identifier|user|subject|^sub$|email|phone|receipt|purchase|attribute|^id$|id$',
    caseSensitive: false,
  ).hasMatch(key)) {
    return '<redacted>';
  }
  if (value is Map) {
    final result = <String, Object?>{};
    var index = 0;
    for (final entry in value.entries.take(100)) {
      final name = entry.key.toString();
      result[_safeTraceKeys.contains(name)
          ? name
          : '<redacted-key-${index++}>'] = _filtered(
        entry.value,
        name,
        depth + 1,
      );
    }
    return result;
  }
  if (value is List) {
    return value.take(50).map((v) => _filtered(v, key, depth + 1)).toList();
  }
  if (value is String) {
    if (const <String>{
          'status',
          'purchaseStatus',
          'sessionType',
          'algorithm',
          'country',
          'code',
        }.contains(key) &&
        RegExp(r'^[A-Za-z0-9_]{1,50}$').hasMatch(value)) {
      return value;
    }
    return '<redacted>';
  }
  if (value == null || value is bool || value is num) return value;
  return '<redacted>';
}

const _safeTraceKeys = <String>{
  'status',
  'purchaseStatus',
  'code',
  'message',
  'data',
  'apiKey',
  'apikey',
  'token',
  'appUserIdentifier',
  'identifierValue',
  'versionName',
  'versionCode',
  'appId',
  'projectId',
  'appUserId',
  'customerInfo',
  'originalAppUserId',
  'sessionToken',
  'sessionType',
  'sessionExpiresAt',
  'forceVersion',
  'hasForceUpdate',
  'storePlatform',
  'storeInfo',
  'verification',
  'algorithm',
  'keyId',
  'jws',
  'expiresAt',
  'entitlements',
  'identifier',
  'is_active',
  'is_sandbox',
  'entitlement_type',
  'period_type',
  'ownership_type',
  'purchase_date',
  'expiration_date',
  'latestExpirationDate',
  'firstSeen',
  'requestDate',
  'hasUsedTrial',
  'attributes',
  'transactions',
  'offerings',
  'placements',
  'packages',
  'product',
  'country',
  'appVersion',
  'keys',
  'kty',
  'crv',
  'alg',
  'use',
  'kid',
  'x',
  'name',
  'price',
  'currency',
};
