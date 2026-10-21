import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:inappify_sdk/models/log_level.dart';
import 'package:inappify_sdk/src/platform/channel/channel_contract.dart';
import 'package:inappify_sdk/src/platform/channel/native_callbacks.dart';
import 'sdk_logger.dart';

abstract final class NativeLogging {
  static const channel = MethodChannel(InappifyChannelContract.channelName);
  static Future<void> _tail = Future<void>.value();
  static bool get _android =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  static Future<void> _serial(Future<void> Function() action) {
    final next = _tail.then((_) => action());
    _tail = next.then<void>((_) {}, onError: (Object _) {});
    return next;
  }

  static Future<void> setLevel(InappifyLogLevel level) => _serial(() async {
    if (_android) {
      await channel.invokeMethod<void>(InappifyChannelContract.setLogLevel, {
        'level': level.name.toUpperCase(),
      });
    }
    SdkLogger.level = level;
  });

  static Future<void> setHandler(InappifyLogHandler? handler) =>
      _serial(() async {
        final previous = SdkLogger.handler;
        SdkLogger.handler = handler;
        try {
          if (_android) {
            NativeCallbacks.install(channel);
            await channel.invokeMethod<void>(
              InappifyChannelContract.setLogHandler,
              {'enabled': handler != null},
            );
          }
        } catch (_) {
          SdkLogger.handler = previous;
          rethrow;
        }
      });
}
