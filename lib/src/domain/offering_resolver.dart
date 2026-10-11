import 'dart:convert';

import 'package:inappify_sdk/models/condition.dart';
import 'package:inappify_sdk/models/offering_model.dart';
import 'package:inappify_sdk/models/rule.dart';
import 'package:inappify_sdk/offering_evaluation_context.dart';

/// Resolves offering rules without reading mutable SDK globals.
abstract final class OfferingResolver {
  /// Returns the first matching rule offering or the default offering.
  static OfferingModel? resolve({
    required List<OfferingModel>? offerings,
    required List<Rule>? rules,
    required OfferingEvaluationContext context,
    String? placement,
  }) {
    final orderedRules = List<Rule>.of(rules ?? const <Rule>[])
      ..sort((left, right) => (left.sort ?? 0).compareTo(right.sort ?? 0));
    for (final rule in orderedRules) {
      final matches = (rule.conditions ?? const <Condition>[]).every(
        (condition) => evaluateField(
          fieldName: condition.field ?? '',
          operator: condition.operator ?? '',
          data: condition.value ?? '',
          attributeKey: condition.context,
          context: context,
        ),
      );
      if (!matches) continue;

      if (placement == null) {
        return _ruleDefaultOrFallback(rule, offerings);
      }

      final placements = rule.placements;
      if (placements == null) {
        return _ruleDefaultOrFallback(rule, offerings);
      }

      for (final mapping in placements.placement_offerings ?? const []) {
        if (mapping.placement_identifier == placement) {
          final selected = _findOffering(
            offerings,
            mapping.offering_identifier,
          );
          if (selected != null) return selected;
        }
      }

      final fallbackIdentifier = placements.fallback_offering_id;
      if (fallbackIdentifier?.isNotEmpty ?? false) {
        final fallback = _findOffering(offerings, fallbackIdentifier);
        if (fallback != null) return fallback;
      }
      return _ruleDefaultOrFallback(rule, offerings);
    }

    return _defaultOffering(offerings);
  }

  /// Evaluates one server-provided rule condition against [context].
  static bool evaluateField({
    required String fieldName,
    required String operator,
    required String data,
    required OfferingEvaluationContext context,
    String? attributeKey,
  }) {
    if (fieldName == 'any_audience') return true;
    if (operator.isEmpty) return false;
    final decoded = _decodeConditionValue(data);
    switch (fieldName) {
      case 'country':
        return evaluateOperator(
          context.country.toUpperCase(),
          operator,
          _normalizeCountryValue(decoded),
        );
      case 'platform':
        return _evaluatePlatform(context.platform, operator, decoded);
      case 'custom_attribute':
        final value = context.customAttributes[attributeKey];
        if (value == null || value.isEmpty) return false;
        return evaluateOperator(value, operator, decoded);
      case 'app_config':
        final appId = context.appId;
        return appId != null && evaluateOperator(appId, operator, decoded);
      case 'app_version':
        if (!_matchesAppContext(attributeKey, context.appId)) return false;
        return _evaluateVersion(context.appVersion, operator, decoded);
      case 'sdk_version':
        return _evaluateVersion(context.sdkVersion, operator, decoded);
      default:
        return false;
    }
  }

  /// Applies a stable Inappify comparison operator.
  static bool evaluateOperator(Object? left, String operator, Object? right) {
    switch (operator) {
      case '>':
        return _comparable(left, right, (a, b) => a > b);
      case '<':
        return _comparable(left, right, (a, b) => a < b);
      case '>=':
        return _comparable(left, right, (a, b) => a >= b);
      case '<=':
        return _comparable(left, right, (a, b) => a <= b);
      case '!=':
        return !_equal(left, right);
      case '=':
        return _equal(left, right);
      case 'in':
        return right is List && right.any((item) => _equal(left, item));
      case 'not in':
        return right is List && !right.any((item) => _equal(left, item));
      default:
        return false;
    }
  }

  /// Converts the existing dotted-version representation to a comparable
  /// numeric value while preserving the SDK's historical behavior.
  static double convertVersionToDouble(String version) {
    final parts = version.split('.');
    if (parts.isEmpty) return 0;

    final major = parts.first;
    final minor = parts.skip(1).join();
    return double.tryParse(minor.isEmpty ? major : '$major.$minor') ?? 0;
  }

