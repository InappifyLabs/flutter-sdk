// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'condition.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

Condition _$ConditionFromJson(Map<String, dynamic> json) => Condition(
      id: (json['id'] as num?)?.toInt(),
      target_id: (json['target_id'] as num?)?.toInt(),
      context: json['context'] as String?,
      field: json['field'] as String?,
      operator: json['operator'] as String?,
      value: json['value'] as String?,
    );

Map<String, dynamic> _$ConditionToJson(Condition instance) => <String, dynamic>{
      'id': instance.id,
      'target_id': instance.target_id,
      'context': instance.context,
      'field': instance.field,
      'operator': instance.operator,
      'value': instance.value,
    };
