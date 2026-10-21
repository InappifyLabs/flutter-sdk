import 'package:inappify_sdk/src/logging/sdk_logger.dart';
// lib/helpers/paywall_assets_helper.dart
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:inappify_sdk/helpers/paywall_assets_downloader.dart';
import 'package:inappify_sdk/models/paywall_asset.dart';
import 'package:collection/collection.dart';
import 'package:inappify_sdk/helpers/responsive_font_helper.dart';

class PaywallAssetsHelper {
  static Color? toColor(String? hexString, [double assetOpacity = 1.0]) {
    if (hexString == null || hexString.isEmpty) {
      return null;
    }

    String formattedHex = hexString.replaceAll("#", "");
    String finalHexAARRGGBB;

    if (formattedHex.length == 6) {
      // It's RRGGBB, prepend full alpha FF
      finalHexAARRGGBB = "FF$formattedHex";
    } else if (formattedHex.length == 8) {
      // It's RRGGBBAA, reorder to AARRGGBB
      String alphaHex =
          formattedHex.substring(6, 8); // Last two chars are alpha
      String rgbHex = formattedHex.substring(0, 6); // First six chars are RGB
      finalHexAARRGGBB = "$alphaHex$rgbHex";
    } else {
      return null;
    }

    try {
      final int parsedValue = int.parse('0x$finalHexAARRGGBB');
      final Color color = Color(parsedValue);
      final Color finalColor = color.withOpacity(assetOpacity);
      return finalColor;
    } catch (e) {
      return null;
    }
  }

  /// Parse a CSS-like linear-gradient string into a Flutter LinearGradient.
  ///
  /// Supported format example:
  ///   linear-gradient(180deg, rgba(0, 0, 0, 0) 0%, rgba(0, 0, 0, 1) 100%)
  ///
  /// If parsing fails, returns null.
  static LinearGradient? _parseCssLinearGradient(String? gradientString) {
    if (gradientString == null) return null;
    final String input = gradientString.trim();
    if (!input.startsWith('linear-gradient(') || !input.endsWith(')')) {
      return null;
    }

    // Strip outer wrapper
    final String inner =
        input.substring('linear-gradient('.length, input.length - 1).trim();

    // Split first comma (angle) from the color stops (need to respect parentheses for rgba())
    int depth = 0;
    int commaIndex = -1;
    for (int i = 0; i < inner.length; i++) {
      final ch = inner[i];
      if (ch == '(') depth++;
      if (ch == ')') depth--;
      if (ch == ',' && depth == 0) {
        commaIndex = i;
        break;
      }
    }
    if (commaIndex == -1) return null;

    final String anglePart = inner.substring(0, commaIndex).trim();
    final String stopsPart = inner.substring(commaIndex + 1).trim();

    // Parse angle (only deg supported for now)
    double cssAngleDeg = 180.0; // default
    final angleMatch = RegExp(r'(-?\d+(?:\.\d+)?)\s*deg').firstMatch(anglePart);
    if (angleMatch != null) {
      cssAngleDeg = double.tryParse(angleMatch.group(1)!) ?? 180.0;
    }

    // Convert CSS angle to Flutter begin/end alignments
    // CSS: 0deg -> to top, 90deg -> to right, 180deg -> to bottom, 270deg -> to left
    // Map to Flutter Alignment where y: -1 top, +1 bottom
    final double rad = cssAngleDeg * math.pi / 180.0;
    final double dx = math.sin(rad);
    final double dy = -math.cos(rad);
    final Alignment end = Alignment(dx.clamp(-1.0, 1.0), dy.clamp(-1.0, 1.0));
    final Alignment begin =
        Alignment(-dx.clamp(-1.0, 1.0), -dy.clamp(-1.0, 1.0));

    // Split stops by top-level commas
    final List<String> stopTokens = _splitTopLevelByComma(stopsPart);
    if (stopTokens.isEmpty) return null;

    final List<Color> colors = <Color>[];
    final List<double> stops = <double>[];

    for (final tokenRaw in stopTokens) {
      final String token = tokenRaw.trim();
      // Expect format: rgba(r,g,b,a) <percent>%  OR hex with optional percent
      final rgbaMatch = RegExp(
        r'rgba\(\s*(\d+)\s*,\s*(\d+)\s*,\s*(\d+)\s*,\s*([0-1]?(?:\.\d+)?)\s*\)\s*(\d+)%?',
      ).firstMatch(token);

      if (rgbaMatch != null) {
        final int r = int.parse(rgbaMatch.group(1)!);
        final int g = int.parse(rgbaMatch.group(2)!);
        final int b = int.parse(rgbaMatch.group(3)!);
        final double a = double.parse(rgbaMatch.group(4)!);
        final String? percentStr = rgbaMatch.group(5);
        final double? percent =
            percentStr != null ? double.tryParse(percentStr) : null;

        colors.add(Color.fromRGBO(r, g, b, a));
        if (percent != null) {
          stops.add((percent / 100.0).clamp(0.0, 1.0));
        }
        continue;
      }

      // Hex color with optional alpha, and optional percentage
      final hexMatch =
          RegExp(r'(#[0-9A-Fa-f]{6,8})\s*(\d+)%?').firstMatch(token);
      if (hexMatch != null) {
        final String hex = hexMatch.group(1)!;
        final String? percentStr = hexMatch.group(2);
        final Color? c = toColor(hex);
        if (c != null) colors.add(c);
        if (percentStr != null) {
          final double? percent = double.tryParse(percentStr);
          if (percent != null) stops.add((percent / 100.0).clamp(0.0, 1.0));
        }
        continue;
      }

      // Fallback: try pure rgba() without percentage
      final rgbaNoStopMatch = RegExp(
        r'rgba\(\s*(\d+)\s*,\s*(\d+)\s*,\s*(\d+)\s*,\s*([0-1]?(?:\.\d+)?)\s*\)',
      ).firstMatch(token);
      if (rgbaNoStopMatch != null) {
        final int r = int.parse(rgbaNoStopMatch.group(1)!);
        final int g = int.parse(rgbaNoStopMatch.group(2)!);
        final int b = int.parse(rgbaNoStopMatch.group(3)!);
        final double a = double.parse(rgbaNoStopMatch.group(4)!);
        colors.add(Color.fromRGBO(r, g, b, a));
        continue;
      }
    }

    if (colors.isEmpty) return null;

    return LinearGradient(
      begin: begin,
      end: end,
      colors: colors,
      stops: stops.length == colors.length ? stops : null,
    );
  }

