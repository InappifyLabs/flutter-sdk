import 'package:json_annotation/json_annotation.dart';

part 'paywall_text_style.g.dart';

@JsonSerializable()
class PaywallTextStyle {
  PaywallTextStyle({
    this.color,
    this.colorId,
    this.fontId,
    this.text,
    this.text1,
    this.text2,
    this.text3,
    this.text4,
    this.title,
    this.caption,
  });

  final String? color;
  final String? colorId;
  final String? fontId;
  final PaywallTextStyle? text;
  final PaywallTextStyle? text1;
  final PaywallTextStyle? text2;
  final PaywallTextStyle? text3;
  final PaywallTextStyle? text4;
  final PaywallTextStyle? title;
  final PaywallTextStyle? caption;

  factory PaywallTextStyle.fromJson(Map<String, dynamic> json) =>
      _$PaywallTextStyleFromJson(json);
  Map<String, dynamic> toJson() => _$PaywallTextStyleToJson(this);
}
