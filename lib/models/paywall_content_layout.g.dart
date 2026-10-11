// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'paywall_content_layout.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

PaywallContentLayout _$PaywallContentLayoutFromJson(
        Map<String, dynamic> json) =>
    PaywallContentLayout(
      align: json['align'] as String?,
      type: json['type'] as String?,
      padding: (json['padding'] as List<dynamic>?)
          ?.map((e) => (e as num).toInt())
          .toList(),
      spacing: json['spacing'] as String?,
      background: json['background'] as String?,
      border: json['border'] as String?,
      cornerRadius: (json['cornerRadius'] as List<dynamic>?)
          ?.map((e) => (e as num).toInt())
          .toList(),
      borderThickness: json['borderThickness'] as String?,
      offset: json['offset'] as String?,
    );

Map<String, dynamic> _$PaywallContentLayoutToJson(
        PaywallContentLayout instance) =>
    <String, dynamic>{
      'align': instance.align,
      'type': instance.type,
      'padding': instance.padding,
      'spacing': instance.spacing,
      'background': instance.background,
      'border': instance.border,
      'cornerRadius': instance.cornerRadius,
      'borderThickness': instance.borderThickness,
      'offset': instance.offset,
    };
