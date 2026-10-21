import 'package:inappify_sdk/src/logging/sdk_logger.dart';
// lib/helpers/localization_helper.dart
import 'package:flutter/material.dart';
import 'package:inappify_sdk/models/paywall_localization.dart';
import 'package:inappify_sdk/models/offering_packages.dart';
import 'package:inappify_sdk/models/offering_packages_product.dart';
import 'package:collection/collection.dart'; // For firstWhereOrNull

/// Emits structural diagnostics without localized text, URLs or dynamic values.
void _debugLocalizationLog(String message) {
  SdkLogger.verbose('Paywall localization event.');
}

/// A helper class for resolving localized strings and dynamic tags.
class LocalizationHelper {
  final Map<String, Map<String, PaywallLocalizationString>> _localizedStrings;
  final Map<String, bool> _rtlLocales;
  String _currentLocale;

  /// Initializes the LocalizationHelper with a list of localizations and an initial locale.
  LocalizationHelper(
      List<PaywallLocalization> localizations, String initialLocale)
      : _localizedStrings = {
          for (var loc in localizations)
            loc.id!: {for (var str in loc.strings ?? []) str.id!: str}
        },
        _rtlLocales = {
          for (var loc in localizations) loc.id!: loc.rtl ?? false
        },
        _currentLocale = initialLocale;

  /// Sets the current locale for string resolution.
  void setCurrentLocale(String locale) {
    _currentLocale = locale;
  }

  /// Checks if the current locale is RTL
  bool get isRTL => _rtlLocales[_currentLocale] ?? false;

  /// Returns true if the given stringId exists for the effective locale
  bool hasStringId(String stringId, {String? currentLocale}) {
    final effectiveLocale = currentLocale ?? _currentLocale;
    final paywallString = _localizedStrings[effectiveLocale]?[stringId];
    return paywallString != null && paywallString.value != null;
  }

  /// Gets the raw localization value for rich text processing
  dynamic getLocalizationValue(String stringId) {
    final paywallString = _localizedStrings[_currentLocale]?[stringId];
    return paywallString?.value;
  }

  /// Formats price with Persian numerals if RTL
  String _formatPrice(String price, bool isRTL) {
    if (!isRTL) return price;

    // Parse the price as integer
    final int? priceInt = int.tryParse(price);
    if (priceInt == null) return price;

    // Format with commas
    String formattedPrice = priceInt.toString();
    final int length = formattedPrice.length;
    for (int i = length - 3; i > 0; i -= 3) {
      formattedPrice =
          formattedPrice.substring(0, i) + ',' + formattedPrice.substring(i);
    }

    // Convert English numerals to Persian numerals
    final persianNumerals = {
      '0': '۰',
      '1': '۱',
      '2': '۲',
      '3': '۳',
      '4': '۴',
      '5': '۵',
      '6': '۶',
      '7': '۷',
      '8': '۸',
      '9': '۹'
    };

    for (var entry in persianNumerals.entries) {
      formattedPrice = formattedPrice.replaceAll(entry.key, entry.value);
    }

    return formattedPrice;
  }

