// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'paywall_badge_style.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

PaywallBadgeStyle _$PaywallBadgeStyleFromJson(Map<String, dynamic> json) =>
    PaywallBadgeStyle(
      visible: json['visible'] as bool?,
      background: json['background'] as String?,
      cornerRadius: (json['cornerRadius'] as List<dynamic>?)
          ?.map((e) => (e as num).toInt())
          .toList(),
      color: json['color'] as String?,
    );

Map<String, dynamic> _$PaywallBadgeStyleToJson(PaywallBadgeStyle instance) =>
    <String, dynamic>{
      'visible': instance.visible,
      'background': instance.background,
      'cornerRadius': instance.cornerRadius,
      'color': instance.color,
    };
