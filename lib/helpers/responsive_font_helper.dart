import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'dart:math';

class ResponsiveFontHelper {
  static const double _baseFontSize = 16.0;
  static const double _smallScreenThreshold = 4.0; // inches
  static const double _mediumScreenThreshold = 6.0; // inches
  static const double _largeScreenThreshold = 8.0; // inches

  /// Calculate responsive font size based on screen size and device characteristics
  static double getResponsiveFontSize({
    required BuildContext context,
    double? baseSize,
    double? minSize,
    double? maxSize,
    bool isTitle = false,
    bool isSubtitle = false,
    bool isBody = false,
    bool isCaption = false,
  }) {
    final mediaQuery = MediaQuery.of(context);
    final size = mediaQuery.size;
    final pixelRatio = mediaQuery.devicePixelRatio;
    final textScaleFactor = mediaQuery.textScaleFactor;

    // Calculate screen diagonal in inches
    final screenDiagonalInches =
        _calculateScreenDiagonalInches(size, pixelRatio);

    // Base font size calculation
    double calculatedSize = baseSize ?? _baseFontSize;

    // Apply screen size multiplier
    double screenMultiplier = _getScreenSizeMultiplier(screenDiagonalInches);

    // Apply type-specific multipliers
    if (isTitle) {
      calculatedSize *= 1.8;
    } else if (isSubtitle) {
      calculatedSize *= 1.4;
    } else if (isBody) {
      calculatedSize *= 1.0;
    } else if (isCaption) {
      calculatedSize *= 0.8;
    }

    // Apply responsive scaling
    calculatedSize *= screenMultiplier;

    // Apply text scale factor for accessibility
    calculatedSize *= textScaleFactor;

    // Apply minimum and maximum constraints
    if (minSize != null && calculatedSize < minSize) {
      calculatedSize = minSize;
    }
    if (maxSize != null && calculatedSize > maxSize) {
      calculatedSize = maxSize;
    }

    return calculatedSize;
  }

  /// Calculate screen diagonal in inches
  static double _calculateScreenDiagonalInches(Size size, double pixelRatio) {
    // Use logical pixels to compute inches. In Flutter, 1 inch ≈ 160 logical px on mobile.
    // Web follows CSS where 1 inch = 96 logical px.
    final diagonalLogical =
        sqrt(size.width * size.width + size.height * size.height);

    final double logicalPixelsPerInch = kIsWeb
        ? 96.0
        : (defaultTargetPlatform == TargetPlatform.iOS
            ? 163.0 // closer to iOS points-per-inch baseline
            : 160.0); // Android and others baseline

    return diagonalLogical / logicalPixelsPerInch;
  }

  /// Get screen size multiplier based on diagonal size
  static double _getScreenSizeMultiplier(double screenDiagonalInches) {
    if (screenDiagonalInches < _smallScreenThreshold) {
      // Small phones (4-5 inches)
      return 0.85;
    } else if (screenDiagonalInches < _mediumScreenThreshold) {
      // Medium phones (5-6 inches)
      return 1.0;
    } else if (screenDiagonalInches < _largeScreenThreshold) {
      // Large phones (6-8 inches)
      return 1.15;
    } else {
      // Tablets and larger devices (8+ inches)
      return 1.3;
    }
  }

  /// Get responsive text style for different text types
  static TextStyle getResponsiveTextStyle({
    required BuildContext context,
    double? baseSize,
    double? minSize,
    double? maxSize,
    bool isTitle = false,
    bool isSubtitle = false,
    bool isBody = false,
    bool isCaption = false,
    Color? color,
    FontWeight? fontWeight,
    List<Shadow>? shadows,
    TextDecoration? decoration,
    String? fontFamily,
  }) {
    return TextStyle(
      fontSize: getResponsiveFontSize(
        context: context,
        baseSize: baseSize,
        minSize: minSize,
        maxSize: maxSize,
        isTitle: isTitle,
        isSubtitle: isSubtitle,
        isBody: isBody,
        isCaption: isCaption,
      ),
      color: color,
      fontWeight: fontWeight,
      shadows: shadows,
      decoration: decoration,
      fontFamily: fontFamily,
    );
  }

  /// Get device-specific font size adjustments
  static double getDeviceFontMultiplier(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final size = mediaQuery.size;
    final pixelRatio = mediaQuery.devicePixelRatio;

    // final screenDiagonalInches =
    //     _calculateScreenDiagonalInches(size, pixelRatio); // currently unused

    // Additional adjustments based on device characteristics
    double multiplier = 1.0;

    // Adjust for high-density displays
    if (pixelRatio > 3.0) {
      multiplier *= 0.9; // Slightly smaller on very high DPI displays
    } else if (pixelRatio < 2.0) {
      multiplier *= 1.1; // Slightly larger on lower DPI displays
    }

    // Adjust for screen orientation
    if (size.width > size.height) {
      // Landscape mode
      multiplier *= 1.05;
    }

    return multiplier;
  }

  /// Get optimal font size for design text elements
  static double getDesignTextFontSize({
    required BuildContext context,
    required double originalFontSize,
    bool isMainTitle = false,
    bool isSubtitle = false,
    bool isBodyText = false,
  }) {
    final responsiveSize = getResponsiveFontSize(
      context: context,
      baseSize: originalFontSize,
      minSize: originalFontSize * 0.7,
      maxSize: originalFontSize * 1.5,
      isTitle: isMainTitle,
      isSubtitle: isSubtitle,
      isBody: isBodyText,
    );

    // Apply device-specific adjustments
    final deviceMultiplier = getDeviceFontMultiplier(context);

    return responsiveSize * deviceMultiplier;
  }

  /// Debug method to get device information
  static Map<String, dynamic> getDeviceInfo(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final size = mediaQuery.size;
    final pixelRatio = mediaQuery.devicePixelRatio;
    final screenDiagonalInches =
        _calculateScreenDiagonalInches(size, pixelRatio);
    final screenMultiplier = _getScreenSizeMultiplier(screenDiagonalInches);
    final deviceMultiplier = getDeviceFontMultiplier(context);

    return {
      'screenSize':
          '${size.width.toStringAsFixed(1)} x ${size.height.toStringAsFixed(1)}',
      'pixelRatio': pixelRatio.toStringAsFixed(2),
      'screenDiagonalInches': screenDiagonalInches.toStringAsFixed(2),
      'screenMultiplier': screenMultiplier.toStringAsFixed(2),
      'deviceMultiplier': deviceMultiplier.toStringAsFixed(2),
      'textScaleFactor': mediaQuery.textScaleFactor.toStringAsFixed(2),
      'orientation': size.width > size.height ? 'Landscape' : 'Portrait',
    };
  }
}
