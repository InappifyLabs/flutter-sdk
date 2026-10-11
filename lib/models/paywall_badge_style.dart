import 'package:json_annotation/json_annotation.dart';

part 'paywall_badge_style.g.dart';

@JsonSerializable()
class PaywallBadgeStyle {
  PaywallBadgeStyle({
    this.visible,
    this.background,
    this.cornerRadius,
    this.color,
  });

  final bool? visible;
  final String? background;
  final List<int>? cornerRadius;
  final String? color;

  factory PaywallBadgeStyle.fromJson(Map<String, dynamic> json) =>
      _$PaywallBadgeStyleFromJson(json);
  Map<String, dynamic> toJson() => _$PaywallBadgeStyleToJson(this);
}
