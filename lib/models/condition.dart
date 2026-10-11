

import 'package:json_annotation/json_annotation.dart';

part 'condition.g.dart';

@JsonSerializable()
class Condition {

  Condition({
    this.id,
    this.target_id,
    this.context,
    this.field,
    this.operator,
    this.value,
  });

  final int? id;
  final int? target_id;
  final String? context;
  final String? field;
  final String? operator;
  final String? value;

  factory Condition.fromJson(Map<String, dynamic> json) => _$ConditionFromJson(json);
  Map<String, dynamic> toJson() => _$ConditionToJson(this);

}
