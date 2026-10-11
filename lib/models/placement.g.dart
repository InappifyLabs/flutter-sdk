// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'placement.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

Placement _$PlacementFromJson(Map<String, dynamic> json) => Placement(
      fallback_offering_id: json['fallback_offering_id'] as String?,
      placement_offerings: (json['placement_offerings'] as List<dynamic>?)
          ?.map((e) => PlacementOffering.fromJson(e as Map<String, dynamic>))
          .toList(),
    );

Map<String, dynamic> _$PlacementToJson(Placement instance) => <String, dynamic>{
      'fallback_offering_id': instance.fallback_offering_id,
      'placement_offerings': instance.placement_offerings,
    };
