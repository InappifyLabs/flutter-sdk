import 'package:inappify_sdk/models/store_product_model.dart';
import 'package:json_annotation/json_annotation.dart';

part 'package_model.g.dart';

@JsonSerializable()
class PackageModel {
  PackageModel({
    this.identifier,
    this.packageType,
    this.product,
    this.entitlement,
    this.name,
    this.discountPercent,
    this.description,
  });

  final String? identifier;
  final int? packageType;
  final String? description;
  final String? entitlement;
  final String? name;
  final int? discountPercent;
  final StoreProductModel? product;

  factory PackageModel.fromJson(Map<String, dynamic> json) =>
      _$PackageModelFromJson(json);
  Map<String, dynamic> toJson() => _$PackageModelToJson(this);
}
