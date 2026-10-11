// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'paywall_text.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

PaywallText _$PaywallTextFromJson(Map<String, dynamic> json) => PaywallText(
      defaultText: json['default'] == null
          ? null
          : TextModel.fromJson(json['default'] as Map<String, dynamic>),
      freeTrial: json['freeTrial'] == null
          ? null
          : TextModel.fromJson(json['freeTrial'] as Map<String, dynamic>),
      caption: json['caption'] as String?,
      title: json['title'] as String?,
    );

Map<String, dynamic> _$PaywallTextToJson(PaywallText instance) =>
    <String, dynamic>{
      'default': instance.defaultText,
      'freeTrial': instance.freeTrial,
      'title': instance.title,
      'caption': instance.caption,
    };
