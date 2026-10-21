import 'package:inappify_sdk/models/store_product_model.dart';
import 'package:json_annotation/json_annotation.dart';

part 'package_model.g.dart';

@JsonSerializable()
class PackageModel {
  PackageModel({
    this.identifier,
    this.offeringIdentifier,
    this.packageType,
    this.product,
    this.entitlement,
    this.name,
    this.discountPercent,
    this.description,
  });

  final String? identifier;
  final String? offeringIdentifier;
  final int? packageType;
  final String? description;
  final String? entitlement;
  final String? name;
  final int? discountPercent;
  final StoreProductModel? product;

  PackageModel withOfferingIdentifier(String? parent) => PackageModel(
    identifier: identifier,
    offeringIdentifier: parent,
    packageType: packageType,
    product: product,
    entitlement: entitlement,
    name: name,
    discountPercent: discountPercent,
    description: description,
  );

  factory PackageModel.fromJson(Map<String, dynamic> json) =>
      _$PackageModelFromJson(json);
  Map<String, dynamic> toJson() => _$PackageModelToJson(this);
}
