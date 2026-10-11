import 'package:json_annotation/json_annotation.dart';

part 'paywall_asset.g.dart';

@JsonSerializable()
class PaywallAsset {
  PaywallAsset({
    this.id,
    this.type,
    this.value,
    this.opacity,
    this.url,
    this.name,
    this.size,
  });
  final String? id;
  final String? type;
  final String? value;
  final double? opacity;
  final String? url;
  final String? name;
  final String? size;
  factory PaywallAsset.fromJson(Map<String, dynamic> json) =>
      _$PaywallAssetFromJson(json);
  Map<String, dynamic> toJson() => _$PaywallAssetToJson(this);
}