  /// Compares dotted versions segment by segment.
  static int compareVersions(String left, String right) {
    final leftParts = _versionParts(left);
    final rightParts = _versionParts(right);
    final length = leftParts.length > rightParts.length
        ? leftParts.length
        : rightParts.length;
    for (var index = 0; index < length; index += 1) {
      final difference =
          (index < leftParts.length ? leftParts[index] : 0) -
          (index < rightParts.length ? rightParts[index] : 0);
      if (difference != 0) return difference < 0 ? -1 : 1;
    }
    return 0;
  }

  static Object? _decodeConditionValue(String value) {
    try {
      return jsonDecode(value);
    } catch (_) {
      return value;
    }
  }

  static Object? _normalizeCountryValue(Object? value) {
    if (value is List) {
      return value
          .map((item) => item is String ? item.toUpperCase() : item)
          .toList(growable: false);
    }
    return value is String ? value.toUpperCase() : value;
  }

  static bool _evaluatePlatform(
    Object platform,
    String operator,
    Object? right,
  ) {
    final aliases = <Object>[platform];
    if (platform == 3 || platform.toString().toLowerCase() == 'web') {
      aliases.addAll(<Object>[3, '3', 'web']);
    }
    if (operator == 'in') {
      return right is List &&
          aliases.any((left) => right.any((item) => _equal(left, item)));
    }
    if (operator == 'not in') {
      return right is List &&
          aliases.every((left) => !right.any((item) => _equal(left, item)));
    }
    return aliases.any((left) => evaluateOperator(left, operator, right));
  }

  static bool _evaluateVersion(String left, String operator, Object? rawRight) {
    if (left.isEmpty) return false;
    final right = rawRight is List && rawRight.isNotEmpty
        ? rawRight.first
        : rawRight;
    if (right is! String && right is! num) return false;
    if (_versionParts(left).isEmpty ||
        _versionParts(right.toString()).isEmpty) {
      return false;
    }
    final comparison = compareVersions(left, right.toString());
    return switch (operator) {
      '>' => comparison > 0,
      '<' => comparison < 0,
      '>=' => comparison >= 0,
      '<=' => comparison <= 0,
      '=' => comparison == 0,
      '!=' => comparison != 0,
      _ => false,
    };
  }

  static bool _matchesAppContext(String? conditionAppId, int? currentAppId) {
    return conditionAppId == null ||
        conditionAppId.isEmpty ||
        (currentAppId != null && _equal(currentAppId, conditionAppId));
  }

  static bool _equal(Object? left, Object? right) {
    if (left is num && right is String && right.trim().isNotEmpty) {
      return left == num.tryParse(right);
    }
    if (left is String && right is num && left.trim().isNotEmpty) {
      return num.tryParse(left) == right;
    }
    return left == right;
  }

  static bool _comparable(
    Object? left,
    Object? right,
    bool Function(num left, num right) compare,
  ) {
    final leftNumber = left is num
        ? left
        : num.tryParse(left?.toString() ?? '');
    final rightNumber = right is num
        ? right
        : num.tryParse(right?.toString() ?? '');
    return leftNumber != null &&
        rightNumber != null &&
        compare(leftNumber, rightNumber);
  }

  static List<int> _versionParts(String version) {
    final trimmed = version.trim().replaceFirst(
      RegExp(r'^v', caseSensitive: false),
      '',
    );
    final core = trimmed.split(RegExp(r'[+-]')).first;
    if (!RegExp(r'^\d+(?:\.\d+)*$').hasMatch(core)) return const <int>[];
    return core.split('.').map(int.parse).toList(growable: false);
  }

  static OfferingModel? _ruleDefaultOrFallback(
    Rule rule,
    List<OfferingModel>? offerings,
  ) {
    final identifier = rule.default_offering;
    if (identifier?.isNotEmpty ?? false) {
      return _findOffering(offerings, identifier);
    }
    return _defaultOffering(offerings);
  }

  static OfferingModel? _defaultOffering(List<OfferingModel>? offerings) {
    for (final offering in offerings ?? const <OfferingModel>[]) {
      if (offering.isDefault ?? false) return offering;
    }
    return null;
  }

  static OfferingModel? _findOffering(
    List<OfferingModel>? offerings,
    String? identifier,
  ) {
    for (final offering in offerings ?? const <OfferingModel>[]) {
      if (offering.identifier == identifier) return offering;
    }
    return null;
  }
}
