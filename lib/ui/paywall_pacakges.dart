import 'package:inappify_sdk/src/logging/sdk_logger.dart';
import 'package:flutter/material.dart';
import 'package:collection/collection.dart';
import 'package:inappify_sdk/helpers/localization_helper.dart';
import 'package:inappify_sdk/helpers/paywall_assets_helper.dart';
import 'package:inappify_sdk/models/offering_packages_product.dart';
import 'package:inappify_sdk/models/paywall.dart';
import 'package:inappify_sdk/models/paywall_asset.dart';
import 'package:inappify_sdk/models/paywall_element.dart';
import 'package:inappify_sdk/models/paywall_text_style.dart';
import 'package:inappify_sdk/models/paywall_element_states.dart';
import 'package:inappify_sdk/models/offering_packages.dart';
import 'package:inappify_sdk/models/paywall_item_tree_state.dart';

/// Emits structural diagnostics without localized text, URLs or dynamic values.
void _debugPaywallLog(String message) {
  SdkLogger.verbose('Paywall package event.');
}

class PaywallPackages extends StatefulWidget {
  const PaywallPackages({
    super.key,
    required this.element,
    required this.assets,
    required this.localizationHelper,
    required this.paywallData,
    required this.onPackageIdChanged,
    this.customFontFamily,
  });

  final PaywallElement element;
  final List<PaywallAsset> assets;
  final LocalizationHelper localizationHelper;
  final Paywall paywallData;
  final Function(String?) onPackageIdChanged;
  final String? customFontFamily;

  @override
  State<PaywallPackages> createState() => _PaywallPackagesState();
}

class _PaywallPackagesState extends State<PaywallPackages> {
  String? _selectedPackageId;
  String? _selectedGroupIdForTabs;

  // When a horizontal list has only 1 child (no scroll), expand it to full width.
  // When it has more than 1 child (scrollable), keep natural sizes with spacing.
  Widget _HorizontalMaybeExpand({
    required List<Widget> children,
    required double spacing,
  }) {
    return _AdaptiveHorizontal(children: children, spacing: spacing);
  }

