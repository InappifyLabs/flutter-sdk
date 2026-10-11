// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'rule.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

Rule _$RuleFromJson(Map<String, dynamic> json) => Rule(
      default_offering: json['default_offering'] as String?,
      sort: (json['sort'] as num?)?.toInt(),
      conditions: (json['conditions'] as List<dynamic>?)
          ?.map((e) => Condition.fromJson(e as Map<String, dynamic>))
          .toList(),
      placements: json['placements'] == null
          ? null
          : Placement.fromJson(json['placements'] as Map<String, dynamic>),
    );

Map<String, dynamic> _$RuleToJson(Rule instance) => <String, dynamic>{
      'default_offering': instance.default_offering,
      'sort': instance.sort,
      'conditions': instance.conditions,
      'placements': instance.placements,
    };
