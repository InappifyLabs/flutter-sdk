import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:inappify_sdk/models/log_level.dart';

/// Shared diagnostics only; this class owns no SDK session or purchase state.
abstract final class SdkLogger {
  static InappifyLogLevel level = kDebugMode
      ? InappifyLogLevel.debug
      : InappifyLogLevel.info;
  static InappifyLogHandler? handler;
  static bool _delivering = false;

  static void log(InappifyLogLevel severity, String message) {
    if (severity.index < level.index || _delivering) return;
    _delivering = true;
    try {
      final bounded = message.length > 2048
          ? message.substring(0, 2048)
          : message;
      final target = handler;
      if (target == null) {
        debugPrint('[Inappify] - ${severity.name.toUpperCase()}: $bounded');
      } else {
        runZonedGuarded(() => target(severity, bounded), (_, _) {});
      }
    } catch (_) {
      // Diagnostic failures must not change SDK results or fulfillment.
    } finally {
      _delivering = false;
    }
  }

  static void verbose(String message) => log(InappifyLogLevel.verbose, message);
  static void debug(String message) => log(InappifyLogLevel.debug, message);
  static void info(String message) => log(InappifyLogLevel.info, message);
  static void warn(String message) => log(InappifyLogLevel.warn, message);
  static void error(String message) => log(InappifyLogLevel.error, message);

  static void receiveNative(Object? arguments) {
    // A detached/replaced handler must not duplicate native console output.
    if (handler == null || arguments is! Map) return;
    final rawLevel = arguments['level'];
    final message = arguments['message'];
    if (rawLevel is! String || message is! String || message.length > 2048)
      return;
    for (final value in InappifyLogLevel.values) {
      if (value.name.toUpperCase() == rawLevel) {
        log(value, message);
        return;
      }
    }
  }
}
