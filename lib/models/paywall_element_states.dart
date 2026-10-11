import 'package:json_annotation/json_annotation.dart';
import 'paywall_text_style.dart';

part 'paywall_element_states.g.dart';

@JsonSerializable()
class PaywallElementStates {
  PaywallElementStates({
    this.defaultState,
    this.selected,
  });

  @JsonKey(name: 'default')
  final PaywallElementState? defaultState;
  final PaywallElementState? selected;

  factory PaywallElementStates.fromJson(Map<String, dynamic> json) =>
      _$PaywallElementStatesFromJson(json);
  Map<String, dynamic> toJson() => _$PaywallElementStatesToJson(this);
}

@JsonSerializable()
class PaywallElementState {
  PaywallElementState({
    this.textStyle,
    this.containerStyle,
  });

  final PaywallTextStyle? textStyle;
  final PaywallContainerStyle? containerStyle;

  factory PaywallElementState.fromJson(Map<String, dynamic> json) =>
      _$PaywallElementStateFromJson(json);
  Map<String, dynamic> toJson() => _$PaywallElementStateToJson(this);
}

@JsonSerializable()
class PaywallContainerStyle {
  PaywallContainerStyle({
    this.border,
    this.background,
    this.cornerRadius,
    this.borderThickness,
  });

  final String? border;
  final String? background;
  final List<int>? cornerRadius;
  final String? borderThickness;

  factory PaywallContainerStyle.fromJson(Map<String, dynamic> json) =>
      _$PaywallContainerStyleFromJson(json);
  Map<String, dynamic> toJson() => _$PaywallContainerStyleToJson(this);
}
