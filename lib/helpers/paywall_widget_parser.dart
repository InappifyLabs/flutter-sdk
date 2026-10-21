import 'package:inappify_sdk/src/logging/sdk_logger.dart';
// lib/paywall_builder/paywall_widget_parser.dart
import 'package:flutter/material.dart';
import 'package:collection/collection.dart';
import 'package:inappify_sdk/helpers/paywall_assets_helper.dart';
import 'package:inappify_sdk/helpers/paywall_image_loader.dart';
import 'package:inappify_sdk/helpers/localization_helper.dart';
import 'package:inappify_sdk/helpers/responsive_font_helper.dart';
import 'package:inappify_sdk/models/paywall.dart';
import 'package:inappify_sdk/models/paywall_element.dart';
import 'package:inappify_sdk/models/paywall_element_states.dart';
import 'package:inappify_sdk/models/paywall_text_style.dart';
import 'package:inappify_sdk/models/paywall_item_tree_state.dart';
import 'package:inappify_sdk/models/offering_packages.dart';
import 'package:inappify_sdk/models/offering_packages_product.dart';
import 'package:inappify_sdk/models/paywall_asset.dart';
import 'package:inappify_sdk/ui/paywall_pacakges.dart';
import 'package:url_launcher/url_launcher.dart';

/// Emits structural diagnostics without localized text, URLs or dynamic values.
void _debugPaywallParserLog(String message) {
  SdkLogger.verbose('Paywall rendering event.');
}

class PaywallWidgetParser {
  final List<PaywallAsset> _assets;
  final LocalizationHelper _localizationHelper;
  final Paywall paywallData;
  final BuildContext context;
  final String? _customFontFamily;

  String? _selectedPackageId;

  PaywallWidgetParser({
    required List<PaywallAsset> assets,
    required LocalizationHelper localizationManager,
    required this.paywallData,
    required this.context,
    String? customFontFamily,
  }) : _assets = assets,
       _localizationHelper = localizationManager,
       _customFontFamily = customFontFamily;

  Widget parse(PaywallElement element) {
    if (element.type == null) {
      _debugPaywallParserLog(
        'Element type is null for element ID: ${element.id}',
      );
      return const SizedBox.shrink();
    }

    return Builder(
      builder: (context) {
        switch (element.type) {
          case 'layout':
            return _buildLayout(element, context);
          case 'hero-image':
            return _buildHeroImage(element, context);
          case 'text':
            return _buildText(element);
          case 'button':
            return _buildButton(element, context);
          case 'footer':
            return _buildFooter(element, context);
          case 'link':
            return _buildLink(element);
          case 'packages':
            _selectedPackageId = element.selectedPackageId;
            return PaywallPackages(
              element: element,
              assets: _assets,
              localizationHelper: _localizationHelper,
              paywallData: paywallData,
              customFontFamily: _customFontFamily,
              onPackageIdChanged: (packageId) {
                _selectedPackageId = packageId;
              },
            );
          case 'package-item':
            // Package items are handled within the packages widget
            return const SizedBox.shrink();
          case 'tab-control':
            return _buildTabControl(element, context);
          case 'group':
            return _buildGroup(element, context);
          case 'image':
            return _buildImage(element);
          case 'card':
            return _buildCard(element, context);
          case 'list':
            return _buildList(element, context);
          case 'list-item':
            final listElement = (paywallData.elements ?? []).firstWhereOrNull(
              (e) => e.type == 'list',
            );
            if (listElement != null) {
              return _buildListItem(element, listElement);
            }
            return const SizedBox.shrink();
          default:
            _debugPaywallParserLog(
              'WARNING: Unknown element type encountered: ${element.type} (ID: ${element.id})',
            );
            return const SizedBox.shrink();
        }
      },
    );
  }

  Widget _applyCommonStyles(Widget child, PaywallElement element) {
    Widget currentWidget = child;

    final decoration = PaywallAssetsHelper.getBoxDecoration(
      _assets,
      element.background,
      element.border,
      element.cornerRadius,
      element.borderThickness,
    );
    if (decoration != null) {
      _debugPaywallParserLog(
        'Applying decoration for element ${element.id}: $decoration',
      );
      currentWidget = Container(
        decoration: decoration,
        padding:
            (element.type != 'layout' &&
                element.padding != null &&
                element.padding!.length == 4)
            ? PaywallAssetsHelper.getPadding(element.padding)
            : EdgeInsets.zero,
        child: currentWidget,
      );
    } else {
      _debugPaywallParserLog(
        'No decoration found for element ${element.id}. Background: ${element.background}, Border: ${element.border}',
      );
      // If no decoration but padding provided, still apply the padding
      if (element.type != 'layout' &&
          element.padding != null &&
          element.padding!.length == 4) {
        currentWidget = Padding(
          padding: PaywallAssetsHelper.getPadding(element.padding),
          child: currentWidget,
        );
      }
    }

    if (element.margin != null &&
        element.margin!.length == 4 &&
        element.type != 'button') {
      return Padding(
        padding: PaywallAssetsHelper.getMargin(element.margin),
        child: currentWidget,
      );
    }

    return currentWidget;
  }