  // Layout widget that measures children and decides:
  // - If total width <= screen width -> distribute space among items (no scroll)
  // - Else -> keep natural widths and allow horizontal scroll
  // It renders children once in an offstage Row to measure, then builds accordingly.
  // Note: This keeps layout cheap by avoiding per-child IntrinsicWidth in scroll mode.
  Widget _AdaptiveHorizontal({
    required List<Widget> children,
    required double spacing,
  }) {
    if (children.isEmpty) return const SizedBox.shrink();

    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth = constraints.maxWidth;

        // Build an offstage row to measure natural width
        final measure = _MeasureRow(
          spacing: spacing,
          children: children,
        );

        return _MeasuredBuilder(
          measure: measure,
          builder: (context, naturalWidth) {
            final bool fits = naturalWidth <= maxWidth + 0.5;
            if (fits) {
              // Distribute width among items (no scroll)
              final itemCount = children.length;
              final totalSpacing =
                  spacing * (itemCount > 0 ? itemCount - 1 : 0);
              final double itemWidth =
                  itemCount > 0 ? (maxWidth - totalSpacing) / itemCount : 0;

              return Row(
                children: [
                  for (int i = 0; i < itemCount; i++) ...[
                    SizedBox(width: itemWidth, child: children[i]),
                    if (i < itemCount - 1) SizedBox(width: spacing),
                  ]
                ],
              );
            } else {
              // Keep natural sizes with horizontal scroll
              return SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    for (int i = 0; i < children.length; i++) ...[
                      children[i],
                      if (i < children.length - 1) SizedBox(width: spacing),
                    ],
                  ],
                ),
              );
            }
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: PaywallAssetsHelper.getPadding(widget.element.padding),
      child: _buildPackages(
        widget.element,
        onPackageSelected: (String packageId) {
          if (_selectedPackageId != packageId) {
            _selectedPackageId = packageId;
            _debugPaywallLog('Selected package changed to: $packageId');

            // Update the selectedPackageId in paywallData
            final packagesElement = (widget.paywallData.elements ?? [])
                .firstWhereOrNull((e) => e.type == 'packages');
            if (packagesElement != null) {
              // Note: This won't actually modify the original data since PaywallElement is immutable
              // But we can use this for debugging
              _debugPaywallLog(
                'Packages element found, would update selectedPackageId to: $packageId',
              );
            }
            widget.onPackageIdChanged.call(packageId);
            setState(() {});
          }
        },
      ),
    );
  }

  Widget _buildPackages(PaywallElement element,
      {Function(String)? onPackageSelected}) {
    // Check if packages are grouped by tabs
    if (element.groupBy == 'tabs') {
      return _buildPackagesWithTabs(element,
          onPackageSelected: onPackageSelected);
    }

    // First try to find packages directly in items_trees_state (top-level)
    List<PaywallItemTreeState> packageItemIds =
        (widget.paywallData.itemsTreesState ?? [])
                .firstWhereOrNull((item) => item.id == element.id)
                ?.children
                ?.toList() ??
            [];

    // If not found directly, look for packages inside footer
    if (packageItemIds.isEmpty) {
      final footerTree = (widget.paywallData.itemsTreesState ?? [])
          .firstWhereOrNull((item) => item.id == 'footer');

      if (footerTree != null) {
        final packagesTree = footerTree.children
            ?.firstWhereOrNull((item) => item.id == element.id);

        if (packagesTree != null) {
          packageItemIds = packagesTree.children?.toList() ?? [];
        }
      }
    }

    // If still not found, search the entire items_trees_state tree recursively.
    if (packageItemIds.isEmpty) {
      final foundNode = _findTreeNodeById(
          widget.paywallData.itemsTreesState ?? [], element.id);
      if (foundNode != null) {
        packageItemIds = foundNode.children?.toList() ?? [];
      }
    }

    _debugPaywallLog(
      'Found ${packageItemIds.length} package items for element ${element.id}',
    );

    if (packageItemIds.isEmpty) {
      _debugPaywallLog('No package items found for element ${element.id}');
      return const SizedBox.shrink();
    }

    final List<Widget> packageItemsWidgets = [];
    final String? selectedPackageId =
        _selectedPackageId ?? element.selectedPackageId;

    final bool isHorizontal = element.contentLayout?.type == 'horizontal';

    for (var itemTree in packageItemIds) {
      final PaywallElement? packageItemElement =
          (widget.paywallData.elements ?? [])
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
          _debugPaywallLog(
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
            (widget.paywallData.offeringPackages ?? [])
                .firstWhereOrNull((op) => op.id.toString() == numericId);
        final OfferingPackagesProduct? product =
            offeringPackage?.products?.firstOrNull;

        _debugPaywallLog(
          'Package item ID: ${packageItemElement.id}, Numeric ID: $numericId, Offering package found: ${offeringPackage != null}',
        );

        packageItemsWidgets.add(
          _buildPackageItem(
            packageItemElement,
            element,
            isSelected,
            offeringPackage: offeringPackage,
            product: product,
            isHorizontal: isHorizontal,
            onPackageSelected: onPackageSelected,
          ),
        );
      }
    }

    final double spacing =
        double.tryParse(element.contentLayout?.spacing ?? '0') ?? 0;

    // Check if contentLayout type is horizontal for horizontal scrolling
    if (isHorizontal) {
      return _HorizontalMaybeExpand(
        children: packageItemsWidgets,
        spacing: spacing,
      );
    } else {
      return Column(
        children: packageItemsWidgets
            .expand((widget) => [
                  widget,
                  if (packageItemsWidgets.indexOf(widget) <
                      packageItemsWidgets.length - 1)
                    SizedBox(height: spacing),
                ])
            .toList(),
      );
    }
  }

  // Depth-first search to find a node by id anywhere in items_trees_state
  PaywallItemTreeState? _findTreeNodeById(
      List<PaywallItemTreeState> nodes, String? targetId) {
    if (targetId == null || targetId.isEmpty) return null;
    for (final node in nodes) {
      if (node.id == targetId) return node;
      final children = node.children;
      if (children != null && children.isNotEmpty) {
        final found = _findTreeNodeById(children, targetId);
        if (found != null) return found;
      }
    }
    return null;
  }

  // Collect package-item nodes under a subtree, ordered by sortOrder if available
  List<PaywallItemTreeState> _collectPackageItemNodes(
      PaywallItemTreeState root) {
    final List<PaywallItemTreeState> result = [];

    void dfs(PaywallItemTreeState node) {
      if (node.id != null) {
        final PaywallElement? el = (widget.paywallData.elements ?? [])
            .firstWhereOrNull((e) => e.id == node.id);
        if (el != null && el.type == 'package-item') {
          result.add(node);
        }
      }

      final children = (node.children ?? []).toList();
      children.sort((a, b) => (a.sortOrder ?? 0).compareTo(b.sortOrder ?? 0));
      for (final child in children) {
        dfs(child);
      }
    }

    dfs(root);
    return result;
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

    _debugPaywallLog(
      'Getting text for element ${element.id}, key: $textKey, textId: $textId',
    );

    final result = widget.localizationHelper.getString(
      textId,
      offeringPackage: offeringPackage,
      product: product,
    );

    _debugPaywallLog('Resolved text for ${element.id} $textKey: "$result"');
    return result;
  }

  String _getBadgeTextFromElement(
    PaywallElement element, {
    OfferingPackages? offeringPackage,
    OfferingPackagesProduct? product,
  }) {
    // First try to get badge text from assets
    final badgeTextFromAssets = PaywallAssetsHelper.getPaywallAssetText(
      widget.assets,
      element.badge,
    );

    if (badgeTextFromAssets != null && badgeTextFromAssets.isNotEmpty) {
      _debugPaywallLog('Getting badge text from assets: $badgeTextFromAssets');
      return badgeTextFromAssets;
    }

    // Fallback to localization helper if badge is a string ID
    if (element.badge != null && element.badge!.isNotEmpty) {
      _debugPaywallLog(
        'Getting badge text from localization: ${element.badge}',
      );
      return widget.localizationHelper.getString(
        element.badge!,
        offeringPackage: offeringPackage,
        product: product,
      );
    }

    return '';
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

    _debugPaywallLog(
      'Container style - Is Selected: $isSelected, Using: ${isSelected ? "selected" : "default"}',
    );
    _debugPaywallLog('Container style: $containerStyle');
    _debugPaywallLog('Background: ${containerStyle?.background}');
    _debugPaywallLog('Border: ${containerStyle?.border}');
    _debugPaywallLog('Corner radius: ${containerStyle?.cornerRadius}');

    final containerDecoration = PaywallAssetsHelper.getBoxDecoration(
      widget.assets,
      containerStyle?.background,
      containerStyle?.border,
      containerStyle?.cornerRadius,
      containerStyle?.borderThickness,
    );

    _debugPaywallLog('Container decoration: $containerDecoration');

    // Use fallback decoration if null
    final finalContainerDecoration = containerDecoration;

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

    final textStyle1 = PaywallAssetsHelper.getTextStyle(
      widget.assets,
      textStyleState?.text1?.fontId,
      textStyleState?.text1?.color ?? textStyleState?.text1?.colorId,
      isRTL: widget.localizationHelper.isRTL,
      context: context,
      customFontFamily: widget.customFontFamily,
    );
    final textStyle2 = PaywallAssetsHelper.getTextStyle(
      widget.assets,
      textStyleState?.text2?.fontId,
      textStyleState?.text2?.color ?? textStyleState?.text2?.colorId,
      isRTL: widget.localizationHelper.isRTL,
      context: context,
      customFontFamily: widget.customFontFamily,
    );
    final textStyle3 = PaywallAssetsHelper.getTextStyle(
      widget.assets,
      textStyleState?.text3?.fontId,
      textStyleState?.text3?.color ?? textStyleState?.text3?.colorId,
      isRTL: widget.localizationHelper.isRTL,
      context: context,
      customFontFamily: widget.customFontFamily,
    );
    final textStyle4 = PaywallAssetsHelper.getTextStyle(
      widget.assets,
      textStyleState?.text4?.fontId,
      textStyleState?.text4?.color ?? textStyleState?.text4?.colorId,
      isRTL: widget.localizationHelper.isRTL,
      context: context,
      customFontFamily: widget.customFontFamily,
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
                packageItemElement.contentLayout!.padding)
            : const EdgeInsets.symmetric(
                horizontal: 8); // Default inner padding if not specified

    final double itemContentSpacing =
        double.tryParse(packageItemElement.contentLayout?.spacing ?? '0') ?? 0;

    return Stack(
      clipBehavior: Clip.none, // Allow children to extend beyond Stack bounds
      children: [
        GestureDetector(
          onTap: () {
            _debugPaywallLog('Package item ${packageItemElement.id} selected!');
            // Extract numeric ID from package item ID (e.g., "7-package-item-..." -> "7")
            String? numericId;
            if (packageItemElement.id != null &&
                packageItemElement.id!.contains('-')) {
              numericId = packageItemElement.id!.split('-')[0];
            } else {
              numericId = packageItemElement.id;
            }

            if (numericId != null && onPackageSelected != null) {
              _debugPaywallLog('Calling onPackageSelected with: $numericId');
              onPackageSelected(numericId);
            }
          },
          child: Container(
            height: isHorizontal ? 130 : null,
            decoration: finalContainerDecoration,
            padding: itemInnerPadding,
            child: Column(
              crossAxisAlignment: isHorizontal
                  ? CrossAxisAlignment.center
                  : CrossAxisAlignment.stretch,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Use Row for horizontal layout within each package item when not horizontal
                isHorizontal
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          // Title (text1 or packageItemElement.title)
                          if (text1.isNotEmpty)
                            Text(text1,
                                style: finalTextStyle1,
                                textAlign: TextAlign.center)
                          else if (packageItemElement.title != null &&
                              packageItemElement.title!.isNotEmpty)
                            Text(packageItemElement.title!,
                                style: finalTextStyle1 ??
                                    TextStyle(
                                        fontFamily: widget.customFontFamily),
                                textAlign: TextAlign.center),

                          SizedBox(height: itemContentSpacing),

                          // Price (text2)
                          if (text2.isNotEmpty)
                            Text(text2,
                                style: finalTextStyle2,
                                textAlign: TextAlign.center),

                          SizedBox(height: itemContentSpacing),

                          // Description (text3)
                          if (text3.isNotEmpty)
                            Text(text3,
                                style: finalTextStyle3,
                                textAlign: TextAlign.center),

                          // Additional info (text4)
                          if (text4.isNotEmpty)
                            Text(
                              text4,
                              style: finalTextStyle4,
                              textAlign: TextAlign.center,
                            ),
                        ],
                      )
                    : Padding(
                        padding: const EdgeInsets.all(12.0),
                        child: Column(
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                if (text1.isNotEmpty)
                                  Text(text1,
                                      style: finalTextStyle1,
                                      textAlign: TextAlign.center)
                                else if (packageItemElement.title != null &&
                                    packageItemElement.title!.isNotEmpty)
                                  Text(packageItemElement.title!,
                                      style: finalTextStyle1 ??
                                          TextStyle(
                                              fontFamily:
                                                  widget.customFontFamily),
                                      textAlign: TextAlign.center),
                                if (text2.isNotEmpty)
                                  Text(text2,
                                      style: finalTextStyle2,
                                      textAlign: TextAlign.center),
                              ],
                            ),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                if (text3.isNotEmpty)
                                  Text(text3,
                                      style: finalTextStyle3,
                                      textAlign: TextAlign.center),
                                if (text4.isNotEmpty)
                                  Text(
                                    text4,
                                    style: finalTextStyle4,
                                    textAlign: TextAlign.center,
                                  ),
                              ],
                            )
                          ],
                        ),
                      ),
              ]
                  .where((widget) => !(widget is SizedBox &&
                      (widget.height == 0 || widget.width == 0)))
                  .toList(),
            ),
          ),
        ),
        // Badge positioned to overlap the top-left corner
        if (packageItemElement.badgeStyle?.visible == true &&
            _getBadgeTextFromElement(
              packageItemElement,
              offeringPackage: offeringPackage,
              product: product,
            ).isNotEmpty)
          PositionedDirectional(
            top: -8, // Position badge to overlap the top border
            end: 12, // Position badge to overlap the left border
            child: Container(
              decoration: PaywallAssetsHelper.getBoxDecoration(
                widget.assets,
                packageItemElement.badgeStyle?.background,
                null,
                packageItemElement.badgeStyle?.cornerRadius,
                '0',
              ),
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Text(
                _getBadgeTextFromElement(
                  packageItemElement,
                  offeringPackage: offeringPackage,
                  product: product,
                ),
                style: TextStyle(
                  color: PaywallAssetsHelper.getPaywallAssetColor(
                    widget.assets,
                    packageItemElement.badgeStyle?.color,
                  ),
                  fontSize: 12,
                  fontFamily: widget.customFontFamily,
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildPackagesWithTabs(
    PaywallElement element, {
    Function(String)? onPackageSelected,
  }) {
    _debugPaywallLog('Building packages with tabs for element: ${element.id}');

    // Find the tab-control element
    final PaywallElement? tabControlElement =
        (widget.paywallData.elements ?? [])
            .firstWhereOrNull((e) => e.type == 'tab-control');

    if (tabControlElement == null) {
      _debugPaywallLog('No tab-control element found');
      return const SizedBox.shrink();
    }

    // Find all group elements
    final List<PaywallElement> groupElements =
        (widget.paywallData.elements ?? [])
            .where((e) => e.type == 'group')
            .toList();

    _debugPaywallLog('Found ${groupElements.length} group elements');

    if (groupElements.isEmpty) {
      _debugPaywallLog('No group elements found');
      return const SizedBox.shrink();
    }

    // Resolve selected group (tab)
    final String? selectedGroupId = _selectedGroupIdForTabs ??
        tabControlElement.selectedPackageId ??
        (groupElements.isNotEmpty ? groupElements.first.id : null);
    final PaywallElement? selectedGroup =
        groupElements.firstWhereOrNull((g) => g.id == selectedGroupId);

    _debugPaywallLog('Selected group ID: $selectedGroupId');

    // Build tab control
    final Widget tabControl = _buildTabControlForPackages(
      tabControlElement,
      groupElements,
      selectedGroupId: selectedGroupId,
      onTabSelected: (PaywallElement group) {
        setState(() {
          _selectedGroupIdForTabs = group.id;
        });
      },
    );

    // Build packages for the selected group
    final Widget packagesWidget = _buildPackagesForGroup(
      selectedGroup ?? groupElements.first,
      element,
      onPackageSelected,
    );

    return Column(
      children: [
        tabControl,
        const SizedBox(height: 16),
        packagesWidget,
      ],
    );
  }

  Widget _buildTabControlForPackages(
    PaywallElement tabControlElement,
    List<PaywallElement> groupElements, {
    String? selectedGroupId,
    required void Function(PaywallElement group) onTabSelected,
  }) {
    final List<Widget> tabButtons = [];

    for (final groupElement in groupElements) {
      final bool isSelected = groupElement.id == selectedGroupId;
      final String title = groupElement.title ?? '';

      _debugPaywallLog(
        'Group element: ${groupElement.id}, Title: $title, Is Selected: $isSelected',
      );

      // Get states for styling
      final PaywallElementStates? elementStates = tabControlElement.states;
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
        onTap: () => onTabSelected(groupElement),
      );

      tabButtons.add(tabButton);
    }

    // Map alignment from contentLayout
    MainAxisAlignment mainAxisAlignment = MainAxisAlignment.spaceEvenly;
    final align = tabControlElement.contentLayout?.align;
    switch (align) {
      case 'justify':
        mainAxisAlignment = MainAxisAlignment.spaceBetween;
        break;
      case 'center':
        mainAxisAlignment = MainAxisAlignment.center;
        break;
      case 'start':
        mainAxisAlignment = MainAxisAlignment.start;
        break;
      case 'end':
        mainAxisAlignment = MainAxisAlignment.end;
        break;
      case 'around':
        mainAxisAlignment = MainAxisAlignment.spaceAround;
        break;
      case 'evenly':
        mainAxisAlignment = MainAxisAlignment.spaceEvenly;
        break;
    }

    // Apply spacing between tabs if provided
    final double spacing =
        double.tryParse(tabControlElement.contentLayout?.spacing ?? '0') ?? 0;
    List<Widget> childrenWithSpacing = tabButtons;
    if (spacing > 0) {
      childrenWithSpacing = [];
      for (int i = 0; i < tabButtons.length; i++) {
        childrenWithSpacing.add(tabButtons[i]);
        if (i < tabButtons.length - 1) {
          childrenWithSpacing.add(SizedBox(width: spacing));
        }
      }
      // When we manually space items, left-align them
      mainAxisAlignment = MainAxisAlignment.start;
    }

    Widget row = Row(
      mainAxisAlignment: mainAxisAlignment,
      children: childrenWithSpacing,
    );

    // Wrap row in container using contentLayout styles (background/border/radius/padding)
    final layoutDeco = PaywallAssetsHelper.getBoxDecoration(
      widget.assets,
      tabControlElement.contentLayout?.background,
      tabControlElement.contentLayout?.border,
      tabControlElement.contentLayout?.cornerRadius,
      tabControlElement.contentLayout?.borderThickness,
    );

    final EdgeInsetsGeometry layoutPadding = PaywallAssetsHelper.getPadding(
        tabControlElement.contentLayout?.padding);

    Widget result = Container(
      decoration: layoutDeco,
      padding: layoutPadding,
      child: row,
    );

    // Apply outer padding from the tab control element itself
    if (tabControlElement.padding != null &&
        tabControlElement.padding!.length == 4) {
      result = Padding(
        padding: PaywallAssetsHelper.getPadding(tabControlElement.padding),
        child: result,
      );
    }

    return result;
  }

  Widget _buildTabButton(
      PaywallElement groupElement,
      String title,
      bool isSelected,
      PaywallContainerStyle? containerStyle,
      PaywallTextStyle? textStyle,
      {VoidCallback? onTap}) {
    // Get container decoration
    final containerDecoration = PaywallAssetsHelper.getBoxDecoration(
      widget.assets,
      containerStyle?.background,
      containerStyle?.border,
      containerStyle?.cornerRadius,
      containerStyle?.borderThickness,
    );

    // Get text style (handle nested 'text' style or flat)
    final textStyleData = PaywallAssetsHelper.getTextStyle(
      widget.assets,
      (textStyle?.title ?? textStyle?.text1 ?? textStyle?.text)?.fontId ??
          textStyle?.fontId,
      (textStyle?.title ?? textStyle?.text1 ?? textStyle?.text)?.color ??
          (textStyle?.title ?? textStyle?.text1 ?? textStyle?.text)?.colorId ??
          textStyle?.color ??
          textStyle?.colorId,
      context: context,
      customFontFamily: widget.customFontFamily,
    );

    // Build a matching BorderRadius for clipping if needed
    BorderRadius? clipRadius;
    if (containerStyle?.cornerRadius != null &&
        containerStyle!.cornerRadius!.length == 4) {
      clipRadius = BorderRadius.only(
        topLeft: Radius.circular(containerStyle.cornerRadius![0].toDouble()),
        topRight: Radius.circular(containerStyle.cornerRadius![1].toDouble()),
        bottomRight:
            Radius.circular(containerStyle.cornerRadius![2].toDouble()),
        bottomLeft: Radius.circular(containerStyle.cornerRadius![3].toDouble()),
      );
    }

    return Expanded(
      child: GestureDetector(
        onTap: () {
          _debugPaywallLog('Tab selected: ${groupElement.id}');
          onTap?.call();
        },
        child: ClipRRect(
          borderRadius: clipRadius ?? BorderRadius.zero,
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
      ),
    );
  }

  Widget _buildPackagesForGroup(
    PaywallElement groupElement,
    PaywallElement packagesElement,
    Function(String)? onPackageSelected,
  ) {
    _debugPaywallLog('Building packages for group: ${groupElement.id}');

    // Prefer resolving items via items_trees_state under the selected group/tab
    List<PaywallElement> groupPackageItems = [];
    final List<PaywallItemTreeState> tree =
        widget.paywallData.itemsTreesState ?? [];
    final PaywallItemTreeState? groupNode =
        _findTreeNodeById(tree, groupElement.id);

    if (groupNode != null) {
      // If there is an explicit packages node under the group, start from there
      final PaywallItemTreeState? packagesNode = (groupNode.children ?? [])
          .firstWhereOrNull(
              (n) => n.id == packagesElement.id || n.type == 'packages');
      final PaywallItemTreeState baseNode = packagesNode ?? groupNode;
      final List<PaywallItemTreeState> packageItemNodes =
          _collectPackageItemNodes(baseNode);

      groupPackageItems = packageItemNodes
          .map((n) => (widget.paywallData.elements ?? [])
              .firstWhereOrNull((e) => e.id == n.id))
          .whereType<PaywallElement>()
          .toList();
    }

    // Fallback: if items_trees_state did not resolve anything, use legacy ID-pattern filter
    if (groupPackageItems.isEmpty) {
      final List<PaywallElement> packageItems =
          (widget.paywallData.elements ?? [])
              .where((e) => e.type == 'package-item' && e.id != null)
              .toList();
      groupPackageItems = packageItems
          .where((item) =>
              groupElement.id != null && item.id!.contains(groupElement.id!))
          .toList();
    }

    _debugPaywallLog(
      'Resolved ${groupPackageItems.length} package items for group ${groupElement.id}',
    );

    if (groupPackageItems.isEmpty) {
      return const SizedBox.shrink();
    }

    final List<Widget> packageItemsWidgets = [];
    final String? selectedPackageId =
        _selectedPackageId ?? packagesElement.selectedPackageId;
    final bool isHorizontal =
        packagesElement.contentLayout?.type == 'horizontal';

    for (final packageItemElement in groupPackageItems) {
      // Check if this package item is selected
      bool isSelected = false;
      if (selectedPackageId != null && packageItemElement.id != null) {
        String? packageNumericId;
        if (packageItemElement.id!.contains('-')) {
          packageNumericId = packageItemElement.id!.split('-')[0];
        } else {
          packageNumericId = packageItemElement.id;
        }
        isSelected = packageNumericId == selectedPackageId;
      }

      // Extract numeric ID from package item ID
      String? numericId;
      if (packageItemElement.id != null &&
          packageItemElement.id!.contains('-')) {
        numericId = packageItemElement.id!.split('-')[0];
      }

      final OfferingPackages? offeringPackage =
          (widget.paywallData.offeringPackages ?? [])
              .firstWhereOrNull((op) => op.id.toString() == numericId);
      final OfferingPackagesProduct? product =
          offeringPackage?.products?.firstOrNull;

      packageItemsWidgets.add(
        _buildPackageItem(
          packageItemElement,
          packagesElement,
          isSelected,
          offeringPackage: offeringPackage,
          product: product,
          isHorizontal: isHorizontal,
          onPackageSelected: onPackageSelected,
        ),
      );
    }

    final double spacing =
        double.tryParse(packagesElement.contentLayout?.spacing ?? '0') ?? 0;

    if (isHorizontal) {
      return _HorizontalMaybeExpand(
        children: packageItemsWidgets,
        spacing: spacing,
      );
    } else {
      return Column(
        children: packageItemsWidgets
            .expand((widget) => [
                  widget,
                  if (packageItemsWidgets.indexOf(widget) <
                      packageItemsWidgets.length - 1)
                    SizedBox(height: spacing),
                ])
            .toList(),
      );
    }
  }
}

class _MeasuredBuilder extends StatefulWidget {
  const _MeasuredBuilder({
    required this.measure,
    required this.builder,
  });

  final Widget measure;
  final Widget Function(BuildContext context, double naturalWidth) builder;

  @override
  State<_MeasuredBuilder> createState() => _MeasuredBuilderState();
}

class _MeasuredBuilderState extends State<_MeasuredBuilder> {
  final GlobalKey _key = GlobalKey();
  double? _width;

  @override
  void initState() {
    super.initState();
    // Delay measurement to next frame
    WidgetsBinding.instance.addPostFrameCallback((_) => _measure());
  }

  void _measure() {
    final context = _key.currentContext;
    if (context == null) return;
    final box = context.findRenderObject() as RenderBox?;
    if (box != null) {
      final width = box.size.width;
      if (mounted && _width != width) {
        setState(() {
          _width = width;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Offstage row used only for measurement
    final offstage = Offstage(
      offstage: true,
      child: _MeasureScope(
        key: _key,
        child: widget.measure,
      ),
    );

    final built = widget.builder(context, _width ?? double.infinity);
    return Stack(
      children: [
        offstage,
        built,
      ],
    );
  }
}

class _MeasureScope extends StatelessWidget {
  const _MeasureScope({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) {
    return Material(type: MaterialType.transparency, child: child);
  }
}

class _MeasureRow extends StatelessWidget {
  const _MeasureRow({required this.children, required this.spacing});
  final List<Widget> children;
  final double spacing;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (int i = 0; i < children.length; i++) ...[
          _Intrinsic(child: children[i]),
          if (i < children.length - 1) SizedBox(width: spacing),
        ]
      ],
    );
  }
}

class _Intrinsic extends StatelessWidget {
  const _Intrinsic({required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) {
    return IntrinsicWidth(child: child);
  }
}
