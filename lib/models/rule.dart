import 'package:inappify_sdk/models/condition.dart';
import 'package:inappify_sdk/models/placement.dart';
import 'package:json_annotation/json_annotation.dart';

part 'rule.g.dart';

@JsonSerializable()
class Rule {
  Rule({
    this.default_offering,
    this.sort,
    this.conditions,
    this.placements,
  });

  final String? default_offering;
  final int? sort;
  final List<Condition>? conditions;
  final Placement? placements;

  factory Rule.fromJson(Map<String, dynamic> json) =>
      _$RuleFromJson(json);
  Map<String, dynamic> toJson() => _$RuleToJson(this);
}
