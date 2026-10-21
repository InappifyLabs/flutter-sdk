// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'package_model.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

PackageModel _$PackageModelFromJson(Map<String, dynamic> json) {
  return PackageModel(
      identifier: json['identifier'] as String?,
      offeringIdentifier: json['offeringIdentifier'] as String?,
      packageType: (json['packageType'] as num?)?.toInt(),
      product: json['product'] == null
          ? null
          : StoreProductModel.fromJson(json['product'] as Map<String, dynamic>),
      entitlement: json['entitlement'] as String?,
      name: json['name'] as String?,
      discountPercent: (json['discountPercent'] as num?)?.toInt(),
      description: json['description'] as String?,
    );
}

Map<String, dynamic> _$PackageModelToJson(PackageModel instance) =>
    <String, dynamic>{
      'identifier': instance.identifier,
      'offeringIdentifier': instance.offeringIdentifier,
      'packageType': instance.packageType,
      'description': instance.description,
      'entitlement': instance.entitlement,
      'name': instance.name,
      'discountPercent': instance.discountPercent,
      'product': instance.product?.toJson(),
    };
