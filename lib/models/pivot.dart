import 'package:json_annotation/json_annotation.dart';

part 'pivot.g.dart';

@JsonSerializable()
class Pivot {
  Pivot({
    this.paywall_id,
    this.description,
    this.offering_package_id,
    this.app_product_id,
  });

  final int? paywall_id;
  final int? offering_package_id;
  final String? description;
  final int? app_product_id;

  factory Pivot.fromJson(Map<String, dynamic> json) => _$PivotFromJson(json);
  Map<String, dynamic> toJson() => _$PivotToJson(this);
}
