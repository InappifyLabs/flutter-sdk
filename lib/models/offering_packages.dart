import 'package:inappify_sdk/models/offering_packages_product.dart';
import 'package:inappify_sdk/models/pivot.dart';
import 'package:json_annotation/json_annotation.dart';

part 'offering_packages.g.dart';

@JsonSerializable()
class OfferingPackages {
  OfferingPackages({
    this.id,
    this.description,
    this.discount_percent,
    this.duration,
    this.identifier_key,
    this.name,
    this.offering_id,
    this.pivot,
    this.products,
    this.sort,
    this.type,
  });

  final int? id;
  final int? offering_id;
  final String? identifier_key;
  final int? duration;
  final String? description;
  final String? name;
  final int? discount_percent;
  final int? type;
  final int? sort;
  final Pivot? pivot;
  final List<OfferingPackagesProduct>? products;

  factory OfferingPackages.fromJson(Map<String, dynamic> json) =>
      _$OfferingPackagesFromJson(json);
  Map<String, dynamic> toJson() => _$OfferingPackagesToJson(this);
}