  Widget _buildHeroImage(PaywallElement element, BuildContext context) {
    return FutureBuilder<String?>(
      future: PaywallAssetsHelper.getPaywallAssetUrl(
        _assets,
        element.imageFile?.asset,
      ),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const SizedBox.shrink();
        }

        final imageUrl = snapshot.data;
        _debugPaywallParserLog(
          'Building hero-image. URL: $imageUrl, ImageHeight: ${element.imageHeight}',
        );

        if (imageUrl == null || imageUrl.isEmpty) {
          _debugPaywallParserLog(
            'Hero image URL is null or empty, returning SizedBox.shrink().',
          );
          return const SizedBox.shrink();
        }

        final int templateType = paywallData.templateType ?? 1;
        final double screenHeight = MediaQuery.sizeOf(context).height;

        double finalHeight;
        BoxFit fitType;

        switch (templateType) {
          case 1:
            // Template Type 1: Hero image takes top portion of screen

            final double calculatedHeight =
                (element.imageHeight?.toDouble() ?? 0.0) / 100.0 * screenHeight;
            finalHeight = calculatedHeight > 0
                ? calculatedHeight
                : screenHeight * 0.4;
            fitType = BoxFit.cover;
            break;
          case 2:
            // Template Type 2: Hero image fills entire screen with overlay
            finalHeight = screenHeight;
            fitType = BoxFit.cover;
            break;
          case 3:
            // Template Type 3: Similar to Template 1
            final double calculatedHeight =
                (element.imageHeight?.toDouble() ?? 0.0) / 100.0 * screenHeight;
            finalHeight = calculatedHeight > 0
                ? calculatedHeight
                : screenHeight * 0.4;
            fitType = BoxFit.cover;
            break;
          default:
            final double calculatedHeight =
                (element.imageHeight?.toDouble() ?? 0.0) / 100.0 * screenHeight;
            finalHeight = calculatedHeight > 0
                ? calculatedHeight
                : screenHeight * 0.4;
            fitType = BoxFit.cover;
            break;
        }

        return SizedBox(
          height: finalHeight,
          width: double.infinity,
          child: buildPaywallImage(
            source: imageUrl,
            height: finalHeight,
            width: double.infinity,
            fit: fitType,
            errorBuilder: (context, error, stackTrace) {
              _debugPaywallParserLog(
                'Paywall image loading failed: ${error.runtimeType}',
              );
              return Container(
                height: finalHeight,
                width: double.infinity,
                color: Colors.grey[300],
                child: const Icon(
                  Icons.broken_image,
                  color: Colors.grey,
                  size: 50,
                ),
              );
            },
          ),
        );
      },
    );
  }

  Widget _buildText(PaywallElement element) {
    _debugPaywallParserLog('Building text element: ${element.id}');
    _debugPaywallParserLog('String ID: ${element.stringId}');

    // Get the raw localization value for rich text processing
    final value = _localizationHelper.getLocalizationValue(
      element.stringId ?? '',
    );

    final textStyle = PaywallAssetsHelper.getTextStyle(
      _assets,
      element.fontId,
      element.color,
      isRTL: _localizationHelper.isRTL,
      context: context,
      customFontFamily: _customFontFamily,
    );

    // Force white color for text elements if no color found
    final finalTextStyle = textStyle?.color == null
        ? TextStyle(
            color: Colors.white,
            fontSize: textStyle?.fontSize,
            fontFamily: _customFontFamily,
          )
        : textStyle;

    TextAlign textAlign = TextAlign.start;
    if (element.hAlign != null) {
      switch (element.hAlign) {
        case 'center':
          textAlign = TextAlign.center;
          break;
        case 'right':
          textAlign = TextAlign.right;
          break;
        case 'left':
          textAlign = TextAlign.left;
          break;
      }
    }

    return _applyCommonStyles(
      SizedBox(
        width: double.infinity,
        child: RichText(
          text: LocalizationHelper.buildLocalizedTextSpan(
            value,
            finalTextStyle ?? const TextStyle(),
            isRTL: _localizationHelper.isRTL,
          ),
          textAlign: textAlign,
          maxLines: _getMaxLines(element.maxRows),
          overflow: element.onOverflow == 'truncate'
              ? TextOverflow.ellipsis
              : TextOverflow.visible,
        ),
      ),
      element,
    );
  }

  Widget _buildButton(PaywallElement element, BuildContext context) {
    _debugPaywallParserLog('Building button element: ${element.id}');

    String primaryTextId = '';

    // Handle PaywallText structure
    if (element.text != null) {
      primaryTextId = element.text?.defaultText?.primary ?? '';
      _debugPaywallParserLog(
        'Button text structure found, primary ID: $primaryTextId',
      );
    } else {
      _debugPaywallParserLog('No text structure found for button');
    }

    final buttonText = _localizationHelper.getString(primaryTextId);
    _debugPaywallParserLog('Resolved button text: "$buttonText"');

    final primaryTextStyle = PaywallAssetsHelper.getTextStyle(
      _assets,
      element.primaryFont,
      element.primaryColor,
      isRTL: _localizationHelper.isRTL,
      context: context,
      customFontFamily: _customFontFamily,
    );

    // Apply same fallback behavior as text elements (default white if color missing)
    final TextStyle? effectivePrimaryTextStyle =
        (primaryTextStyle?.color == null)
        ? TextStyle(
            color: Colors.white,
            fontSize: ResponsiveFontHelper.getResponsiveFontSize(
              context: context,
              baseSize: primaryTextStyle?.fontSize,
            ),
            fontFamily: _customFontFamily,
          )
        : primaryTextStyle;

    return Padding(
      padding: PaywallAssetsHelper.getPadding(element.margin),
      child: _applyCommonStyles(
        GestureDetector(
          onTap: () {
            _debugPaywallParserLog(
              'Button action: ${element.action?.type ?? 'N/A'}',
            );
            if (element.action?.type == 'purchase_product') {
              if (_selectedPackageId != null) {
                int id = int.parse(_selectedPackageId!);
                OfferingPackages? package = paywallData.offeringPackages
                    ?.firstWhereOrNull((e) => e.id == id);
                if (package != null) {}
              }
            } else if (element.action?.type == 'crypto') {
              // Trigger crypto payment flow
            } else if (element.action?.type == 'close') {
              Navigator.of(context).pop();
            }
          },
          child: Align(
            // Shrink-wrap width to content
            widthFactor: 1.0,
            child: Container(
              alignment: _getAlignment(element.contentLayout?.align),
              padding: PaywallAssetsHelper.getPadding(
                element.contentLayout?.padding,
              ),
              child: Text(buttonText, style: effectivePrimaryTextStyle),
            ),
          ),
        ),
        element,
      ),
    );
  }

  Widget _buildFooter(PaywallElement element, BuildContext context) {
    // First try to find footer directly in items_trees_state
    List<PaywallItemTreeState> footerChildrenItemTrees =
        (paywallData.itemsTreesState ?? [])
            .firstWhereOrNull((item) => item.id == element.id)
            ?.children
            ?.toList() ??
        [];

    // If not found directly, look for footer in items_trees_state
    if (footerChildrenItemTrees.isEmpty) {
      final footerTree = (paywallData.itemsTreesState ?? []).firstWhereOrNull(
        (item) => item.id == 'footer',
      );

      if (footerTree != null) {
        footerChildrenItemTrees = footerTree.children?.toList() ?? [];
      }
    }

    footerChildrenItemTrees.sort(
      (a, b) => (a.sortOrder ?? 0).compareTo(b.sortOrder ?? 0),
    );

    _debugPaywallParserLog(
      'Found ${footerChildrenItemTrees.length} footer children for element ${element.id}',
    );

    final List<Widget> childrenWidgets = [];
    for (var itemTree in footerChildrenItemTrees) {
      final childElement = (paywallData.elements ?? []).firstWhereOrNull(
        (e) => e.id == itemTree.id,
      );
      if (childElement != null) {
        if (childElement.type == 'hero-image') {
          childrenWidgets.add(_buildHeroImage(childElement, context));
        } else {
          childrenWidgets.add(parse(childElement));
        }
        _debugPaywallParserLog(
          'Parsing footer child: ${childElement.id} (${childElement.type})',
        );
      } else {
        _debugPaywallParserLog(
          'WARNING: Footer child from items_trees_state not found in paywall.elements: ID ${itemTree.id}',
        );
      }

      if (element.spacing != null) {
        childrenWidgets.add(
          SizedBox(height: double.tryParse(element.spacing ?? '0') ?? 0),
        );
      }
    }

    return _applyCommonStyles(Column(children: childrenWidgets), element);
  }

  Widget _buildLink(PaywallElement element) {
    final List<Widget> links = [];
    final linkStyle = PaywallAssetsHelper.getTextStyle(
      _assets,
      element.textStyle?.fontId,
      element.textStyle?.color ?? element.textStyle?.colorId,
      isRTL: _localizationHelper.isRTL,
      context: context,
    );
    final dividerColor = PaywallAssetsHelper.getPaywallAssetColor(
      _assets,
      element.divider?.color,
    );
    final double dividerThickness =
        double.tryParse(element.divider?.thickness ?? '0') ?? 0;

    void addLink(String? stringId, {String? urlId, bool? visible}) {
      if (visible == true && stringId != null && stringId.isNotEmpty) {
        links.add(
          GestureDetector(
            onTap: () {
              if (urlId != null && urlId.isNotEmpty) {
                launchUrl(Uri.parse(urlId));
              }
            },
            child: Text(
              _localizationHelper.getString(stringId),
              style: linkStyle,
            ),
          ),
        );
      }
    }

    if (element.links?.login?.visible == true) {
      addLink(element.links?.login?.stringId, visible: true);
    }
    if (element.links?.terms?.visible == true) {
      addLink(
        element.links?.terms?.stringId,
        urlId: element.links?.terms?.urlId,
        visible: true,
      );
    }
    if (element.links?.privacy?.visible == true) {
      addLink(
        element.links?.privacy?.stringId,
        urlId: element.links?.privacy?.urlId,
        visible: true,
      );
    }
    if (element.links?.restore?.visible == true) {
      addLink(element.links?.restore?.stringId, visible: true);
    }

    if (links.isEmpty) return const SizedBox.shrink();

    // Calculate spacing between links
    final double spacing =
        double.tryParse(element.contentLayout?.spacing ?? '8') ?? 8;

    return _applyCommonStyles(
      Row(
        mainAxisAlignment: _getMainAxisAlignment(
          element.contentLayout?.align ?? 'center',
        ),
        children: links
            .expand(
              (link) => [
                Flexible(child: link),
                if (links.last != link)
                  if (dividerThickness > 0 && dividerColor != null)
                    Padding(
                      padding: EdgeInsets.symmetric(horizontal: spacing / 2),
                      child: Container(
                        width: dividerThickness,
                        height: 16,
                        color: dividerColor,
                      ),
                    )
                  else
                    SizedBox(width: spacing),
              ],
            )
            .toList(),
      ),
      element,
    );
  }

  // Refactored _buildLayout to manage spacing between top-level elements and use Expanded
  Widget _buildLayout(PaywallElement element, BuildContext context) {
    final int templateType = paywallData.templateType ?? 1;
    _debugPaywallParserLog('Building layout for template type: $templateType');

    Widget? topButtonWidget;
    if (element.topButton != null &&
        (element.topButton!.style?.visible ?? false)) {
      topButtonWidget = GestureDetector(
        onTap: () {
          if (element.topButton?.action?.type == 'close') {
            Navigator.of(context).pop();
          } else {
            Navigator.of(
              context,
            ).pushNamed(element.topButton?.action?.type ?? '');
          }
        },
        child: Container(
          padding: element.topButton?.styleType == 'icon'
              ? const EdgeInsets.all(8.0)
              : const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: PaywallAssetsHelper.getBoxDecoration(
            _assets,
            element.topButton?.style?.background,
            element.topButton?.style?.border,
            element.topButton?.styleType == 'icon'
                ? [50, 50, 50, 50]
                : element.topButton!.style?.cornerRadius,
            (element.topButton!.style?.thickness ?? 0).toString(),
          ),
          child: element.topButton?.styleType == 'icon'
              ? Icon(
                  element.topButton?.style?.icon?.type == 'chevron_left'
                      ? Icons.chevron_left
                      : element.topButton?.style?.icon?.type == 'chevron_right'
                      ? Icons.chevron_right
                      : Icons.close,
                  color: PaywallAssetsHelper.getPaywallAssetColor(
                    _assets,
                    element.topButton!.style?.icon?.color,
                  ),
                )
              : Text(
                  _localizationHelper.getString(
                    element.topButton!.style?.stringId ?? '',
                  ),
                  style: PaywallAssetsHelper.getTextStyle(
                    _assets,
                    element.topButton!.style?.fontId,
                    element.topButton!.style?.icon?.color,
                    context: context,
                    customFontFamily: _customFontFamily,
                  ),
                ),
        ),
      );
      _debugPaywallParserLog('Top button widget built.');
    }

    Widget? heroImageWidget;
    final heroImageElement = (paywallData.elements ?? []).firstWhereOrNull(
      (e) => e.id == 'hero-image',
    );
    if (heroImageElement != null) {
      heroImageWidget = _buildHeroImage(heroImageElement, context);
      _debugPaywallParserLog('Hero image widget built.');
    }

    // Prepare the list of core content widgets (excluding header/footer which are added specially)
    final List<Widget> coreContentWidgets = [];
    final EdgeInsetsGeometry layoutContentPadding =
        (element.padding != null && element.padding!.length == 4)
        ? EdgeInsets.fromLTRB(
            element.padding![3].toDouble(), // Left
            element.padding![0]
                .toDouble(), // Top (only for content below image)
            element.padding![1].toDouble(), // Right
            element.padding![2].toDouble(), // Bottom
          )
        : EdgeInsets.zero;

    // Iterate through items_trees_state for other top-level children
    final List<PaywallItemTreeState> topLevelItemTrees =
        (paywallData.itemsTreesState ?? [])
            .where((item) => item.parentId == null)
            .toList()
          ..sort((a, b) => (a.sortOrder ?? 0).compareTo(b.sortOrder ?? 0));

    _debugPaywallParserLog(
      'Top-level items from items_trees_state: ${topLevelItemTrees.map((e) => e.id).toList()}',
    );

    // Debug: Print all elements in paywall data
    _debugPaywallParserLog(
      'All elements in paywall data: ${(paywallData.elements ?? []).map((e) => '${e.id} (${e.type})').toList()}',
    );

    for (var itemTree in topLevelItemTrees) {
      _debugPaywallParserLog(
        'Processing item tree: ${itemTree.id} (${itemTree.type})',
      );

      // Skip hero-image if it was already handled in the Stack
      if (itemTree.id == 'hero-image') {
        _debugPaywallParserLog(
          'Skipping hero-image from items_trees_state as it\'s handled in Stack.',
        );
        continue;
      }

      final childElement = (paywallData.elements ?? []).firstWhereOrNull(
        (e) => e.id == itemTree.id,
      );
      if (childElement != null) {
        _debugPaywallParserLog(
          'Processing element: ${childElement.id} (${childElement.type})',
        );
        Widget parsedChild;
        if (childElement.type == 'packages') {
          // If it's the packages element, call _buildPackages
          parsedChild = PaywallPackages(
            element: childElement,
            assets: _assets,
            localizationHelper: _localizationHelper,
            paywallData: paywallData,
            onPackageIdChanged: (packageId) {
              _debugPaywallParserLog('Package ID changed to: $packageId');
            },
          );

          // Insert a SizedBox *before* packages if there was previous content
        } else if (childElement.type == 'footer') {
          // Footer will be handled separately at the end of the main Column
          _debugPaywallParserLog(
            'Footer element found, will be added after main content.',
          );
          continue; // Skip adding footer here
        } else {
          parsedChild = parse(childElement);
        }

        // Add the parsed child directly without individual padding
        coreContentWidgets.add(parsedChild);
        _debugPaywallParserLog(
          'Parsed core content element: ${childElement.id} (${childElement.type})',
        );
      } else {
        _debugPaywallParserLog(
          'WARNING: Element from items_trees_state not found in paywall.elements: ID ${itemTree.id}',
        );
      }
    }

    _debugPaywallParserLog(
      'Total core content widgets: ${coreContentWidgets.length}',
    );

    // Build layout based on template type
    Widget layoutWidget;

    switch (templateType) {
      case 1:
        // Template Type 1: Hero image on top, content below with dark background
        layoutWidget = _buildTemplateType1(
          heroImageWidget,
          topButtonWidget,
          coreContentWidgets,
          element,
          context,
          paywallData.elements?.firstWhereOrNull((e) => e.id == 'hero-image') ??
              PaywallElement(),
          layoutContentPadding as EdgeInsets,
        );
        break;
      case 2:
        // Template Type 2: Hero image covers entire screen with overlay content
        layoutWidget = _buildTemplateType2(
          heroImageWidget,
          topButtonWidget,
          coreContentWidgets,
          element,
          context,
          layoutContentPadding as EdgeInsets,
        );
        break;
      case 3:
        // Template Type 3: Different layout (to be defined)
        layoutWidget = _buildTemplateType3(
          heroImageWidget,
          topButtonWidget,
          coreContentWidgets,
          element,
          context,
          layoutContentPadding as EdgeInsets,
        );
        break;
      default:
        // Default to Template Type 1
        layoutWidget = _buildTemplateType1(
          heroImageWidget,
          topButtonWidget,
          coreContentWidgets,
          element,
          context,
          paywallData.elements?.firstWhereOrNull((e) => e.id == 'hero-image') ??
              PaywallElement(),
          layoutContentPadding as EdgeInsets,
        );
        break;
    }

    return layoutWidget;
  }

  // Builds a Positioned overlay for the top button honoring the align property
  // align: 'left' | 'right' | 'center' (default: 'left')
  Widget _buildTopButtonOverlay(
    PaywallElement element,
    Widget topButtonWidget,
  ) {
    final String align = (element.topButton?.align ?? 'left').toLowerCase();

    switch (align) {
      case 'right':
        return Positioned(
          top: 12,
          right: 12,
          child: Material(color: Colors.transparent, child: topButtonWidget),
        );
      case 'center':
        return Positioned(
          top: 12,
          left: 0,
          right: 0,
          child: Material(
            color: Colors.transparent,
            child: Center(child: topButtonWidget),
          ),
        );
      case 'left':
      default:
        return Positioned(
          top: 12,
          left: 12,
          child: Material(color: Colors.transparent, child: topButtonWidget),
        );
    }
  }

  Widget _buildTemplateType1(
    Widget? heroImageWidget,
    Widget? topButtonWidget,
    List<Widget> coreContentWidgets,
    PaywallElement element,
    BuildContext context,
    PaywallElement heroImageElement,
    EdgeInsets layoutContentPadding,
  ) {
    // Find footer element
    final footerElement = (paywallData.elements ?? []).firstWhereOrNull(
      (e) => e.type == 'footer',
    );

    // Build footer widget if it exists
    Widget? footerWidget;
    if (footerElement != null) {
      footerWidget = _buildFooter(footerElement, context);
    }

    // Create scrollable content (everything except footer)
    final List<Widget> scrollableContent = [];

    // Add hero image to scrollable content

    if (heroImageWidget != null) {
      if (heroImageElement.maskType == 'convex') {
        scrollableContent.add(
          ClipPath(clipper: CurveClipper(), child: heroImageWidget),
        );
      } else if (heroImageElement.maskType == 'concave') {
        scrollableContent.add(
          ClipPath(clipper: ConcaveCurveClipper(), child: heroImageWidget),
        );
      } else if (heroImageElement.maskType == 'rect') {
        scrollableContent.add(heroImageWidget);
      } else if (heroImageElement.maskType == 'round_rect') {
        // Get background color from server
        final Color? backgroundColor = PaywallAssetsHelper.getPaywallAssetColor(
          _assets,
          element.background,
        );

        scrollableContent.add(
          Stack(
            children: [
              // Hero image as background
              heroImageWidget,
              // Overlay with custom clipper using server background color
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: ClipPath(
                  clipper: YellowOverlayClipper(),
                  child: Container(height: 60, color: backgroundColor),
                ),
              ),
            ],
          ),
        );
      }
    }

    // Add all core content to scrollable content
    scrollableContent.addAll(coreContentWidgets);

    // Create main container with scrollable content
    final Widget mainContent = Container(
      margin: PaywallAssetsHelper.getMargin(element.margin),
      decoration: PaywallAssetsHelper.getBoxDecoration(
        _assets,
        element.background,
        element.border,
        element.cornerRadius,
        element.borderThickness,
      ),
      child: ListView(
        padding: const EdgeInsets.only(bottom: 150),
        children: [
          // Hero image without padding
          if (heroImageWidget != null)
            ...scrollableContent.where(
              (widget) =>
                  widget == heroImageWidget ||
                  (widget is ClipPath && widget.child == heroImageWidget) ||
                  (widget is Stack &&
                      widget.children.any((child) => child == heroImageWidget)),
            ),
          // Core content with padding
          Padding(
            padding: layoutContentPadding,
            child: Column(
              children: scrollableContent
                  .where(
                    (widget) =>
                        widget != heroImageWidget &&
                        !(widget is ClipPath &&
                            widget.child == heroImageWidget) &&
                        !(widget is Stack &&
                            widget.children.any(
                              (child) => child == heroImageWidget,
                            )),
                  )
                  .toList(),
            ),
          ),
        ],
      ),
    );

    // If there's footer, wrap in Stack
    if (footerWidget != null) {
      return Stack(
        children: [
          // Main scrollable content
          mainContent,
          // Fixed footer at bottom
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              decoration: PaywallAssetsHelper.getBoxDecoration(
                _assets,
                element.background,
                element.border,
                element.cornerRadius,
                element.borderThickness,
              ),
              child: SafeArea(child: footerWidget),
            ),
          ),
          // Top button as overlay
          if (topButtonWidget != null)
            _buildTopButtonOverlay(element, topButtonWidget),
        ],
      );
    } else {
      // If no footer, just add top button overlay
      if (topButtonWidget != null) {
        return Stack(
          children: [
            mainContent,
            _buildTopButtonOverlay(element, topButtonWidget),
          ],
        );
      } else {
        return mainContent;
      }
    }
  }

  Widget _buildTemplateType2(
    Widget? heroImageWidget,
    Widget? topButtonWidget,
    List<Widget> coreContentWidgets,
    PaywallElement element,
    BuildContext context,
    EdgeInsets layoutContentPadding,
  ) {
    if (heroImageWidget == null) {
      _debugPaywallParserLog(
        'No hero image found for Template 2, falling back to Template 1 layout.',
      );
      return _buildTemplateType1(
        heroImageWidget,
        topButtonWidget,
        coreContentWidgets,
        element,
        context,
        paywallData.elements?.firstWhereOrNull((e) => e.id == 'hero-image') ??
            PaywallElement(),
        layoutContentPadding,
      );
    }

    // For template type 2, we need the hero image to cover the entire screen
    final double screenHeight = MediaQuery.sizeOf(context).height;
    final double screenWidth = MediaQuery.sizeOf(context).width;

    _debugPaywallParserLog(
      'Template Type 2: Rendering ${coreContentWidgets.length} content widgets',
    );

    // Separate package items from other content
    final List<Widget> packageItems = [];
    final List<Widget> otherContent = [];

    for (var widget in coreContentWidgets) {
      // Check if this widget contains package items (this is a simplified check)
      // In a real implementation, you might need to check the widget type more precisely
      if (widget.toString().contains('packages') ||
          widget.toString().contains('package-item')) {
        packageItems.add(widget);
      } else {
        otherContent.add(widget);
      }
    }

    return SizedBox(
      height: screenHeight,
      width: screenWidth,
      child: Stack(
        children: [
          // Hero image covering entire screen
          Positioned.fill(
            child: SizedBox(
              height: screenHeight,
              width: screenWidth,
              child: heroImageWidget,
            ),
          ),

          // Dark overlay gradient, resolved from assets via tintColor
          // If not resolvable, fallback to default black gradient
          Positioned.fill(
            child: Builder(
              builder: (context) {
                final PaywallElement? hero = paywallData.elements
                    ?.firstWhereOrNull((e) => e.id == 'hero-image');
                final gradient = hero != null
                    ? PaywallAssetsHelper.getPaywallAssetLinearGradient(
                        _assets,
                        hero.tintColor,
                      )
                    : null;
                return Container(decoration: BoxDecoration(gradient: gradient));
              },
            ),
          ),

          // Main scrollable content
          Positioned.fill(
            child: Column(
              children: [
                // Scrollable content with top padding for button
                Expanded(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Add top padding to account for the overlay button
                        SizedBox(height: topButtonWidget != null ? 60.0 : 0),
                        ...otherContent,
                        ...packageItems,
                        // Add bottom padding to account for fixed footer
                        const SizedBox(height: 120.0),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Fixed footer at bottom
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.transparent, Colors.black.withOpacity(0.8)],
                  stops: const [0.0, 1.0],
                ),
              ),
              child: _buildFooterFromElements(context),
            ),
          ),

          // Top button as overlay
          if (topButtonWidget != null)
            _buildTopButtonOverlay(element, topButtonWidget),
        ],
      ),
    );
  }

  Widget _buildFooterFromElements(BuildContext context) {
    final footerElement = (paywallData.elements ?? []).firstWhereOrNull(
      (e) => e.type == 'footer',
    );
    if (footerElement != null) {
      return _buildFooter(footerElement, context);
    }
    return const SizedBox.shrink();
  }

  Widget _buildTemplateType3(
    Widget? heroImageWidget,
    Widget? topButtonWidget,
    List<Widget> coreContentWidgets,
    PaywallElement element,
    BuildContext context,
    EdgeInsets layoutContentPadding,
  ) {
    final List<Widget> childrenWidgets = [];

    // Template Type 3: Hero image with different overlay style
    if (heroImageWidget != null) {
      childrenWidgets.add(
        Expanded(
          child: Stack(
            children: [
              // Hero image as background
              heroImageWidget,

              // Overlay style for Template 3, resolved from assets via tintColor
              // Builder(builder: (context) {
              //   final PaywallElement? hero = paywallData.elements
              //       ?.firstWhereOrNull((e) => e.id == 'hero-image');
              //   final gradient = hero != null
              //       ? PaywallAssetsHelper.getPaywallAssetLinearGradient(
              //           _assets, hero.tintColor)
              //       : null;
              //   return Container(
              //     decoration: BoxDecoration(
              //       gradient: gradient ??
              //           const LinearGradient(
              //             begin: Alignment.topCenter,
              //             end: Alignment.bottomCenter,
              //             colors: [
              //               Color.fromRGBO(0, 0, 0, 0.2),
              //               Colors.transparent,
              //               Color.fromRGBO(0, 0, 0, 0.6),
              //               Color.fromRGBO(0, 0, 0, 0.8),
              //             ],
              //             stops: [0.0, 0.3, 0.6, 1.0],
              //           ),
              //     ),
              //   );
              // }),

              // Top button
              if (topButtonWidget != null)
                _buildTopButtonOverlay(element, topButtonWidget),

              // Content overlaid on image with different positioning
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: Container(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: coreContentWidgets,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
      _debugPaywallParserLog(
        'Added Stack with hero-image overlay and content (Template 3).',
      );
    } else {
      // If no hero image, fall back to template type 1 layout
      _debugPaywallParserLog(
        'No hero image found for Template 3, falling back to Template 1 layout.',
      );
      return _buildTemplateType1(
        heroImageWidget,
        topButtonWidget,
        coreContentWidgets,
        element,
        context,
        paywallData.elements?.firstWhereOrNull((e) => e.id == 'hero-image') ??
            PaywallElement(),
        layoutContentPadding,
      );
    }

    // Add footer outside the stack
    final footerElement = (paywallData.elements ?? []).firstWhereOrNull(
      (e) => e.type == 'footer',
    );
    if (footerElement != null) {
      childrenWidgets.add(_buildFooter(footerElement, context));
    }

    return Container(
      margin: PaywallAssetsHelper.getMargin(element.margin),
      decoration: PaywallAssetsHelper.getBoxDecoration(
        _assets,
        element.background,
        element.border,
        element.cornerRadius,
        element.borderThickness,
      ),
      child: Column(children: childrenWidgets),
    );
  }

  // Refactored _buildPackages to remove Expanded and SingleChildScrollView from its internal Column
  // as they are now handled by _buildLayout
  // Retained for the package layout renderer; not yet selected by the parser.
  // ignore: unused_element
  Widget _buildPackages(
    PaywallElement element, {
    Function(String)? onPackageSelected,
  }) {
    // First try to find packages directly in items_trees_state
    List<PaywallItemTreeState> packageItemIds =
        (paywallData.itemsTreesState ?? [])
            .firstWhereOrNull((item) => item.id == element.id)
            ?.children
            ?.toList() ??
        [];

    // If not found directly, look for packages inside footer
    if (packageItemIds.isEmpty) {
      final footerTree = (paywallData.itemsTreesState ?? []).firstWhereOrNull(
        (item) => item.id == 'footer',
      );

      if (footerTree != null) {
        final packagesTree = footerTree.children?.firstWhereOrNull(
          (item) => item.id == element.id,
        );

        if (packagesTree != null) {
          packageItemIds = packagesTree.children?.toList() ?? [];
        }
      }
    }

    _debugPaywallParserLog(
      'Found ${packageItemIds.length} package items for element ${element.id}',
    );

    if (packageItemIds.isEmpty) {
      _debugPaywallParserLog(
        'No package items found for element ${element.id}',
      );
      return const SizedBox.shrink();
    }

    final List<Widget> packageItemsWidgets = [];
    final String? selectedPackageId = element.selectedPackageId;

    final bool isHorizontal = element.contentLayout?.type == 'horizontal';

    for (var itemTree in packageItemIds) {
      final PaywallElement? packageItemElement = (paywallData.elements ?? [])
          .firstWhereOrNull((e) => e.id == itemTree.id);
      if (packageItemElement != null &&
          packageItemElement.type == 'package-item') {
        // Check if this package item is selected by comparing numeric IDs
        bool isSelected = false;
        if (selectedPackageId != null && packageItemElement.id != null) {
          // Extract numeric ID from package item ID (e.g., "7-package-item-..." -> "7")
          String? packageNumericId;
          if (packageItemElement.id!.contains('-')) {
            packageNumericId = packageItemElement.id!.split('-')[0];
          } else {
            packageNumericId = packageItemElement.id;
          }

          // Compare numeric IDs
          isSelected = packageNumericId == selectedPackageId;
          _debugPaywallParserLog(
            'Package item: ${packageItemElement.id}, Numeric ID: $packageNumericId, Selected ID: $selectedPackageId, Is Selected: $isSelected',
          );
        }

        // Extract numeric ID from package item ID (e.g., "6-package-item-..." -> "6")
        String? numericId;
        if (packageItemElement.id != null &&
            packageItemElement.id!.contains('-')) {
          numericId = packageItemElement.id!.split('-')[0];
        }

        final OfferingPackages? offeringPackage =
            (paywallData.offeringPackages ?? []).firstWhereOrNull(
              (op) => op.id.toString() == numericId,
            );
        final OfferingPackagesProduct? product =
            offeringPackage?.products?.firstOrNull;

        _debugPaywallParserLog(
          'Package item ID: ${packageItemElement.id}, Numeric ID: $numericId, Offering package found: ${offeringPackage != null}',
        );

        packageItemsWidgets.add(
          _buildPackageItem(
            packageItemElement,
            element,
            isSelected,
            offeringPackage: offeringPackage,
            product: product,
            isHorizontal: true,
            onPackageSelected: onPackageSelected,
          ),
        );
      }
    }

    final double spacing =
        double.tryParse(element.contentLayout?.spacing ?? '0') ?? 0;

    // Check if contentLayout type is horizontal for horizontal scrolling

    if (isHorizontal) {
      // Horizontal layout with SingleChildScrollView
      return _applyCommonStyles(
        SizedBox(
          width: double.infinity,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: PaywallAssetsHelper.getPadding(
              element.contentLayout?.padding,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.start,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: packageItemsWidgets
                  .map(
                    (widget) => Padding(
                      padding: EdgeInsets.only(right: spacing),
                      child: widget,
                    ),
                  )
                  .toList(),
            ),
          ),
        ),
        element,
      );
    } else {
      // Vertical layout (default)
      return _applyCommonStyles(
        SizedBox(
          width: double.infinity,
          child: Column(
            mainAxisAlignment: _getMainAxisAlignment(
              element.contentLayout?.align,
            ),
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: packageItemsWidgets
                .map(
                  (widget) => Padding(
                    padding: EdgeInsets.only(bottom: spacing),
                    child: widget,
                  ),
                )
                .toList(),
          ),
        ),
        element,
      );
    }
  }

  String _getTextFromElement(
    PaywallElement element,
    String textKey, {
    OfferingPackages? offeringPackage,
    OfferingPackagesProduct? product,
  }) {
    String textId = '';

    if (element.text != null) {
      switch (textKey) {
        case 'text1':
          textId = element.text?.defaultText?.text1 ?? '';
          break;
        case 'text2':
          textId = element.text?.defaultText?.text2 ?? '';
          break;
        case 'text3':
          textId = element.text?.defaultText?.text3 ?? '';
          break;
        case 'text4':
          textId = element.text?.defaultText?.text4 ?? '';
          break;
      }
    }

    return _localizationHelper.getString(
      textId,
      offeringPackage: offeringPackage,
      product: product,
    );
  }

  Widget _buildPackageItem(
    PaywallElement packageItemElement,
    PaywallElement parentPackagesElement,
    bool isSelected, {
    OfferingPackages? offeringPackage,
    OfferingPackagesProduct? product,
    bool isHorizontal = false,
    Function(String)? onPackageSelected,
  }) {
    final PaywallElementStates? elementStates = parentPackagesElement.states;
    final containerStyle = isSelected
        ? elementStates?.selected?.containerStyle
        : elementStates?.defaultState?.containerStyle;

    _debugPaywallParserLog(
      'Container style - Is Selected: $isSelected, Using: ${isSelected ? "selected" : "default"}',
    );

    final containerDecoration = PaywallAssetsHelper.getBoxDecoration(
      _assets,
      containerStyle?.background,
      containerStyle?.border,
      containerStyle?.cornerRadius,
      containerStyle?.borderThickness,
    );

    final text1 = _getTextFromElement(
      packageItemElement,
      'text1',
      offeringPackage: offeringPackage,
      product: product,
    );
    final text2 = _getTextFromElement(
      packageItemElement,
      'text2',
      offeringPackage: offeringPackage,
      product: product,
    );
    final text3 = _getTextFromElement(
      packageItemElement,
      'text3',
      offeringPackage: offeringPackage,
      product: product,
    );
    final text4 = _getTextFromElement(
      packageItemElement,
      'text4',
      offeringPackage: offeringPackage,
      product: product,
    );

    // Get text style from parent packages element states
    final textStyleState = isSelected
        ? elementStates?.selected?.textStyle
        : elementStates?.defaultState?.textStyle;

    _debugPaywallParserLog(
      'Package item ${packageItemElement.id} - Is Selected: $isSelected',
    );
    _debugPaywallParserLog(
      'Using text style state: ${isSelected ? "selected" : "default"}',
    );

    final textStyle1 = PaywallAssetsHelper.getTextStyle(
      _assets,
      textStyleState?.text1?.fontId,
      textStyleState?.text1?.color ?? textStyleState?.text1?.colorId,
      isRTL: _localizationHelper.isRTL,
      context: context,
      customFontFamily: _customFontFamily,
    );
    final textStyle2 = PaywallAssetsHelper.getTextStyle(
      _assets,
      textStyleState?.text2?.fontId,
      textStyleState?.text2?.color ?? textStyleState?.text2?.colorId,
      isRTL: _localizationHelper.isRTL,
      context: context,
      customFontFamily: _customFontFamily,
    );
    final textStyle3 = PaywallAssetsHelper.getTextStyle(
      _assets,
      textStyleState?.text3?.fontId,
      textStyleState?.text3?.color ?? textStyleState?.text3?.colorId,
      isRTL: _localizationHelper.isRTL,
      context: context,
      customFontFamily: _customFontFamily,
    );
    final textStyle4 = PaywallAssetsHelper.getTextStyle(
      _assets,
      textStyleState?.text4?.fontId,
      textStyleState?.text4?.color ?? textStyleState?.text4?.colorId,
      isRTL: _localizationHelper.isRTL,
      context: context,
      customFontFamily: _customFontFamily,
    );

    // Use the actual text styles from the parent packages element
    final finalTextStyle1 = textStyle1;
    final finalTextStyle2 = textStyle2;
    final finalTextStyle3 = textStyle3;
    final finalTextStyle4 = textStyle4;

    final itemInnerPadding =
        packageItemElement.contentLayout?.padding != null &&
            packageItemElement.contentLayout!.padding!.length == 4
        ? PaywallAssetsHelper.getPadding(
            packageItemElement.contentLayout!.padding,
          )
        : const EdgeInsets.all(0); // Default inner padding if not specified

    final double itemContentSpacing =
        double.tryParse(packageItemElement.contentLayout?.spacing ?? '0') ?? 0;

    return GestureDetector(
      onTap: () {
        _debugPaywallParserLog(
          'Package item ${packageItemElement.id} selected!',
        );
        // Extract numeric ID from package item ID (e.g., "7-package-item-..." -> "7")
        String? numericId;
        if (packageItemElement.id != null &&
            packageItemElement.id!.contains('-')) {
          numericId = packageItemElement.id!.split('-')[0];
        } else {
          numericId = packageItemElement.id;
        }

        if (numericId != null && onPackageSelected != null) {
          _debugPaywallParserLog('Calling onPackageSelected with: $numericId');
          onPackageSelected(numericId);
        }
      },
      child: Container(
        width: 120,
        height: isHorizontal ? 130 : null,

        decoration: containerDecoration,
        padding:
            itemInnerPadding, // This is the inner padding, unchanged by this request
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisAlignment: MainAxisAlignment.center,
          children:
              [
                    if (packageItemElement.badgeStyle?.visible == true &&
                        (packageItemElement.badge?.isNotEmpty ?? false))
                      Container(
                        decoration: PaywallAssetsHelper.getBoxDecoration(
                          _assets,
                          packageItemElement.badgeStyle?.background,
                          null,
                          packageItemElement.badgeStyle?.cornerRadius,
                          '0',
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        child: Text(
                          packageItemElement.badge!,
                          style: TextStyle(
                            color: PaywallAssetsHelper.getPaywallAssetColor(
                              _assets,
                              packageItemElement.badgeStyle?.color,
                            ),
                            fontFamily: _customFontFamily,
                          ),
                        ),
                      ),
                    if (packageItemElement.badgeStyle?.visible == true &&
                        (packageItemElement.badge?.isNotEmpty ?? false))
                      SizedBox(height: itemContentSpacing),
                    // Use Column for vertical layout within each package item
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Title (text1 or packageItemElement.title)
                        if (text1.isNotEmpty)
                          Text(
                            text1,
                            style: finalTextStyle1,
                            textAlign: TextAlign.center,
                          )
                        else if (packageItemElement.title != null &&
                            packageItemElement.title!.isNotEmpty)
                          Text(
                            packageItemElement.title!,
                            style:
                                finalTextStyle1 ??
                                TextStyle(fontFamily: _customFontFamily),
                            textAlign: TextAlign.center,
                          ),

                        SizedBox(height: itemContentSpacing),

                        // Price (text2)
                        if (text2.isNotEmpty)
                          Text(
                            text2,
                            style: finalTextStyle2,
                            textAlign: TextAlign.center,
                          ),

                        SizedBox(height: itemContentSpacing),

                        // Description (text3)
                        if (text3.isNotEmpty)
                          Text(
                            text3,
                            style: finalTextStyle3,
                            textAlign: TextAlign.center,
                          ),

                        // Additional info (text4)
                        if (text4.isNotEmpty)
                          Text(
                            text4,
                            style: finalTextStyle4,
                            textAlign: TextAlign.center,
                          ),
                      ],
                    ),
                  ]
                  .where(
                    (widget) =>
                        !(widget is SizedBox &&
                            (widget.height == 0 || widget.width == 0)),
                  )
                  .toList(),
        ),
      ),
    );
  }

  Widget _buildImage(PaywallElement element) {
    return FutureBuilder<String?>(
      future: PaywallAssetsHelper.getPaywallAssetUrl(
        _assets,
        element.imageFile?.asset,
      ),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const SizedBox.shrink();
        }

        final imageUrl = snapshot.data;
        _debugPaywallParserLog('Building image. URL: $imageUrl');

        if (imageUrl == null || imageUrl.isEmpty) {
          _debugPaywallParserLog(
            'Image URL is null or empty, returning SizedBox.shrink().',
          );
          return const SizedBox.shrink();
        }

        return _applyCommonStyles(
          buildPaywallImage(
            source: imageUrl,
            fit: BoxFit.contain,
            errorBuilder: (context, error, stackTrace) {
              _debugPaywallParserLog(
                'Paywall image loading failed: ${error.runtimeType}',
              );
              return Container(
                height: 50,
                width: double.infinity,
                color: Colors.grey[300],
                child: const Icon(
                  Icons.broken_image,
                  color: Colors.grey,
                  size: 50,
                ),
              );
            },
          ),
          element,
        );
      },
    );
  }

  Widget _buildCard(PaywallElement element, BuildContext context) {
    final List<PaywallItemTreeState> cardChildrenItemTrees =
        (paywallData.itemsTreesState ?? [])
            .firstWhereOrNull((item) => item.id == element.id)
            ?.children
            ?.toList() ??
        [];

    cardChildrenItemTrees.sort(
      (a, b) => (a.sortOrder ?? 0).compareTo(b.sortOrder ?? 0),
    );

    final List<Widget> childrenWidgets = [];
    for (var itemTree in cardChildrenItemTrees) {
      final childElement = (paywallData.elements ?? []).firstWhereOrNull(
        (e) => e.id == itemTree.id,
      );
      if (childElement != null) {
        childrenWidgets.add(parse(childElement));
        _debugPaywallParserLog(
          'Parsed card child: ${childElement.id} (${childElement.type})',
        );
      } else {
        _debugPaywallParserLog(
          'WARNING: Card child from items_trees_state not found in paywall.elements: ID ${itemTree.id}',
        );
      }
    }

    // Handle card background logic
    Widget cardContent = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: childrenWidgets,
    );

    // Priority: imageFile -> background -> color
    if (element.imageFile != null) {
      return FutureBuilder<String?>(
        future: PaywallAssetsHelper.getPaywallAssetUrl(
          _assets,
          element.imageFile?.asset,
        ),
        builder: (context, snapshot) {
          final imageUrl = snapshot.data;

          if (imageUrl != null && imageUrl.isNotEmpty) {
            _debugPaywallParserLog(
              'Card using imageFile as background: $imageUrl',
            );
            Widget finalCardContent = Container(
              width: double.infinity,
              decoration: BoxDecoration(
                image: DecorationImage(
                  image: createPaywallImageProvider(imageUrl),
                ),
              ),
              child: Center(child: cardContent),
            );

            return _applyCommonStyles(
              finalCardContent,
              element.copyWith(
                background:
                    '#${Colors.transparent.value.toRadixString(16).padLeft(8, '0')}',
              ),
            );
          } else {
            _debugPaywallParserLog(
              'Card imageFile is null or empty, trying background',
            );
            // Fallback to background if imageFile is null or empty
            if (element.background != null) {
              final Color? backgroundColor =
                  PaywallAssetsHelper.getPaywallAssetColor(
                    _assets,
                    element.background,
                  );

              if (backgroundColor != null) {
                _debugPaywallParserLog(
                  'Card using background: ${element.background}',
                );
                cardContent = Center(child: cardContent);
              }
            } else if (element.color != null) {
              // Fallback to color if background is also null
              final Color? backgroundColor =
                  PaywallAssetsHelper.getPaywallAssetColor(
                    _assets,
                    element.color,
                  );

              if (backgroundColor != null) {
                _debugPaywallParserLog(
                  'Card using color as background: ${element.color}',
                );
                cardContent = Container(
                  color: backgroundColor,
                  child: cardContent,
                );
              }
            }
            return _applyCommonStyles(cardContent, element);
          }
        },
      );
    } else if (element.background != null) {
      // If no imageFile, try background
      final Color? backgroundColor = PaywallAssetsHelper.getPaywallAssetColor(
        _assets,
        element.background,
      );

      if (backgroundColor != null) {
        _debugPaywallParserLog('Card using background: ${element.background}');
        cardContent = Container(
          width: double.infinity,
          color: backgroundColor,
          child: cardContent,
        );
      } else if (element.color != null) {
        // Fallback to color if background is null
        final Color? backgroundColor = PaywallAssetsHelper.getPaywallAssetColor(
          _assets,
          element.color,
        );

        if (backgroundColor != null) {
          _debugPaywallParserLog(
            'Card using color as background: ${element.color}',
          );
          cardContent = Container(
            width: double.infinity,
            color: backgroundColor,
            child: cardContent,
          );
        }
      }
    } else if (element.color != null) {
      // If no imageFile and no background, use color
      final Color? backgroundColor = PaywallAssetsHelper.getPaywallAssetColor(
        _assets,
        element.color,
      );

      if (backgroundColor != null) {
        _debugPaywallParserLog(
          'Card using color as background: ${element.color}',
        );
        cardContent = Container(
          width: double.infinity,
          color: backgroundColor,
          child: cardContent,
        );
      }
    }

    return _applyCommonStyles(cardContent, element);
  }

  Widget _buildList(PaywallElement element, BuildContext context) {
    final List<PaywallItemTreeState> listChildrenItemTrees =
        (paywallData.itemsTreesState ?? [])
            .firstWhereOrNull((item) => item.id == element.id)
            ?.children
            ?.toList() ??
        [];

    listChildrenItemTrees.sort(
      (a, b) => (a.sortOrder ?? 0).compareTo(b.sortOrder ?? 0),
    );

    final List<Widget> childrenWidgets = [];
    for (int i = 0; i < listChildrenItemTrees.length; i++) {
      final itemTree = listChildrenItemTrees[i];
      final childElement = (paywallData.elements ?? []).firstWhereOrNull(
        (e) => e.id == itemTree.id,
      );
      if (childElement != null) {
        if (childElement.type == 'list-item') {
          childrenWidgets.add(
            _buildListItem(
              childElement,
              element,
              isFirst: i == 0,
              isLast: i == listChildrenItemTrees.length - 1,
            ),
          );
        } else {
          childrenWidgets.add(parse(childElement));
        }
        _debugPaywallParserLog(
          'Parsed list child: ${childElement.id} (${childElement.type})',
        );
      } else {
        _debugPaywallParserLog(
          'WARNING: List child from items_trees_state not found in paywall.elements: ID ${itemTree.id}',
        );
      }
    }

    return _applyCommonStyles(
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: childrenWidgets,
      ),
      element,
    );
  }

  Widget _buildListItem(
    PaywallElement element,
    PaywallElement listElement, {
    bool isFirst = false,
    bool isLast = false,
  }) {
    // Handle text object structure from JSON
    String titleText = '';
    String captionText = '';

    // For list items, the text structure might be different
    // Try to get the title string ID from the element's text field
    if (element.text != null) {
      // For list items, the text structure is different - it has title and caption
      // We need to handle this specially since it's not a PaywallText structure
      // The JSON shows: "text": { "title": "string-id", "caption": "string-id" }
      // This is a simple Map structure, not PaywallText
      if (element.text != null) {
        final titleStringId = element.text?.title;
        final captionStringId = element.text?.caption;
        if (titleStringId != null) {
          titleText = _localizationHelper.getString(titleStringId);
        }
        if (captionStringId != null &&
            _localizationHelper.hasStringId(captionStringId)) {
          captionText = _localizationHelper.getString(captionStringId);
        }
      }
    }

    // If text is still empty, try to construct the string ID from the element ID
    if (titleText.isEmpty) {
      // For list items, the string ID is usually constructed as: element-id-title-string-id
      final titleStringId = '${element.id}-title-string-id';
      titleText = _localizationHelper.getString(titleStringId);
    }

    // Fallback to stringId if text object is not available
    if (titleText.isEmpty && element.stringId != null) {
      titleText = _localizationHelper.getString(element.stringId!);
    }

    // Get text style from textStyle object instead of fontId and color
    TextStyle? titleStyleTs;
    TextStyle? captionStyleTs;
    if (element.textStyle != null) {
      final titleStyle = element.textStyle?.title;
      if (titleStyle != null) {
        final bool hasItemTitleFont =
            PaywallAssetsHelper.getPaywallAssetFontSize(
              _assets,
              titleStyle.fontId,
            ) !=
            null;
        final bool hasItemTitleColor =
            PaywallAssetsHelper.getPaywallAssetColor(
              _assets,
              titleStyle.color ?? titleStyle.colorId,
            ) !=
            null;
        if (hasItemTitleFont && hasItemTitleColor) {
          titleStyleTs = PaywallAssetsHelper.getTextStyle(
            _assets,
            titleStyle.fontId,
            titleStyle.color ?? titleStyle.colorId,
            context: context,
            customFontFamily: _customFontFamily,
          );
        }
      }
      final captionStyle = element.textStyle?.caption;
      if (captionStyle != null) {
        final bool hasItemCaptionFont =
            PaywallAssetsHelper.getPaywallAssetFontSize(
              _assets,
              captionStyle.fontId,
            ) !=
            null;
        final bool hasItemCaptionColor =
            PaywallAssetsHelper.getPaywallAssetColor(
              _assets,
              captionStyle.color ?? captionStyle.colorId,
            ) !=
            null;
        if (hasItemCaptionFont && hasItemCaptionColor) {
          captionStyleTs = PaywallAssetsHelper.getTextStyle(
            _assets,
            captionStyle.fontId,
            captionStyle.color ?? captionStyle.colorId,
            context: context,
            customFontFamily: _customFontFamily,
          );
        }
      }
    }

    if (titleStyleTs == null) {
      final titleStyle = listElement.textStyle?.title;
      if (titleStyle != null) {
        titleStyleTs = PaywallAssetsHelper.getTextStyle(
          _assets,
          titleStyle.fontId,
          titleStyle.color ?? titleStyle.colorId,
          context: context,
          customFontFamily: _customFontFamily,
        );
      }
    }
    if (captionStyleTs == null) {
      final captionStyle = listElement.textStyle?.caption;
      if (captionStyle != null) {
        final bool hasListCaptionFont =
            PaywallAssetsHelper.getPaywallAssetFontSize(
              _assets,
              captionStyle.fontId,
            ) !=
            null;
        final bool hasListCaptionColor =
            PaywallAssetsHelper.getPaywallAssetColor(
              _assets,
              captionStyle.color ?? captionStyle.colorId,
            ) !=
            null;
        if (hasListCaptionFont && hasListCaptionColor) {
          captionStyleTs = PaywallAssetsHelper.getTextStyle(
            _assets,
            captionStyle.fontId,
            captionStyle.color ?? captionStyle.colorId,
            context: context,
            customFontFamily: _customFontFamily,
          );
        }
      }
    }

    // Fallback to element's fontId and color if textStyle is not available
    titleStyleTs ??= PaywallAssetsHelper.getTextStyle(
      _assets,
      element.fontId,
      element.color,
      context: context,
      customFontFamily: _customFontFamily,
    );
    captionStyleTs ??= titleStyleTs;

    // Force white color for list items if no color found
    final finalTitleStyle = titleStyleTs?.color == null
        ? TextStyle(
            color: Colors.white,
            fontSize: titleStyleTs?.fontSize,
            fontFamily: _customFontFamily,
          )
        : titleStyleTs;
    final finalCaptionStyle = captionStyleTs?.color == null
        ? TextStyle(
            color: Colors.white,
            fontSize: captionStyleTs?.fontSize,
            fontFamily: _customFontFamily,
          )
        : captionStyleTs;

    // Get icon URL from iconFile if available
    return FutureBuilder<String?>(
      future: element.iconFile != null
          ? PaywallAssetsHelper.getPaywallAssetUrl(
              _assets,
              element.iconFile!.asset,
            )
          : Future.value(null),
      builder: (context, snapshot) {
        final iconUrl = snapshot.data;
        _debugPaywallParserLog('List item icon URL: $iconUrl');

        // Build the main row content: title + caption stacked
        Widget rowContent = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              titleText.isEmpty ? 'No title for ${element.id}' : titleText,
              style: finalTitleStyle,
            ),
            if (captionText.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(captionText, style: finalCaptionStyle),
              ),
          ],
        );

        // Determine effective connector (item-level overrides, fallback to list-level)
        final itemConnector = element.connector;
        final listConnector = listElement.connector;
        final bool hasAnyConnector =
            itemConnector != null || listConnector != null;

        if (hasAnyConnector) {
          // Resolve thickness with fallback
          double thickness = 2.0;
          final String? itemThicknessStr = itemConnector?.thickness;
          final String? listThicknessStr = listConnector?.thickness;
          thickness =
              double.tryParse(itemThicknessStr ?? '') ??
              double.tryParse(listThicknessStr ?? '') ??
              2.0;

          // Resolve color with fallback (and asset lookup)
          Color? lineColor = PaywallAssetsHelper.getPaywallAssetColor(
            _assets,
            itemConnector?.colorId,
          );
          lineColor ??= PaywallAssetsHelper.getPaywallAssetColor(
            _assets,
            listConnector?.colorId,
          );

          // Determine side based on RTL
          final bool isRTL = _localizationHelper.isRTL;
          final EdgeInsets contentPadding = isRTL
              ? const EdgeInsets.only(right: 24)
              : const EdgeInsets.only(left: 24);

          // Build side column (node + optional line) and place it left/right using a Row
          final double nodeHeight =
              double.tryParse(listElement.iconHeight ?? '') ?? 24;
          final Widget node = SizedBox(
            child: SizedBox(
              width: nodeHeight,
              height: nodeHeight,
              child: Center(
                child: (iconUrl != null && iconUrl.isNotEmpty)
                    ? ClipOval(
                        child: buildPaywallImage(
                          source: iconUrl,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) =>
                              const Icon(
                                Icons.circle,
                                size: 12,
                                color: Colors.blue,
                              ),
                        ),
                      )
                    : const Icon(Icons.circle, size: 12, color: Colors.blue),
              ),
            ),
          );

          final Widget? verticalLine = thickness > 0
              ? SizedBox(
                  width: thickness,
                  height: 80,
                  child: ColoredBox(color: lineColor ?? Colors.blue),
                )
              : null;

          final Widget sideColumn = Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [node, if (verticalLine != null) verticalLine],
          );

          final double gap = 12;
          rowContent = IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (!isRTL) sideColumn,
                if (!isRTL) SizedBox(width: gap),
                if (isRTL) SizedBox(width: gap),
                if (isRTL) sideColumn,
                Expanded(
                  child: Padding(padding: contentPadding, child: rowContent),
                ),
              ],
            ),
          );
        }

        return _applyCommonStyles(rowContent, element);
      },
    );
  }

  int? _getMaxLines(String? maxRows) {
    if (maxRows == null || maxRows.isEmpty) return null;
    final maxLines = int.tryParse(maxRows);
    return maxLines != null && maxLines > 0 ? maxLines : null;
  }

  AlignmentGeometry _getAlignment(String? align) {
    switch (align) {
      case 'center':
        return Alignment.center;
      case 'left':
        return Alignment.centerLeft;
      case 'right':
        return Alignment.centerRight;
      case 'justify':
        return Alignment.center;
      default:
        return Alignment.center;
    }
  }

  MainAxisAlignment _getMainAxisAlignment(String? align) {
    switch (align) {
      case 'center':
        return MainAxisAlignment.center;
      case 'start':
        return MainAxisAlignment.start;
      case 'end':
        return MainAxisAlignment.end;
      case 'spaceBetween':
        return MainAxisAlignment.spaceBetween;
      case 'spaceAround':
        return MainAxisAlignment.spaceAround;
      case 'spaceEvenly':
        return MainAxisAlignment.spaceEvenly;
      default:
        return MainAxisAlignment.start;
    }
  }

  Widget _buildTabControl(PaywallElement element, BuildContext context) {
    _debugPaywallParserLog('Building tab-control for element: ${element.id}');

    // Find all group elements that are children of this tab-control
    final List<PaywallElement> groupElements = (paywallData.elements ?? [])
        .where((e) => e.type == 'group' && e.id != null)
        .toList();

    _debugPaywallParserLog('Found ${groupElements.length} group elements');

    if (groupElements.isEmpty) {
      _debugPaywallParserLog('No group elements found for tab-control');
      return const SizedBox.shrink();
    }

    // Build tab buttons
    final List<Widget> tabButtons = [];

    for (final groupElement in groupElements) {
      final bool isSelected = groupElement.id == element.selectedPackageId;
      final String title = groupElement.title ?? '';

      _debugPaywallParserLog(
        'Group element: ${groupElement.id}, Title: $title, Is Selected: $isSelected',
      );

      // Get states for styling
      final PaywallElementStates? elementStates = element.states;
      final containerStyle = isSelected
          ? elementStates?.selected?.containerStyle
          : elementStates?.defaultState?.containerStyle;

      final textStyle = isSelected
          ? elementStates?.selected?.textStyle
          : elementStates?.defaultState?.textStyle;

      // Build tab button
      final Widget tabButton = _buildTabButton(
        groupElement,
        title,
        isSelected,
        containerStyle,
        textStyle,
      );

      tabButtons.add(tabButton);
    }

    // Apply common styles and layout
    Widget result = Row(
      mainAxisAlignment: _getMainAxisAlignment(element.contentLayout?.align),
      children: tabButtons,
    );

    return _applyCommonStyles(result, element);
  }

  Widget _buildTabButton(
    PaywallElement groupElement,
    String title,
    bool isSelected,
    PaywallContainerStyle? containerStyle,
    PaywallTextStyle? textStyle,
  ) {
    // Get container decoration
    final containerDecoration = PaywallAssetsHelper.getBoxDecoration(
      _assets,
      containerStyle?.background,
      containerStyle?.border,
      containerStyle?.cornerRadius,
      containerStyle?.borderThickness,
    );

    // Get text style
    final textStyleData = PaywallAssetsHelper.getTextStyle(
      _assets,
      textStyle?.fontId,
      textStyle?.color,
      isRTL: _localizationHelper.isRTL,
      context: context,
      customFontFamily: _customFontFamily,
    );

    return Expanded(
      child: GestureDetector(
        onTap: () {
          _debugPaywallParserLog('Tab selected: ${groupElement.id}');
          // TODO: Implement tab selection callback
        },
        child: Container(
          decoration: containerDecoration,
          padding: PaywallAssetsHelper.getPadding(groupElement.padding),
          child: Center(
            child: Text(
              title,
              style: textStyleData,
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildGroup(PaywallElement element, BuildContext context) {
    _debugPaywallParserLog('Building group for element: ${element.id}');

    // Groups are typically containers for other elements
    // In the context of tabs, they contain package items
    // For now, return a simple container that can be styled
    Widget result = Center(
      child: Text(
        element.title ?? '',
        style: TextStyle(
          color: Colors.white,
          fontSize: 16,
          fontFamily: _customFontFamily,
        ),
      ),
    );

    return _applyCommonStyles(result, element);
  }
}

class CurveClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    final path = Path();

    path.moveTo(0, 0);
    path.lineTo(size.width, 0);
    path.lineTo(size.width, size.height * 0.9);

    // Convex curve facing UP with a gentle arc
    path.quadraticBezierTo(
      size.width * 0.5, // Control point X (center)
      size.height * 0.7, // Control point Y (slightly lower = gentler curve)
      0, // End point X
      size.height * 0.9, // End point Y
    );

    path.lineTo(0, 0);
    return path;
  }

  @override
  bool shouldReclip(CustomClipper<Path> oldClipper) => false;
}

class ConcaveCurveClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    final path = Path();

    path.moveTo(0, 0);
    path.lineTo(size.width, 0);
    path.lineTo(size.width, size.height * 0.85);

    // Only ONE smooth convex curve from right to left
    path.quadraticBezierTo(
      size.width * 0.5, // Control point at center top
      size.height * 1.1, // Lower Y = deeper curve
      0, // End point left
      size.height * 0.85, // Same Y as right edge
    );

    path.lineTo(0, 0);
    return path;
  }

  @override
  bool shouldReclip(CustomClipper<Path> oldClipper) => false;
}

class TopRoundedClipper extends CustomClipper<Path> {
  final double radius;

  TopRoundedClipper({this.radius = 24});

  @override
  Path getClip(Size size) {
    final path = Path();

    // Create a rounded rectangle with only top corners rounded
    path.addRRect(
      RRect.fromRectAndCorners(
        Rect.fromLTWH(0, 0, size.width, size.height),
        topLeft: Radius.circular(radius),
        topRight: Radius.circular(radius),
        bottomLeft: Radius.zero,
        bottomRight: Radius.zero,
      ),
    );

    return path;
  }

  @override
  bool shouldReclip(CustomClipper<Path> oldClipper) {
    if (oldClipper is TopRoundedClipper) {
      return oldClipper.radius != radius;
    }
    return true;
  }
}

class YellowOverlayClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    final path = Path();

    // Start from bottom-left
    path.moveTo(0, size.height);

    // Line up to bottom of left corner
    path.lineTo(0, 20);

    // Top-left arc (rounded corner)
    path.quadraticBezierTo(
      0, // Control point X
      0, // Control point Y
      20, // End point X
      0, // End point Y
    );

    // Top line to top-right arc
    path.lineTo(size.width - 20, 0);

    // Top-right arc (rounded corner)
    path.quadraticBezierTo(
      size.width, // Control point X
      0, // Control point Y
      size.width, // End point X
      20, // End point Y
    );

    // Line down to bottom-right
    path.lineTo(size.width, size.height);

    // Close the path
    path.close();

    return path;
  }

  @override
  bool shouldReclip(CustomClipper<Path> oldClipper) => false;
}
