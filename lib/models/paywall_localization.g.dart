// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'paywall_localization.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

PaywallLocalization _$PaywallLocalizationFromJson(Map<String, dynamic> json) =>
    PaywallLocalization(
      id: json['id'] as String?,
      rtl: json['rtl'] as bool?,
      strings: (json['strings'] as List<dynamic>?)
          ?.map((e) =>
              PaywallLocalizationString.fromJson(e as Map<String, dynamic>))
          .toList(),
    );

Map<String, dynamic> _$PaywallLocalizationToJson(
        PaywallLocalization instance) =>
    <String, dynamic>{
      'id': instance.id,
      'rtl': instance.rtl,
      'strings': instance.strings,
    };

PaywallLocalizationString _$PaywallLocalizationStringFromJson(
        Map<String, dynamic> json) =>
    PaywallLocalizationString(
      id: json['id'] as String?,
      value: json['value'],
    );

Map<String, dynamic> _$PaywallLocalizationStringToJson(
        PaywallLocalizationString instance) =>
    <String, dynamic>{
      'id': instance.id,
      'value': instance.value,
    };
