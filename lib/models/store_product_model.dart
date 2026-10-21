import 'package:inappify_sdk/models/mobile_v2.dart';
import 'package:inappify_sdk/models/price_model.dart';
import 'package:json_annotation/json_annotation.dart';

part 'store_product_model.g.dart';

@JsonSerializable()
class StoreProductModel {
  StoreProductModel({
    this.identifier,
    this.productType,
    this.name,
    this.prices,
    this.dollarPrice,
    this.trialDays,
  });

  final String? identifier;
  final InappifyProductType? productType;
  final String? name;
  final List<PriceModel>? prices;
  final double? dollarPrice;
  final int? trialDays;

  factory StoreProductModel.fromJson(Map<String, dynamic> json) =>
      _$StoreProductModelFromJson(json);
  Map<String, dynamic> toJson() => _$StoreProductModelToJson(this);
}
