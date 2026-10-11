import 'package:json_annotation/json_annotation.dart';

part 'paywall_divider.g.dart';

@JsonSerializable()
class PaywallDivider {
  PaywallDivider({
    this.color,
    this.thickness,
  });

  final String? color;
  final String? thickness;

  factory PaywallDivider.fromJson(Map<String, dynamic> json) =>
      _$PaywallDividerFromJson(json);
  Map<String, dynamic> toJson() => _$PaywallDividerToJson(this);
}
