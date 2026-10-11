// In order to *not* need this ignore, consider extracting the "web" version
// of your plugin as a separate package, instead of inlining it in the same
// package as the core of your plugin.
// ignore: avoid_web_libraries_in_flutter

import 'package:flutter_web_plugins/flutter_web_plugins.dart';
import 'package:inappify_sdk/src/platform/web/javascript_inappify_bridge.dart';
import 'package:inappify_sdk/src/platform/web/web_inappify_bridge.dart';
import 'package:inappify_sdk/src/platform/web/web_inappify_platform.dart';
import 'package:web/web.dart' as web;

import 'inappify_sdk_platform_interface.dart' show InappifySdkPlatform;

/// Browser plugin entry backed by the official Inappify JavaScript SDK.
///
/// The adapter becomes eligible during capability negotiation only when the
/// host page has installed the documented ESM bridge before Flutter starts.
/// Otherwise the process uses the complete Dart fallback for the full session.
class InappifySdkWeb extends WebInappifyPlatform {
  /// Creates the browser platform candidate.
  ///
  /// [bridge] is injectable for browser contract tests. Production plugin
  /// registration uses [JavaScriptInappifyBridge].
  InappifySdkWeb({InappifyWebBridge? bridge})
    : super(bridge: bridge ?? JavaScriptInappifyBridge());

  /// Registers the browser candidate with Flutter's plugin registrar.
  static void registerWith(Registrar registrar) {
    InappifySdkPlatform.instance = InappifySdkWeb();
  }

  /// Returns a [String] containing the version of the platform.
  @override
  Future<String?> getPlatformVersion() async {
    final version = web.window.navigator.userAgent;
    return version;
  }
}
