import 'dart:io';

import 'package:flutter/material.dart';

Widget buildPaywallImage({
  required String source,
  double? width,
  double? height,
  BoxFit? fit,
  ImageErrorWidgetBuilder? errorBuilder,
}) {
  if (_isNetworkSource(source)) {
    return Image.network(
      source,
      width: width,
      height: height,
      fit: fit,
      errorBuilder: errorBuilder,
    );
  }
  return Image.file(
    File(source),
    width: width,
    height: height,
    fit: fit,
    errorBuilder: errorBuilder,
  );
}

ImageProvider<Object> createPaywallImageProvider(String source) {
  return _isNetworkSource(source)
      ? NetworkImage(source)
      : FileImage(File(source));
}

bool _isNetworkSource(String source) {
  return source.startsWith('http://') || source.startsWith('https://');
}
