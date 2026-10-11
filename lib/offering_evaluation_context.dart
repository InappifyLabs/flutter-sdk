import 'package:flutter/foundation.dart';

/// Immutable inputs used to evaluate Inappify offering rules.
///
/// Platform adapters build this value from their authoritative snapshot. Rule
/// evaluation receives the value explicitly and therefore does not depend on
/// JavaScript globals, MethodChannel values, or store-specific SDK classes.
@immutable
class OfferingEvaluationContext {
  /// Creates a complete offering-rule evaluation context.
  OfferingEvaluationContext({
    required this.country,
    required this.platform,
    required this.appVersion,
    this.sdkVersion = '',
    this.appId,
    Map<String, String?> customAttributes = const <String, String?>{},
  }) : customAttributes = Map<String, String?>.unmodifiable(customAttributes);

  /// ISO-style country code used by country rules.
  final String country;

  /// Stable platform identifier: `web`, `android`, `ios`, or an empty string.
  final String platform;

  /// Host application version used by app-version rules.
  final String appVersion;

  /// Inappify SDK version used by `sdk_version` targeting rules.
  final String sdkVersion;

  /// Inappify application identifier used by app-configuration rules.
  final int? appId;

  /// Current customer attributes keyed by their Inappify identifier.
  final Map<String, String?> customAttributes;
}
