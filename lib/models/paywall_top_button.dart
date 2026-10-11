import 'package:json_annotation/json_annotation.dart';

part 'paywall_top_button.g.dart';

@JsonSerializable(explicitToJson: true)
class PaywallTopButton {
  final String? align;
  final PaywallTopButtonStyle? style;
  final PaywallTopButtonAction? action;
  final String? styleType;

  PaywallTopButton({
    this.align,
    this.style,
    this.action,
    this.styleType,
  });

  factory PaywallTopButton.fromJson(Map<String, dynamic> json) =>
      _$PaywallTopButtonFromJson(json);
  Map<String, dynamic> toJson() => _$PaywallTopButtonToJson(this);
}

@JsonSerializable()
class PaywallTopButtonStyle {
  final PaywallTopButtonIcon? icon;
  final String? border;
  final String? fontId;
  final String? hashSum;
  final bool? visible;
  final String? stringId;
  final int? thickness;
  final String? background;
  final List<int>? cornerRadius;

  PaywallTopButtonStyle({
    this.icon,
    this.border,
    this.fontId,
    this.hashSum,
    this.visible,
    this.stringId,
    this.thickness,
    this.background,
    this.cornerRadius,
  });

  factory PaywallTopButtonStyle.fromJson(Map<String, dynamic> json) =>
      _$PaywallTopButtonStyleFromJson(json);
  Map<String, dynamic> toJson() => _$PaywallTopButtonStyleToJson(this);
}

@JsonSerializable()
class PaywallTopButtonIcon {
  final String? type;
  final String? color;

  PaywallTopButtonIcon({
    this.type,
    this.color,
  });

  factory PaywallTopButtonIcon.fromJson(Map<String, dynamic> json) =>
      _$PaywallTopButtonIconFromJson(json);
  Map<String, dynamic> toJson() => _$PaywallTopButtonIconToJson(this);
}

@JsonSerializable()
class PaywallTopButtonAction {
  final String? id;
  final String? type;

  PaywallTopButtonAction({
    this.id,
    this.type,
  });

  factory PaywallTopButtonAction.fromJson(Map<String, dynamic> json) =>
      _$PaywallTopButtonActionFromJson(json);
  Map<String, dynamic> toJson() => _$PaywallTopButtonActionToJson(this);
}