  /// Converts a localization value (String or List) to a TextSpan with support for attributes like bold, italic, underline, strike.
  static TextSpan buildLocalizedTextSpan(
    dynamic value,
    TextStyle baseStyle, {
    OfferingPackages? offeringPackage,
    OfferingPackagesProduct? product,
    String? currentLocale,
    bool isRTL = false,
  }) {
    if (value is List) {
      List<TextSpan> children = [];
      for (var part in value) {
        if (part == null) continue;
        if (part is String) {
          children.add(TextSpan(text: part, style: baseStyle));
        } else if (part is Map<String, dynamic>) {
          // Handle text with attributes
          if (part.containsKey('text')) {
            String text = part['text'] ?? '';
            Map<String, dynamic> attrs = part['attributes'] ?? {};
            TextStyle style = baseStyle;
            if (attrs['bold'] == true) {
              style = style.copyWith(fontWeight: FontWeight.bold);
            }
            if (attrs['italic'] == true) {
              style = style.copyWith(fontStyle: FontStyle.italic);
            }
            // Combine underline and strike if both are true
            if (attrs['underline'] == true && attrs['strike'] == true) {
              style = style.copyWith(
                  decoration: TextDecoration.combine(
                      [TextDecoration.underline, TextDecoration.lineThrough]));
            } else if (attrs['underline'] == true) {
              style = style.copyWith(decoration: TextDecoration.underline);
            } else if (attrs['strike'] == true) {
              style = style.copyWith(decoration: TextDecoration.lineThrough);
            }
            children.add(TextSpan(text: text, style: style));
          } else if (part.containsKey('tag')) {
            // Handle dynamic tags (e.g., PROD_TITLE, PROD_PRICE, etc.)
            final String? tag = part['tag'];
            String tagText = '';
            switch (tag) {
              case "PROD_TITLE":
                tagText = product?.name ?? 'N/A';
                break;
              case "PROD_PRICE":
                final priceObject = product?.prices
                        ?.firstWhereOrNull((p) => p.currency == 'IRR') ??
                    product?.prices
                        ?.firstWhereOrNull((p) => p.currency == 'USD') ??
                    product?.prices?.firstOrNull;
                final price = priceObject?.price?.toString() ?? 'N/A';
                tagText = isRTL ? _formatPriceStatic(price, true) : price;
                break;
              case "PROD_CURRENCY":
                final priceObject = product?.prices
                        ?.firstWhereOrNull((p) => p.currency == 'IRR') ??
                    product?.prices
                        ?.firstWhereOrNull((p) => p.currency == 'USD') ??
                    product?.prices?.firstOrNull;
                final String currencyText = priceObject?.currency ?? 'N/A';
                tagText =
                    isRTL && currencyText == 'IRR' ? 'تومان' : currencyText;
                break;
              case "PACK_DESCRIPTION":
                tagText = offeringPackage?.description ?? 'N/A';
                break;
              default:
                tagText = '[$tag]';
                break;
            }
            children.add(TextSpan(text: tagText, style: baseStyle));
          }
        }
      }
      return TextSpan(children: children, style: baseStyle);
    } else if (value is String) {
      return TextSpan(text: value, style: baseStyle);
    }
    return TextSpan(text: '', style: baseStyle);
  }

  /// Static helper method for formatting price (needed for buildLocalizedTextSpan)
  static String _formatPriceStatic(String price, bool isRTL) {
    if (!isRTL) return price;

    // Parse the price as integer
    final int? priceInt = int.tryParse(price);
    if (priceInt == null) return price;

    // Format with commas
    String formattedPrice = priceInt.toString();
    final int length = formattedPrice.length;
    for (int i = length - 3; i > 0; i -= 3) {
      formattedPrice =
          formattedPrice.substring(0, i) + ',' + formattedPrice.substring(i);
    }

    // Convert English numerals to Persian numerals
    final persianNumerals = {
      '0': '۰',
      '1': '۱',
      '2': '۲',
      '3': '۳',
      '4': '۴',
      '5': '۵',
      '6': '۶',
      '7': '۷',
      '8': '۸',
      '9': '۹'
    };

    for (var entry in persianNumerals.entries) {
      formattedPrice = formattedPrice.replaceAll(entry.key, entry.value);
    }

    return formattedPrice;
  }

