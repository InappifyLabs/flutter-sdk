import 'package:json_annotation/json_annotation.dart';

part 'paywall_content_layout.g.dart';

@JsonSerializable()
class PaywallContentLayout {
  PaywallContentLayout({
    this.align,
    this.type,
    this.padding,
    this.spacing,
    this.background,
    this.border,
    this.cornerRadius,
    this.borderThickness,
    this.offset,
  });

  final String? align;
  final String? type;
  final List<int>? padding;
  final String? spacing;
  final String? background;
  final String? border;
  final List<int>? cornerRadius;
  final String? borderThickness;
  final String? offset;

  factory PaywallContentLayout.fromJson(Map<String, dynamic> json) =>
      _$PaywallContentLayoutFromJson(json);
  Map<String, dynamic> toJson() => _$PaywallContentLayoutToJson(this);
}