  /// Split a string by commas not enclosed in parentheses.
  static List<String> _splitTopLevelByComma(String input) {
    final List<String> parts = <String>[];
    int depth = 0;
    final StringBuffer current = StringBuffer();
    for (int i = 0; i < input.length; i++) {
      final String ch = input[i];
      if (ch == '(') depth++;
      if (ch == ')') depth--;
      if (ch == ',' && depth == 0) {
        parts.add(current.toString());
        current.clear();
        continue;
      }
      current.write(ch);
    }
    if (current.isNotEmpty) parts.add(current.toString());
    return parts;
  }

  /// Resolve a gradient asset by id. The asset's value must be a CSS-like
  /// linear-gradient(...) string. Returns null if not found or unparsable.
  static LinearGradient? getPaywallAssetLinearGradient(
      List<PaywallAsset> assets, String? assetId) {
    if (assetId == null || assetId.isEmpty || assets.isEmpty) return null;

    final PaywallAsset? asset = assets.firstWhereOrNull((a) =>
        a.id == assetId && (a.value?.contains('linear-gradient(') ?? false));
    if (asset == null) return null;

    return _parseCssLinearGradient(asset.value);
  }

  // ... (rest of PaywallAssetsHelper methods remain unchanged) ...
  static Color? getPaywallAssetColor(
      List<PaywallAsset> assets, String? assetId) {
    if (assetId == null || assets.isEmpty) return null;

    final asset =
        assets.firstWhereOrNull((e) => e.id == assetId && e.type == 'color');
    if (asset != null && asset.value != null) {
      final double opacity = asset.opacity?.toDouble() ?? 1.0;
      final Color? resolvedColor = toColor(
        asset.value,
        opacity,
      );
      return resolvedColor;
    }
    return null;
  }