  /// Retrieves a localized string based on its ID and optionally injects dynamic product/package data.
  String getString(
    String stringId, {
    OfferingPackages? offeringPackage,
    OfferingPackagesProduct? product,
    String? currentLocale,
  }) {
    final effectiveLocale = currentLocale ?? _currentLocale;
    final paywallString = _localizedStrings[effectiveLocale]?[stringId];
    final isRTL = _rtlLocales[effectiveLocale] ?? false;

    _debugLocalizationLog(
      'Getting string for ID: $stringId, Locale: $effectiveLocale, Found: ${paywallString != null}',
    );
    _debugLocalizationLog(
      'Available locales: ${_localizedStrings.keys.toList()}',
    );
    _debugLocalizationLog(
      'Available strings in $effectiveLocale: ${_localizedStrings[effectiveLocale]?.keys.toList()}',
    );

    if (paywallString == null || paywallString.value == null) {
      _debugLocalizationLog(
        'Localization string not found for ID: $stringId in locale: $effectiveLocale',
      );
      return stringId; // Fallback to ID if string or its value not found
    }

    _debugLocalizationLog(
      'String value type: ${paywallString.value.runtimeType}, Value: ${paywallString.value}',
    );

    // Handle the 'value' field which can be String or List<dynamic>
    if (paywallString.value is String) {
      return paywallString.value.toString();
    } else if (paywallString.value is List) {
      final List<dynamic> values = paywallString.value;
      final StringBuffer buffer = StringBuffer();

      _debugLocalizationLog('Processing list with ${values.length} items');

      for (var item in values) {
        _debugLocalizationLog(
          'Processing item: $item (type: ${item.runtimeType})',
        );

        if (item is String) {
          buffer.write(item);
        } else if (item is Map<String, dynamic>) {
          // Handle text objects with attributes
          if (item.containsKey('text')) {
            buffer.write(item['text'] ?? '');
            _debugLocalizationLog('Added text: ${item['text']}');
          } else {
            // Handle tag objects
            final String? tag = item['tag'];
            _debugLocalizationLog('Processing tag: $tag');
            switch (tag) {
              case "PROD_TITLE":
                final productName = product?.name ?? 'N/A';
                buffer.write(productName);
                _debugLocalizationLog('Added PROD_TITLE: $productName');
                break;
              case "PROD_PRICE":
                // Find the price object, prioritizing IRR, then USD, then the first available
                final priceObject = product?.prices?.firstWhereOrNull(
                      (p) => p.currency == 'IRR',
                    ) ??
                    product?.prices?.firstWhereOrNull(
                      (p) => p.currency == 'USD',
                    ) ??
                    product?.prices?.firstOrNull;
                final price = priceObject?.price?.toString() ?? 'N/A';
                final formattedPrice = _formatPrice(price, isRTL);
                buffer.write(formattedPrice);
                _debugLocalizationLog(
                  'Added PROD_PRICE: $formattedPrice (RTL: $isRTL)',
                );
                break;
              case "PROD_CURRENCY":
                // Find the price object, prioritizing IRR, then USD, then the first available
                final priceObject = product?.prices?.firstWhereOrNull(
                      (p) => p.currency == 'IRR',
                    ) ??
                    product?.prices?.firstWhereOrNull(
                      (p) => p.currency == 'USD',
                    ) ??
                    product?.prices?.firstOrNull;

                // Replace "IRR" with "تومان" for RTL
                final String currencyText = priceObject?.currency ?? 'N/A';
                final displayCurrency =
                    isRTL && currencyText == 'IRR' ? 'تومان' : currencyText;
                buffer.write(displayCurrency);
                _debugLocalizationLog(
                  'Added PROD_CURRENCY: $displayCurrency (RTL: $isRTL)',
                );
                break;
              case "PACK_DESCRIPTION":
                final description = offeringPackage?.description ?? 'N/A';
                buffer.write(description);
                _debugLocalizationLog('Added PACK_DESCRIPTION: $description');
                break;
              default:
                _debugLocalizationLog(
                  'Unknown localization tag: $tag for string ID: $stringId',
                );
                buffer.write('[$tag]'); // Show unknown tags for debugging
                break;
            }
          }
        } else if (item == null) {
          // Handle null values in the list
          buffer.write('');
          _debugLocalizationLog('Added null item');
        } else {
          _debugLocalizationLog(
            'Unexpected type in localization string value list: ${item.runtimeType} for string ID: $stringId',
          );
          buffer.write(item.toString()); // Fallback for unexpected types
        }
      }

      final result = buffer.toString();
      _debugLocalizationLog('Final string result: "$result"');
      return result;
    }
    _debugLocalizationLog(
      'Unexpected localization string value type: ${paywallString.value.runtimeType} for string ID: $stringId',
    );
    return paywallString.value
        .toString(); // Fallback for unexpected root value types
  }
}
