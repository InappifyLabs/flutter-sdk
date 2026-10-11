// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'packages_color.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

PackagesColor _$PackagesColorFromJson(Map<String, dynamic> json) =>
    PackagesColor(
      default_background_color: json['default_background_color'] as String?,
      default_border_color: json['default_border_color'] as String?,
      default_text_color: json['default_text_color'] as String?,
      selected_background_color: json['selected_background_color'] as String?,
      selected_border_color: json['selected_border_color'] as String?,
      selected_text_color: json['selected_text_color'] as String?,
    );

Map<String, dynamic> _$PackagesColorToJson(PackagesColor instance) =>
    <String, dynamic>{
      'default_text_color': instance.default_text_color,
      'selected_text_color': instance.selected_text_color,
      'default_border_color': instance.default_border_color,
      'selected_border_color': instance.selected_border_color,
      'default_background_color': instance.default_background_color,
      'selected_background_color': instance.selected_background_color,
    };
