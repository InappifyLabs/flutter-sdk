import 'package:flutter/foundation.dart';

/// Token-free lifecycle state of the session owned by the selected backend.
///
/// Flutter applications should not infer authentication from a nullable
/// customer snapshot. In particular, [temporarilyUnavailable] means that the
/// last authoritative customer state must be preserved while the operation is
/// retried; it does not mean that the customer became anonymous.
enum InappifySessionState {
  unconfigured,
  configuring,
  anonymous,
  authenticated,
  refreshing,
  temporarilyUnavailable,
  recoveryRequired,
  unknown;

  /// Stable value used by JavaScript and MethodChannel adapters.
  String get wireName => switch (this) {
    InappifySessionState.unconfigured => 'unconfigured',
    InappifySessionState.configuring => 'configuring',
    InappifySessionState.anonymous => 'anonymous',
    InappifySessionState.authenticated => 'authenticated',
    InappifySessionState.refreshing => 'refreshing',
    InappifySessionState.temporarilyUnavailable => 'temporarily-unavailable',
    InappifySessionState.recoveryRequired => 'recovery-required',
    InappifySessionState.unknown => 'unknown',
  };

  /// Decodes a backend value without throwing for future SDK additions.
  static InappifySessionState fromWire(Object? value) {
    return switch (value) {
      'unconfigured' => InappifySessionState.unconfigured,
      'configuring' => InappifySessionState.configuring,
      'anonymous' => InappifySessionState.anonymous,
      'authenticated' => InappifySessionState.authenticated,
      'refreshing' => InappifySessionState.refreshing,
      'temporarily-unavailable' ||
      'temporarily_unavailable' => InappifySessionState.temporarilyUnavailable,
      'recovery-required' ||
      'recovery_required' => InappifySessionState.recoveryRequired,
      _ => InappifySessionState.unknown,
    };
  }
}

/// Persistence guarantees reported by the session-owning backend.
enum InappifySessionPersistenceMode {
  /// The backend did not expose a persistence guarantee.
  unknown,

  /// Session restoration is backed by durable platform storage.
  durable,

  /// The session exists only for the current process/page lifetime.
  memory;

  String get wireName => name;

  static InappifySessionPersistenceMode fromWire(Object? value) {
    return switch (value) {
      'durable' => InappifySessionPersistenceMode.durable,
      'memory' => InappifySessionPersistenceMode.memory,
      _ => InappifySessionPersistenceMode.unknown,
    };
  }
}

/// Non-sensitive metadata carried by a session-state event.
@immutable
class InappifySessionStateChange {
  const InappifySessionStateChange({
    required this.state,
    required this.isRetryable,
    this.reason,
  });

  final InappifySessionState state;
  final bool isRetryable;

  /// Stable provider reason code. This value never contains session tokens.
  final String? reason;

  Map<String, Object?> toMap() => <String, Object?>{
    'state': state.wireName,
    'retryable': isRetryable,
    if (reason != null) 'reason': reason,
  };

  factory InappifySessionStateChange.fromMap(Map<String, dynamic> map) {
    final rawState = map['state'];
    final retryable = map['retryable'];
    final reason = map['reason'];
    if (rawState is! String || retryable is! bool) {
      throw const FormatException(
        'Session state event requires string state and bool retryable fields.',
      );
    }
    if (reason != null && reason is! String) {
      throw const FormatException(
        'Session state event reason must be a string or null.',
      );
    }
    final state = InappifySessionState.fromWire(rawState);
    if (state == InappifySessionState.unknown) {
      throw FormatException('Unsupported Inappify session state: $rawState.');
    }
    return InappifySessionStateChange(
      state: state,
      isRetryable: retryable,
      reason: reason as String?,
    );
  }
}

/// Creates a fresh, short-lived Identity Ticket on demand.
///
/// The callback must request the ticket from a trusted backend immediately
/// before returning it. The Flutter SDK invokes it only when an authenticated
/// host session needs to be established or recovered and never persists the
/// returned value.
typedef InappifyIdentityTicketProvider = Future<String> Function();
