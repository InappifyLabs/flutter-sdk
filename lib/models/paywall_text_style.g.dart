// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'paywall_text_style.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

PaywallTextStyle _$PaywallTextStyleFromJson(Map<String, dynamic> json) =>
    PaywallTextStyle(
      color: json['color'] as String?,
      colorId: json['colorId'] as String?,
      fontId: json['fontId'] as String?,
      text: json['text'] == null
          ? null
          : PaywallTextStyle.fromJson(json['text'] as Map<String, dynamic>),
      text1: json['text1'] == null
          ? null
          : PaywallTextStyle.fromJson(json['text1'] as Map<String, dynamic>),
      text2: json['text2'] == null
          ? null
          : PaywallTextStyle.fromJson(json['text2'] as Map<String, dynamic>),
      text3: json['text3'] == null
          ? null
          : PaywallTextStyle.fromJson(json['text3'] as Map<String, dynamic>),
      text4: json['text4'] == null
          ? null
          : PaywallTextStyle.fromJson(json['text4'] as Map<String, dynamic>),
      title: json['title'] == null
          ? null
          : PaywallTextStyle.fromJson(json['title'] as Map<String, dynamic>),
      caption: json['caption'] == null
          ? null
          : PaywallTextStyle.fromJson(json['caption'] as Map<String, dynamic>),
    );

Map<String, dynamic> _$PaywallTextStyleToJson(PaywallTextStyle instance) =>
    <String, dynamic>{
      'color': instance.color,
      'colorId': instance.colorId,
      'fontId': instance.fontId,
      'text': instance.text,
      'text1': instance.text1,
      'text2': instance.text2,
      'text3': instance.text3,
      'text4': instance.text4,
      'title': instance.title,
      'caption': instance.caption,
    };
