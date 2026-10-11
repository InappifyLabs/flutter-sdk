// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'offering_model.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

OfferingModel _$OfferingModelFromJson(Map<String, dynamic> json) {
  try {
    return OfferingModel(
      identifier: json['identifier'] as String?,
      isDefault: json['isDefault'] as bool?,
      serverDescription: json['serverDescription'] as String?,
      trialDays: (json['trialDays'] as num?)?.toInt(),
      metadata: json['metadata'],
      packages: (json['packages'] as List<dynamic>?)
          ?.map((e) => PackageModel.fromJson(e as Map<String, dynamic>))
          .toList(),
      paywall: json['paywall'] == null
          ? null
          : Paywall.fromJson(json['paywall'] as Map<String, dynamic>),
    );
  } catch (_) {
    return OfferingModel();
  }
}

Map<String, dynamic> _$OfferingModelToJson(OfferingModel instance) =>
    <String, dynamic>{
      'identifier': instance.identifier,
      'isDefault': instance.isDefault,
      'serverDescription': instance.serverDescription,
      'trialDays': instance.trialDays,
      'metadata': instance.metadata,
      'packages': instance.packages,
      'paywall': instance.paywall,
    };
