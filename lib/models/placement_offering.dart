import 'package:json_annotation/json_annotation.dart';

part 'placement_offering.g.dart';

@JsonSerializable()
class PlacementOffering {
  PlacementOffering({
    this.offering_identifier,
    this.placement_identifier,
  });

  final String? placement_identifier;
  final String? offering_identifier;

  factory PlacementOffering.fromJson(Map<String, dynamic> json) =>
      _$PlacementOfferingFromJson(json);
  Map<String, dynamic> toJson() => _$PlacementOfferingToJson(this);
}
