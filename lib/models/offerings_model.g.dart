// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'offerings_model.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

OfferingsModel _$OfferingsModelFromJson(Map<String, dynamic> json) =>
    OfferingsModel(
      offerings: (json['offerings'] as List<dynamic>?)
          ?.map((e) => OfferingModel.fromJson(e as Map<String, dynamic>))
          .toList(),
      rules: (json['rules'] as List<dynamic>?)
          ?.map((e) => Rule.fromJson(e as Map<String, dynamic>))
          .toList(),
      forceVersion: (json['forceVersion'] as num?)?.toInt(),
      fetchedAt: json['fetchedAt'] as String?,
      currentOfferingIdentifier: json['currentOffering'] as String?,
      placements: (json['placements'] as Map<String, dynamic>?)?.map(
        (k, e) => MapEntry(k, e as String?),
      ),
      usesServerTargeting: json['usesServerTargeting'] as bool? ?? false,
    );

Map<String, dynamic> _$OfferingsModelToJson(OfferingsModel instance) =>
    <String, dynamic>{
      'offerings': instance.offerings,
      'rules': instance.rules,
      'currentOffering': ?instance.currentOfferingIdentifier,
      'placements': ?instance.placements,
      'usesServerTargeting': instance.usesServerTargeting,
      'forceVersion': instance.forceVersion,
      'fetchedAt': instance.fetchedAt,
    };
