import 'package:json_annotation/json_annotation.dart';

part 'paywall_action.g.dart';

@JsonSerializable()
class PaywallAction {
  PaywallAction({
    this.id,
    this.type,
    this.enable,
  });
  final String? id;
  final String? type;
  final bool? enable;
  factory PaywallAction.fromJson(Map<String, dynamic> json) =>
      _$PaywallActionFromJson(json);
  Map<String, dynamic> toJson() => _$PaywallActionToJson(this);
}
