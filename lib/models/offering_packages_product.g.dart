// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'offering_packages_product.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

OfferingPackagesProduct _$OfferingPackagesProductFromJson(
        Map<String, dynamic> json) =>
    OfferingPackagesProduct(
      description: json['description'] as String?,
      id: (json['id'] as num?)?.toInt(),
      identifier_key: json['identifier_key'] as String?,
      name: json['name'] as String?,
      pivot: json['pivot'] == null
          ? null
          : Pivot.fromJson(json['pivot'] as Map<String, dynamic>),
      type: (json['type'] as num?)?.toInt(),
      prices: (json['prices'] as List<dynamic>?)
          ?.map((e) => PriceModel.fromJson(e as Map<String, dynamic>))
          .toList(),
    );

Map<String, dynamic> _$OfferingPackagesProductToJson(
        OfferingPackagesProduct instance) =>
    <String, dynamic>{
      'id': instance.id,
      'identifier_key': instance.identifier_key,
      'type': instance.type,
      'name': instance.name,
      'description': instance.description,
      'pivot': instance.pivot,
      'prices': instance.prices,
    };
