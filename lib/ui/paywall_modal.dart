import 'package:flutter/material.dart';
import 'package:collection/collection.dart';
import 'package:inappify_sdk/helpers/localization_helper.dart';
import 'package:inappify_sdk/helpers/paywall_widget_parser.dart';
import 'package:inappify_sdk/models/paywall.dart';
import 'package:inappify_sdk/models/paywall_element.dart';

class PaywallModal extends StatefulWidget {
  const PaywallModal({
    required this.paywall,
    this.fontFamily,
    super.key,
  });

  final Paywall paywall;
  final String? fontFamily;

  @override
  State<PaywallModal> createState() => _PaywallModalState();
}

class _PaywallModalState extends State<PaywallModal> {
  String? _selectedPackageId;

  // Getter for selected package ID
  String? get selectedPackageId => _selectedPackageId;
  @override
  Widget build(BuildContext context) {
    // Check for essential data before building UI
    if (widget.paywall.assets == null || widget.paywall.assets!.isEmpty) {
      return const Center(
          child: Text('Paywall assets are missing. Cannot build UI.'));
    }
    if (widget.paywall.localizations == null ||
        widget.paywall.localizations!.isEmpty) {
      return const Center(
          child: Text('Paywall localizations are missing. Cannot build UI.'));
    }

    // Initialize LocalizationHelper (it's an instance)
    final LocalizationHelper localizationManager = LocalizationHelper(
      widget.paywall.localizations!,
      widget.paywall.currentLocale ?? 'en', // Provide a default locale if null
    );

    // Create PaywallWidgetParser, passing the necessary data and helper instance
    final PaywallWidgetParser parser = PaywallWidgetParser(
      assets: widget.paywall.assets!, // Pass the list of assets to the parser
      localizationManager:
          localizationManager, // Pass the LocalizationHelper instance
      paywallData: widget.paywall,
      context: context,
      customFontFamily: widget.fontFamily, // Pass the custom font family
    );

    // Find the 'layout' element which is the root of the UI tree
    final PaywallElement? layoutElement = (widget.paywall.elements ?? [])
        .firstWhereOrNull((e) => e.type == 'layout');

    if (layoutElement == null) {
      return const Center(
          child: Text('Layout element not found in JSON. Cannot build UI.'));
    }

    // Render the UI using the parser, applying RTL/LTR based on current locale
    final String locale = (widget.paywall.currentLocale ?? 'en').toLowerCase();
    final bool isRtlByLocale = locale.startsWith('fa');
    final TextDirection textDirection =
        isRtlByLocale ? TextDirection.rtl : TextDirection.ltr;

    return Directionality(
      textDirection: textDirection,
      child: Container(
        width: MediaQuery.sizeOf(context).width,
        height: MediaQuery.sizeOf(context).height,
        color: Colors.white,
        child: parser.parse(layoutElement),
      ),
    );
  }
}
