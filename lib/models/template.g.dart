// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'template.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

Template _$TemplateFromJson(Map<String, dynamic> json) => Template(
      buttons: json['buttons'] == null
          ? null
          : Buttons.fromJson(json['buttons'] as Map<String, dynamic>),
      dark: json['dark'] == null
          ? null
          : Template.fromJson(json['dark'] as Map<String, dynamic>),
      icon: json['icon'] as String?,
      icon_name: json['icon_name'] as String?,
      packages: json['packages'] == null
          ? null
          : PackagesColor.fromJson(json['packages'] as Map<String, dynamic>),
      sub_title: json['sub_title'] as String?,
      text_color: json['text_color'] as String?,
      sub_text_color: json['sub_text_color'] as String?,
      title: json['title'] as String?,
      feature_border_color: json['feature_border_color'] as String?,
      background: json['background'] == null
          ? null
          : Background.fromJson(json['background'] as Map<String, dynamic>),
      features: (json['features'] as List<dynamic>?)
          ?.map((e) => Feature.fromJson(e as Map<String, dynamic>))
          .toList(),
    );

Map<String, dynamic> _$TemplateToJson(Template instance) => <String, dynamic>{
      'icon': instance.icon,
      'title': instance.title,
      'buttons': instance.buttons,
      'packages': instance.packages,
      'icon_name': instance.icon_name,
      'sub_title': instance.sub_title,
      'text_color': instance.text_color,
      'sub_text_color': instance.sub_text_color,
      'feature_border_color': instance.feature_border_color,
      'background': instance.background,
      'dark': instance.dark,
      'features': instance.features,
    };
