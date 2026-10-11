// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'pivot.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

Pivot _$PivotFromJson(Map<String, dynamic> json) => Pivot(
      paywall_id: (json['paywall_id'] as num?)?.toInt(),
      description: json['description'] as String?,
      offering_package_id: (json['offering_package_id'] as num?)?.toInt(),
      app_product_id: (json['app_product_id'] as num?)?.toInt(),
    );

Map<String, dynamic> _$PivotToJson(Pivot instance) => <String, dynamic>{
      'paywall_id': instance.paywall_id,
      'offering_package_id': instance.offering_package_id,
      'description': instance.description,
      'app_product_id': instance.app_product_id,
    };
