import 'package:flutter/material.dart';
import 'package:inappify_sdk/src/paywall/assets/paywall_image_loader_stub.dart'
    if (dart.library.io) 'package:inappify_sdk/src/paywall/assets/paywall_image_loader_io.dart'
    as implementation;

/// Builds paywall images without exposing file-system types to browser builds.
Widget buildPaywallImage({
  required String source,
  double? width,
  double? height,
  BoxFit? fit,
  ImageErrorWidgetBuilder? errorBuilder,
}) {
  return implementation.buildPaywallImage(
    source: source,
    width: width,
    height: height,
    fit: fit,
    errorBuilder: errorBuilder,
  );
}

/// Creates an image provider suitable for the active Dart runtime.
ImageProvider<Object> createPaywallImageProvider(String source) {
  return implementation.createPaywallImageProvider(source);
}
