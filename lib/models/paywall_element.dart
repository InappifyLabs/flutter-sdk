import 'package:inappify_sdk/models/paywall_action.dart';
import 'package:inappify_sdk/models/paywall_badge_style.dart';
import 'package:inappify_sdk/models/paywall_content_layout.dart';
import 'package:inappify_sdk/models/paywall_divider.dart';
import 'package:inappify_sdk/models/paywall_connector.dart';
import 'package:inappify_sdk/models/paywall_element_states.dart';
import 'package:inappify_sdk/models/paywall_image_file.dart';
import 'package:inappify_sdk/models/paywall_links.dart';
import 'package:inappify_sdk/models/paywall_text.dart';
import 'package:inappify_sdk/models/paywall_text_style.dart';
import 'package:inappify_sdk/models/paywall_top_button.dart';
import 'package:json_annotation/json_annotation.dart';

part 'paywall_element.g.dart';

@JsonSerializable()
class PaywallElement {
  PaywallElement({
    this.id,
    this.type,
    this.padding,
    this.spacing,
    this.topButton,
    this.background,
    this.offset,
    this.maskType,
    this.imageFile,
    this.iconFile,
    this.iconWidth,
    this.iconHeight,
    this.tintColor,
    this.maskHeight,
    this.imageHeight,
    this.cornerRadius,
    this.color,
    this.fontId,
    this.hAlign,
    this.margin,
    this.maxRows,
    this.stringId,
    this.onOverflow,
    this.text,
    this.title,
    this.action,
    this.border,
    this.previewType,
    this.primaryFont,
    this.primaryColor,
    this.contentLayout,
    this.secondaryFont,
    this.secondaryColor,
    this.borderThickness,
    this.links,
    this.divider,
    this.textStyle,
    this.states,
    this.groupBy,
    this.previewState,
    this.previewTextStyle,
    this.selectedPackageId,
    this.badge,
    this.badgeStyle,
    this.key,
    this.connector,
  });

  final String? id;
  final String? type;
  final List<int>? padding;
  final String? spacing;
  final PaywallTopButton? topButton;
  final String? background;
  final String? offset;
  final String? maskType;
  final PaywallImageFile? imageFile;
  final PaywallImageFile? iconFile;
  final String? iconWidth;
  final String? iconHeight;
  final String? tintColor;
  final int? maskHeight;
  final int? imageHeight;
  final List<int>? cornerRadius;
  final String? color;
  final String? fontId;
  final String? hAlign;
  final List<int>? margin;
  final String? maxRows;
  final String? stringId;
  final String? onOverflow;
  @JsonKey(name: 'text')
  final PaywallText? text;
  final String? title;
  final PaywallAction? action;
  final String? border;
  final String? previewType;
  final String? primaryFont;
  final String? primaryColor;
  final PaywallContentLayout? contentLayout;
  final String? secondaryFont;
  final String? secondaryColor;
  final String? borderThickness;
  final PaywallLinks? links;
  final PaywallDivider? divider;
  final PaywallTextStyle? textStyle;
  final PaywallElementStates? states;
  final String? groupBy;
  final String? previewState;
  final String? previewTextStyle;
  final String? selectedPackageId;
  final String? badge;
  final PaywallBadgeStyle? badgeStyle;
  final String? key;
  final PaywallConnector? connector;

  /// Returns a new instance of [PaywallElement] with the provided fields
  /// replaced, while preserving the values of all unspecified fields.
  PaywallElement copyWith({
    String? id,
    String? type,
    List<int>? padding,
    String? spacing,
    PaywallTopButton? topButton,
    String? background,
    String? offset,
    String? maskType,
    PaywallImageFile? imageFile,
    PaywallImageFile? iconFile,
    String? iconWidth,
    String? iconHeight,
    String? tintColor,
    int? maskHeight,
    int? imageHeight,
    List<int>? cornerRadius,
    String? color,
    String? fontId,
    String? hAlign,
    List<int>? margin,
    String? maxRows,
    String? stringId,
    String? onOverflow,
    PaywallText? text,
    String? title,
    PaywallAction? action,
    String? border,
    String? previewType,
    String? primaryFont,
    String? primaryColor,
    PaywallContentLayout? contentLayout,
    String? secondaryFont,
    String? secondaryColor,
    String? borderThickness,
    PaywallLinks? links,
    PaywallDivider? divider,
    PaywallTextStyle? textStyle,
    PaywallElementStates? states,
    String? groupBy,
    String? previewState,
    String? previewTextStyle,
    String? selectedPackageId,
    String? badge,
    PaywallBadgeStyle? badgeStyle,
    String? key,
    PaywallConnector? connector,
  }) {
    return PaywallElement(
      id: id ?? this.id,
      type: type ?? this.type,
      padding: padding ?? this.padding,
      spacing: spacing ?? this.spacing,
      topButton: topButton ?? this.topButton,
      background: background ?? this.background,
      offset: offset ?? this.offset,
      maskType: maskType ?? this.maskType,
      imageFile: imageFile ?? this.imageFile,
      iconFile: iconFile ?? this.iconFile,
      iconWidth: iconWidth ?? this.iconWidth,
      iconHeight: iconHeight ?? this.iconHeight,
      tintColor: tintColor ?? this.tintColor,
      maskHeight: maskHeight ?? this.maskHeight,
      imageHeight: imageHeight ?? this.imageHeight,
      cornerRadius: cornerRadius ?? this.cornerRadius,
      color: color ?? this.color,
      fontId: fontId ?? this.fontId,
      hAlign: hAlign ?? this.hAlign,
      margin: margin ?? this.margin,
      maxRows: maxRows ?? this.maxRows,
      stringId: stringId ?? this.stringId,
      onOverflow: onOverflow ?? this.onOverflow,
      text: text ?? this.text,
      title: title ?? this.title,
      action: action ?? this.action,
      border: border ?? this.border,
      previewType: previewType ?? this.previewType,
      primaryFont: primaryFont ?? this.primaryFont,
      primaryColor: primaryColor ?? this.primaryColor,
      contentLayout: contentLayout ?? this.contentLayout,
      secondaryFont: secondaryFont ?? this.secondaryFont,
      secondaryColor: secondaryColor ?? this.secondaryColor,
      borderThickness: borderThickness ?? this.borderThickness,
      links: links ?? this.links,
      divider: divider ?? this.divider,
      textStyle: textStyle ?? this.textStyle,
      states: states ?? this.states,
      groupBy: groupBy ?? this.groupBy,
      previewState: previewState ?? this.previewState,
      previewTextStyle: previewTextStyle ?? this.previewTextStyle,
      selectedPackageId: selectedPackageId ?? this.selectedPackageId,
      badge: badge ?? this.badge,
      badgeStyle: badgeStyle ?? this.badgeStyle,
      key: key ?? this.key,
      connector: connector ?? this.connector,
    );
  }

  factory PaywallElement.fromJson(Map<String, dynamic> json) =>
      _$PaywallElementFromJson(json);
  Map<String, dynamic> toJson() => _$PaywallElementToJson(this);
}
