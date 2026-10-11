import 'package:flutter/material.dart';

Widget buildPaywallImage({
  required String source,
  double? width,
  double? height,
  BoxFit? fit,
  ImageErrorWidgetBuilder? errorBuilder,
}) {
  return Image.network(
    source,
    width: width,
    height: height,
    fit: fit,
    errorBuilder: errorBuilder,
  );
}

ImageProvider<Object> createPaywallImageProvider(String source) {
  return NetworkImage(source);
}
