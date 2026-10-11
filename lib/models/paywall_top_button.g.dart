// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'paywall_top_button.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

PaywallTopButton _$PaywallTopButtonFromJson(Map<String, dynamic> json) =>
    PaywallTopButton(
      align: json['align'] as String?,
      style: json['style'] == null
          ? null
          : PaywallTopButtonStyle.fromJson(
              json['style'] as Map<String, dynamic>),
      action: json['action'] == null
          ? null
          : PaywallTopButtonAction.fromJson(
              json['action'] as Map<String, dynamic>),
      styleType: json['styleType'] as String?,
    );

Map<String, dynamic> _$PaywallTopButtonToJson(PaywallTopButton instance) =>
    <String, dynamic>{
      'align': instance.align,
      'style': instance.style?.toJson(),
      'action': instance.action?.toJson(),
      'styleType': instance.styleType,
    };

PaywallTopButtonStyle _$PaywallTopButtonStyleFromJson(
        Map<String, dynamic> json) =>
    PaywallTopButtonStyle(
      icon: json['icon'] == null
          ? null
          : PaywallTopButtonIcon.fromJson(json['icon'] as Map<String, dynamic>),
      border: json['border'] as String?,
      fontId: json['fontId'] as String?,
      hashSum: json['hashSum'] as String?,
      visible: json['visible'] as bool?,
      stringId: json['stringId'] as String?,
      thickness: (json['thickness'] as num?)?.toInt(),
      background: json['background'] as String?,
      cornerRadius: (json['cornerRadius'] as List<dynamic>?)
          ?.map((e) => (e as num).toInt())
          .toList(),
    );

Map<String, dynamic> _$PaywallTopButtonStyleToJson(
        PaywallTopButtonStyle instance) =>
    <String, dynamic>{
      'icon': instance.icon,
      'border': instance.border,
      'fontId': instance.fontId,
      'hashSum': instance.hashSum,
      'visible': instance.visible,
      'stringId': instance.stringId,
      'thickness': instance.thickness,
      'background': instance.background,
      'cornerRadius': instance.cornerRadius,
    };

PaywallTopButtonIcon _$PaywallTopButtonIconFromJson(
        Map<String, dynamic> json) =>
    PaywallTopButtonIcon(
      type: json['type'] as String?,
      color: json['color'] as String?,
    );

Map<String, dynamic> _$PaywallTopButtonIconToJson(
        PaywallTopButtonIcon instance) =>
    <String, dynamic>{
      'type': instance.type,
      'color': instance.color,
    };

PaywallTopButtonAction _$PaywallTopButtonActionFromJson(
        Map<String, dynamic> json) =>
    PaywallTopButtonAction(
      id: json['id'] as String?,
      type: json['type'] as String?,
    );

Map<String, dynamic> _$PaywallTopButtonActionToJson(
        PaywallTopButtonAction instance) =>
    <String, dynamic>{
      'id': instance.id,
      'type': instance.type,
    };
