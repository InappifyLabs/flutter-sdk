import 'package:flutter/foundation.dart';

/// Read-only configuration and browser allowlist reported by an SDK backend.
///
/// The beta Web guide does not freeze the complete configuration schema.
/// Therefore known scalar values are exposed through [values] while unknown
/// fields are preserved as codec-safe data for forward compatibility.
@immutable
class InappifyConfiguration {
  /// Creates an immutable configuration projection.
  InappifyConfiguration(Map<String, Object?> values)
    : values = Map<String, Object?>.unmodifiable(values);

  /// Provider-defined, token-free configuration values.
  final Map<String, Object?> values;

  /// Decodes a configuration object normalized by a platform adapter.
  factory InappifyConfiguration.fromMap(Map<String, dynamic> map) {
    return InappifyConfiguration(map.cast<String, Object?>());
  }

  /// Encodes this value using standard message-codec values.
  Map<String, Object?> toMap() => Map<String, Object?>.of(values);
}
