// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'placement_offering.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

PlacementOffering _$PlacementOfferingFromJson(Map<String, dynamic> json) =>
    PlacementOffering(
      offering_identifier: json['offering_identifier'] as String?,
      placement_identifier: json['placement_identifier'] as String?,
    );

Map<String, dynamic> _$PlacementOfferingToJson(PlacementOffering instance) =>
    <String, dynamic>{
      'placement_identifier': instance.placement_identifier,
      'offering_identifier': instance.offering_identifier,
    };
