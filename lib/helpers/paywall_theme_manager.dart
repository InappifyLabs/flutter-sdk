import 'package:inappify_sdk/src/logging/sdk_logger.dart';
import 'package:flutter/material.dart';
import '../models/paywall_asset.dart';

class PaywallThemeManager {
  final Map<String, PaywallAsset> _assetsMap;

  PaywallThemeManager(List<PaywallAsset>? assets)
      : _assetsMap = {for (var asset in assets ?? []) asset.id!: asset};

  Color? _toColor(String? hexString, [double defaultOpacity = 1.0]) {
    if (hexString == null || hexString.isEmpty) return null;
    String hex = hexString.replaceAll("#", "");
    if (hex.length == 6) {
      hex = "FF$hex"; // Add alpha if not present (fully opaque)
    }
    try {
      return Color(int.parse(hex, radix: 16)).withOpacity(defaultOpacity);
    } catch (e) {
      SdkLogger.error('Paywall color parsing failed.');
      return null;
    }
  }

  Color? getColor(String? id) {
    if (id == null) return null;
    final asset = _assetsMap[id];
    if (asset?.type == 'color') {
      final double opacity = asset?.opacity?.toDouble() ?? 1.0;
      return _toColor(asset?.value, opacity);
    }
    return null;
  }

  TextStyle? getTextStyle(String? fontId, String? colorId,
      {String? customFontFamily}) {
    if (fontId == null && colorId == null) return null;

    final fontAsset = _assetsMap[fontId];
    final colorAsset = _assetsMap[colorId];

    Color? color;
    if (colorAsset?.type == 'color') {
      final double opacity = colorAsset?.opacity?.toDouble() ?? 1.0;
      color = _toColor(colorAsset?.value, opacity);
    }

    double? fontSize;
    if (fontAsset?.type == 'font') {
      fontSize = double.tryParse(fontAsset?.size ?? '');
    }

    if (color == null && fontSize == null) return null;

    return TextStyle(
      color: color,
      fontSize: fontSize,
      fontFamily: customFontFamily,
      // FontWeight, FontStyle و موارد دیگر را می‌توانید اضافه کنید اگر در JSON باشند.
    );
  }

  BoxDecoration? getBoxDecoration(String? backgroundId, String? borderId,
      List<int>? cornerRadius, String? borderThickness) {
    final backgroundColor = getColor(backgroundId);
    final borderColor = getColor(borderId);

    final double thickness = double.tryParse(borderThickness ?? '0') ?? 0;

    if (backgroundColor == null &&
        borderColor == null &&
        thickness == 0 &&
        (cornerRadius == null || cornerRadius.isEmpty)) {
      return null;
    }

    BorderRadius? borderRadius;
    if (cornerRadius != null && cornerRadius.length == 4) {
      borderRadius = BorderRadius.only(
        topLeft: Radius.circular(cornerRadius[0].toDouble()),
        topRight: Radius.circular(cornerRadius[1].toDouble()),
        bottomRight: Radius.circular(cornerRadius[2].toDouble()),
        bottomLeft: Radius.circular(cornerRadius[3].toDouble()),
      );
    }

    return BoxDecoration(
      color: backgroundColor,
      borderRadius: borderRadius,
      border: borderColor != null && thickness > 0
          ? Border.all(color: borderColor, width: thickness)
          : null,
    );
  }

  EdgeInsetsGeometry getPadding(List<int>? padding) {
    if (padding == null || padding.length != 4) return EdgeInsets.zero;
    return EdgeInsets.fromLTRB(
      padding[3].toDouble(), // Left
      padding[0].toDouble(), // Top
      padding[1].toDouble(), // Right
      padding[2].toDouble(), // Bottom
    );
  }

  EdgeInsetsGeometry getMargin(List<int>? margin) {
    if (margin == null || margin.length != 4) return EdgeInsets.zero;
    return EdgeInsets.fromLTRB(
      margin[3].toDouble(), // Left
      margin[0].toDouble(), // Top
      margin[1].toDouble(), // Right
      margin[2].toDouble(), // Bottom
    );
  }
}
