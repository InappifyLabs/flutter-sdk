import 'package:inappify_sdk/models/pivot.dart';
import 'package:inappify_sdk/models/price_model.dart';
import 'package:json_annotation/json_annotation.dart';

part 'offering_packages_product.g.dart';

@JsonSerializable()
class OfferingPackagesProduct {
  OfferingPackagesProduct({
    this.description,
    this.id,
    this.identifier_key,
    this.name,
    this.pivot,
    this.type,
    this.prices,
  });

  final int? id;
  final String? identifier_key;

  final int? type;
  final String? name;
  final String? description;
  final Pivot? pivot;
  final List<PriceModel>? prices;

  factory OfferingPackagesProduct.fromJson(Map<String, dynamic> json) =>
      _$OfferingPackagesProductFromJson(json);
  Map<String, dynamic> toJson() => _$OfferingPackagesProductToJson(this);
}
