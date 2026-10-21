import 'dart:collection';
import 'package:inappify_sdk/models/entitlement_model.dart';

/// Known rights with RevenueCat-style lookup and active/all maps.
class InappifyEntitlementInfos extends ListBase<EntitlementModel> {
  InappifyEntitlementInfos(
    Iterable<EntitlementModel> values, {
    int? evaluationTimeMillis,
  }) : _values = List.unmodifiable(values),
       _evaluationTimeMillis = evaluationTimeMillis,
       _elapsed = Stopwatch()..start();

  final List<EntitlementModel> _values;
  final int? _evaluationTimeMillis;
  final Stopwatch _elapsed;

  DateTime get _now => _evaluationTimeMillis == null
      ? DateTime.now().toUtc()
      : DateTime.fromMillisecondsSinceEpoch(
          _evaluationTimeMillis + _elapsed.elapsedMilliseconds,
          isUtc: true,
        );

  Map<String, EntitlementModel> get all {
    final result = <String, EntitlementModel>{};
    for (final value in _values) {
      if (value.identifier != null)
        result.putIfAbsent(value.identifier!, () => value);
    }
    return Map.unmodifiable(result);
  }

  Map<String, EntitlementModel> get active => Map.unmodifiable({
    for (final value in all.values)
      if (value.identifier != null && _isActive(value))
        value.identifier!: value,
  });

  bool _isActive(EntitlementModel value) {
    if (value.isActive != true) return false;
    final expiry = value.expirationDate;
    if (expiry == null || expiry.isEmpty) return true;
    final parsed = DateTime.tryParse(expiry);
    return parsed == null
        ? _evaluationTimeMillis == null
        : parsed.isAfter(_now);
  }

  @override
  int get length => _values.length;
  @override
  set length(int value) =>
      throw UnsupportedError('Entitlements are read-only.');
  @override
  EntitlementModel operator [](int index) => _values[index];
  @override
  void operator []=(int index, EntitlementModel value) =>
      throw UnsupportedError('Entitlements are read-only.');
}
