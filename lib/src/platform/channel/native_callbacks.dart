import 'package:flutter/services.dart';
import 'package:inappify_sdk/src/logging/sdk_logger.dart';
import 'channel_contract.dart';

/// One callback dispatcher so installing a log handler cannot replace delivery.
abstract final class NativeCallbacks {
  static Future<Object?> Function(MethodCall call)? delivery;

  static void install(MethodChannel channel) {
    channel.setMethodCallHandler((call) async {
      if (call.method == InappifyChannelContract.logCallback) {
        SdkLogger.receiveNative(call.arguments);
        return null;
      }
      if (call.method == InappifyChannelContract.consumableDeliveryCallback) {
        return await delivery?.call(call) ?? 'retryLater';
      }
      throw MissingPluginException();
    });
  }
}
