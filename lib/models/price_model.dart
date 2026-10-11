import 'package:json_annotation/json_annotation.dart';

part 'price_model.g.dart';

@JsonSerializable()
class PriceModel {
  final int? id;
  @JsonKey(name: 'app_product_id')
  final int? appProductId;
  final String? currency;
  final num? amount;
  final num? originalAmount;
  final num? discountAmount;
  final int? price;
  @JsonKey(name: 'created_at')
  final String? createdAt;
  @JsonKey(name: 'updated_at')
  final String? updatedAt;
  final int? originPrice;

  PriceModel({
    this.id,
    this.appProductId,
    this.currency,
    this.amount,
    this.originalAmount,
    this.discountAmount,
    this.price,
    this.createdAt,
    this.updatedAt,
    this.originPrice,
  });

  factory PriceModel.fromJson(Map<String, dynamic> json) =>
      _$PriceModelFromJson(json);
  Map<String, dynamic> toJson() => _$PriceModelToJson(this);
}