  static double? getPaywallAssetFontSize(
      List<PaywallAsset> assets, String? assetId) {
    if (assetId == null || assets.isEmpty) return null;
    final asset =
        assets.firstWhereOrNull((e) => e.id == assetId && e.type == 'font');
    if (asset != null && asset.size != null) {
      final double? resolvedSize = double.tryParse(asset.size!);
      return resolvedSize;
    }
    return null;
  }

  static Future<String?> getPaywallAssetUrl(
      List<PaywallAsset> assets, String? assetId) async {
    if (assetId == null || assets.isEmpty) return null;
    final asset =
        assets.firstWhereOrNull((e) => e.id == assetId && e.type == 'assets');

    if (asset?.url == null) return null;

    // Try to get cached version first
    final cachedPath =
        await PaywallAssetsDownloader.getLocalAssetPath(asset!.url!);
    if (cachedPath != null) {
      SdkLogger.debug('Using cached paywall asset.');
      return cachedPath;
    }

    // Fallback to original URL
    SdkLogger.debug('Using remote paywall asset.');
    return asset.url;
  }

  // Sync version for backward compatibility
  static String? getPaywallAssetUrlSync(
      List<PaywallAsset> assets, String? assetId) {
    if (assetId == null || assets.isEmpty) return null;
    final asset =
        assets.firstWhereOrNull((e) => e.id == assetId && e.type == 'assets');
    return asset?.url;
  }

  /// Get text content from assets by asset ID
  static String? getPaywallAssetText(
      List<PaywallAsset> assets, String? assetId) {
    if (assetId == null || assets.isEmpty) return null;
    final asset =
        assets.firstWhereOrNull((e) => e.id == assetId && e.type == 'text');
    return asset?.value;
  }

  static TextStyle? getTextStyle(
      List<PaywallAsset> assets, String? fontId, String? colorId,
      {bool isRTL = false, BuildContext? context, String? customFontFamily}) {
    if ((fontId == null || fontId.isEmpty) &&
        (colorId == null || colorId.isEmpty)) return null;

    final Color? color = getPaywallAssetColor(assets, colorId);
    final double originalFontSize =
        getPaywallAssetFontSize(assets, fontId) ?? 14;

    // Use responsive font size if context is provided
    double? finalFontSize = originalFontSize;
    if (context != null) {
      finalFontSize = ResponsiveFontHelper.getResponsiveFontSize(
        context: context,
        baseSize: originalFontSize,
        minSize: originalFontSize * 0.7,
        maxSize: originalFontSize * 1.5,
      );
    }

    return TextStyle(
        color: color ?? Colors.black,
        fontSize: finalFontSize,
        fontFamily: customFontFamily ?? (isRTL ? 'Vazirmatn' : null),
        height: 1.7 // Use custom font family or Persian font for RTL
        );
  }

  static BoxDecoration? getBoxDecoration(
      List<PaywallAsset> assets,
      String? backgroundId,
      String? borderId,
      List<int>? cornerRadius,
      String? borderThickness) {
    final backgroundColor = getPaywallAssetColor(assets, backgroundId);
    final borderColor = getPaywallAssetColor(assets, borderId);

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

  static EdgeInsetsGeometry getPadding(List<int>? padding) {
    if (padding == null || padding.length != 4) return EdgeInsets.zero;
    return EdgeInsets.fromLTRB(
      padding[3].toDouble(), // Left
      padding[0].toDouble(), // Top
      padding[1].toDouble(), // Right
      padding[2].toDouble(), // Bottom
    );
  }

  static EdgeInsetsGeometry getMargin(List<int>? margin) {
    if (margin == null || margin.length != 4) return EdgeInsets.zero;
    return EdgeInsets.fromLTRB(
      margin[3].toDouble(), // Left
      margin[0].toDouble(), // Top
      margin[1].toDouble(), // Right
      margin[2].toDouble(), // Bottom
    );
  }
}
