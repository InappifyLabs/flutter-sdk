// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'offering_packages.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

OfferingPackages _$OfferingPackagesFromJson(Map<String, dynamic> json) =>
    OfferingPackages(
      id: (json['id'] as num?)?.toInt(),
      description: json['description'] as String?,
      discount_percent: (json['discount_percent'] as num?)?.toInt(),
      duration: (json['duration'] as num?)?.toInt(),
      identifier_key: json['identifier_key'] as String?,
      name: json['name'] as String?,
      offering_id: (json['offering_id'] as num?)?.toInt(),
      pivot: json['pivot'] == null
          ? null
          : Pivot.fromJson(json['pivot'] as Map<String, dynamic>),
      products: (json['products'] as List<dynamic>?)
          ?.map((e) =>
              OfferingPackagesProduct.fromJson(e as Map<String, dynamic>))
          .toList(),
      sort: (json['sort'] as num?)?.toInt(),
      type: (json['type'] as num?)?.toInt(),
    );

Map<String, dynamic> _$OfferingPackagesToJson(OfferingPackages instance) =>
    <String, dynamic>{
      'id': instance.id,
      'offering_id': instance.offering_id,
      'identifier_key': instance.identifier_key,
      'duration': instance.duration,
      'description': instance.description,
      'name': instance.name,
      'discount_percent': instance.discount_percent,
      'type': instance.type,
      'sort': instance.sort,
      'pivot': instance.pivot,
      'products': instance.products,
    };
