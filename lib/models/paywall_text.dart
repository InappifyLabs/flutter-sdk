//"text": {
//     "default": {
//         "primary": "purchase-button-text-default-primary",
//         "secondary": "purchase-button-text-default-secondary"
//     },
//     "freeTrial": {
//         "primary": "purchase-button-text-freeTrial-primary",
//         "secondary": "purchase-button-text-freeTrial-secondary"
//     }
// },

import 'package:inappify_sdk/models/text_model.dart';
import 'package:json_annotation/json_annotation.dart';

part 'paywall_text.g.dart';

@JsonSerializable()
class PaywallText {
  @JsonKey(name: 'default')
  final TextModel? defaultText;
  final TextModel? freeTrial;
  final String? title;
  final String? caption;

  PaywallText({this.defaultText, this.freeTrial, this.caption, this.title});

  factory PaywallText.fromJson(Map<String, dynamic> json) =>
      _$PaywallTextFromJson(json);
  Map<String, dynamic> toJson() => _$PaywallTextToJson(this);
}
