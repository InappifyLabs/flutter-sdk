// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'entitlement_model.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

EntitlementModel _$EntitlementModelFromJson(Map<String, dynamic> json) =>
    EntitlementModel(
      expirationDate: json['expiration_date'] as String?,
      identifier: json['identifier'] as String?,
      isActive: json['is_active'] as bool?,
      isSandbox: json['is_sandbox'] as bool?,
      ownershipType: json['ownership_type'] as String?,
      periodType: json['period_type'] as String?,
      purchaseDate: json['purchase_date'] as String?,
      entitlementType: json['entitlement_type'] as String?,
      purchaseStoreRefHash: json['purchase_store_ref_hash'] as String?,
      purchaseStoreTime: (json['purchase_store_time'] as num?)?.toInt(),
    );

Map<String, dynamic> _$EntitlementModelToJson(EntitlementModel instance) =>
    <String, dynamic>{
      'identifier': instance.identifier,
      'is_active': instance.isActive,
      'is_sandbox': instance.isSandbox,
      'period_type': instance.periodType,
      'purchase_date': instance.purchaseDate,
      'expiration_date': instance.expirationDate,
      'ownership_type': instance.ownershipType,
      'entitlement_type': instance.entitlementType,
      'purchase_store_ref_hash': instance.purchaseStoreRefHash,
      'purchase_store_time': instance.purchaseStoreTime,
    };
