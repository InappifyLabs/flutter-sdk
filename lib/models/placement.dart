import 'package:inappify_sdk/models/placement_offering.dart';
import 'package:json_annotation/json_annotation.dart';

part 'placement.g.dart';

@JsonSerializable()
class Placement {
  Placement({
    this.fallback_offering_id,
    this.placement_offerings,
  });

  final String? fallback_offering_id;
  final List<PlacementOffering>? placement_offerings;

  factory Placement.fromJson(Map<String, dynamic> json) => _$PlacementFromJson(json);
  Map<String, dynamic> toJson() => _$PlacementToJson(this);
}
