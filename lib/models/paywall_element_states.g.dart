// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'paywall_element_states.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

PaywallElementStates _$PaywallElementStatesFromJson(
        Map<String, dynamic> json) =>
    PaywallElementStates(
      defaultState: json['default'] == null
          ? null
          : PaywallElementState.fromJson(
              json['default'] as Map<String, dynamic>),
      selected: json['selected'] == null
          ? null
          : PaywallElementState.fromJson(
              json['selected'] as Map<String, dynamic>),
    );

Map<String, dynamic> _$PaywallElementStatesToJson(
        PaywallElementStates instance) =>
    <String, dynamic>{
      'default': instance.defaultState,
      'selected': instance.selected,
    };

PaywallElementState _$PaywallElementStateFromJson(Map<String, dynamic> json) =>
    PaywallElementState(
      textStyle: json['textStyle'] == null
          ? null
          : PaywallTextStyle.fromJson(
              json['textStyle'] as Map<String, dynamic>),
      containerStyle: json['containerStyle'] == null
          ? null
          : PaywallContainerStyle.fromJson(
              json['containerStyle'] as Map<String, dynamic>),
    );

Map<String, dynamic> _$PaywallElementStateToJson(
        PaywallElementState instance) =>
    <String, dynamic>{
      'textStyle': instance.textStyle,
      'containerStyle': instance.containerStyle,
    };

PaywallContainerStyle _$PaywallContainerStyleFromJson(
        Map<String, dynamic> json) =>
    PaywallContainerStyle(
      border: json['border'] as String?,
      background: json['background'] as String?,
      cornerRadius: (json['cornerRadius'] as List<dynamic>?)
          ?.map((e) => (e as num).toInt())
          .toList(),
      borderThickness: json['borderThickness'] as String?,
    );

Map<String, dynamic> _$PaywallContainerStyleToJson(
        PaywallContainerStyle instance) =>
    <String, dynamic>{
      'border': instance.border,
      'background': instance.background,
      'cornerRadius': instance.cornerRadius,
      'borderThickness': instance.borderThickness,
    };
