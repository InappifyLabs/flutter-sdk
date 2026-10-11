import 'package:json_annotation/json_annotation.dart';

part 'paywall_image_file.g.dart';

@JsonSerializable()
class PaywallImageFile {
  final String? type;
  final String? asset;

  PaywallImageFile({
    this.type,
    this.asset,
  });

  factory PaywallImageFile.fromJson(Map<String, dynamic> json) =>
      _$PaywallImageFileFromJson(json);
  Map<String, dynamic> toJson() => _$PaywallImageFileToJson(this);
}
