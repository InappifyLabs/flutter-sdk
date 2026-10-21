import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inappify_sdk/inappify_sdk.dart';
import 'package:inappify_sdk/inappify_sdk_method_channel.dart';
import 'package:inappify_sdk/src/logging/sdk_logger.dart';
import 'package:inappify_sdk/src/platform/channel/native_callbacks.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('inappify_sdk');
  const codec = StandardMethodCodec();
  late List<MethodCall> calls;
  late InappifyLogLevel oldLevel;
  late InappifyLogHandler? oldHandler;

  Future<Object?> callback(String method, Object? arguments) async {
    final result = Completer<ByteData?>();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage(
          'inappify_sdk',
          codec.encodeMethodCall(MethodCall(method, arguments)),
          result.complete,
        );
    final bytes = await result.future;
    return bytes == null ? null : codec.decodeEnvelope(bytes);
  }

  setUp(() {
    oldLevel = SdkLogger.level;
    oldHandler = SdkLogger.handler;
    calls = [];
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          if (call.method == 'sdkSetConsumableDeliveryHandler') {
            final args = call.arguments as Map;
            return {
              'protocolVersion': 1,
              'requestId': args['requestId'],
              'ok': true,
              'data': <String, Object?>{},
              'snapshot': const InappifySdkSnapshot().toMap(),
            };
          }
          return null;
        });
  });

  tearDown(() {
    SdkLogger.level = oldLevel;
    SdkLogger.handler = oldHandler;
    NativeCallbacks.delivery = null;
    channel.setMethodCallHandler(null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    debugDefaultTargetPlatformOverride = null;
  });

  test(
    'logging config works before configure and severity is a minimum',
    () async {
      final seen = <InappifyLogLevel>[];
      await InappifySdk.setLogHandler((level, _) => seen.add(level));
      await InappifySdk.setLogLevel(InappifyLogLevel.info);
      for (final level in InappifyLogLevel.values)
        SdkLogger.log(level, 'Safe event.');
      expect(seen, [
        InappifyLogLevel.info,
        InappifyLogLevel.warn,
        InappifyLogLevel.error,
      ]);
      expect(calls.map((call) => call.method), [
        'sdkSetLogHandler',
        'sdkSetLogLevel',
      ]);
      expect(calls.last.arguments, {'level': 'INFO'});
    },
  );

  test(
    'native callbacks respect filtering and malformed messages are ignored',
    () async {
      final seen = <String>[];
      await InappifySdk.setLogLevel(InappifyLogLevel.warn);
      await InappifySdk.setLogHandler((_, message) => seen.add(message));
      await callback('sdkLog', {'level': 'DEBUG', 'message': 'Filtered.'});
      await callback('sdkLog', {
        'level': 'ERROR',
        'message': 'Safe native error.',
      });
      await callback('sdkLog', {'level': 'INVALID', 'message': 'Ignore.'});
      await callback('sdkLog', {'level': 'ERROR', 'message': 123});
      expect(seen, ['Safe native error.']);
    },
  );

  test('custom handler replaces console and null restores it', () async {
    final console = <String>[];
    final originalPrint = debugPrint;
    debugPrint = (message, {wrapWidth}) {
      if (message != null) console.add(message);
    };
    try {
      await InappifySdk.setLogLevel(InappifyLogLevel.info);
      await InappifySdk.setLogHandler((_, _) {});
      SdkLogger.info('Handled.');
      expect(console, isEmpty);
      await InappifySdk.setLogHandler(null);
      SdkLogger.info('Console event.');
      expect(console.single, contains('[Inappify] - INFO: Console event.'));
      expect(calls.last.arguments, {'enabled': false});
    } finally {
      debugPrint = originalPrint;
    }
  });

  test('throwing and recursive handlers do not affect SDK callers', () async {
    await InappifySdk.setLogHandler((_, _) => throw StateError('Host failure'));
    expect(() => SdkLogger.error('Safe error.'), returnsNormally);
    var count = 0;
    await InappifySdk.setLogHandler((_, _) {
      count++;
      SdkLogger.error('Recursive.');
    });
    SdkLogger.error('Outer.');
    expect(count, 1);
  });

  test(
    'installing and removing logs never replaces consumable delivery',
    () async {
      var deliveries = 0;
      final platform = MethodChannelInappifySdk(methodChannel: channel);
      await platform.setConsumableDeliveryHandler((_) async {
        deliveries++;
        return InappifyDeliveryResult.delivered;
      });
      await InappifySdk.setLogHandler((_, _) {});
      final data = {
        'deliveryId': 44,
        'productIdentifier': 'coins',
        'source': 'DIRECT',
      };
      expect(await callback('sdkConsumableDelivery', data), 'delivered');
      await InappifySdk.setLogHandler(null);
      expect(await callback('sdkConsumableDelivery', data), 'delivered');
      expect(deliveries, 2);
    },
  );

  test(
    'iOS logging stays in Dart and makes no Android channel calls',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      final seen = <String>[];
      await InappifySdk.setLogLevel(InappifyLogLevel.debug);
      await InappifySdk.setLogHandler((_, message) => seen.add(message));
      SdkLogger.debug('Direct recovery started.');
      expect(seen, ['Direct recovery started.']);
      expect(calls, isEmpty);
    },
  );
}
