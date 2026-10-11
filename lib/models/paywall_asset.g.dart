// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'paywall_asset.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

PaywallAsset _$PaywallAssetFromJson(Map<String, dynamic> json) => PaywallAsset(
      id: json['id'] as String?,
      type: json['type'] as String?,
      value: json['value'] as String?,
      opacity: (json['opacity'] as num?)?.toDouble(),
      url: json['url'] as String?,
      name: json['name'] as String?,
      size: json['size'] as String?,
    );

Map<String, dynamic> _$PaywallAssetToJson(PaywallAsset instance) =>
    <String, dynamic>{
      'id': instance.id,
      'type': instance.type,
      'value': instance.value,
      'opacity': instance.opacity,
      'url': instance.url,
      'name': instance.name,
      'size': instance.size,
    };
