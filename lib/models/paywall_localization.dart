import 'package:json_annotation/json_annotation.dart';

part 'paywall_localization.g.dart';

@JsonSerializable()
class PaywallLocalization {
  PaywallLocalization({
    this.id,
    this.rtl,
    this.strings,
  });
  final String? id;
  final bool? rtl;
  final List<PaywallLocalizationString>? strings;
  factory PaywallLocalization.fromJson(Map<String, dynamic> json) =>
      _$PaywallLocalizationFromJson(json);
  Map<String, dynamic> toJson() => _$PaywallLocalizationToJson(this);
}

@JsonSerializable()
class PaywallLocalizationString {
  PaywallLocalizationString({
    this.id,
    this.value,
  });
  final String? id;
  final dynamic value;
  factory PaywallLocalizationString.fromJson(Map<String, dynamic> json) =>
      _$PaywallLocalizationStringFromJson(json);
  Map<String, dynamic> toJson() => _$PaywallLocalizationStringToJson(this);
}
