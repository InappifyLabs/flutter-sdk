import 'package:inappify_sdk/models/purchase_link.dart';
import 'package:inappify_sdk/models/offering_model.dart';
import 'package:json_annotation/json_annotation.dart';

part 'validate_discount_code_data.g.dart';

@JsonSerializable()
class ValidateDiscountCodeData {
  ValidateDiscountCodeData({
    this.isValid,
    this.errorCode,
    this.code,
    this.discountId,
    this.discountCodeId,
    this.percent,
    this.message,
    this.paymentLinks,
    this.offering,
  });

  @JsonKey(name: 'is_valid')
  final bool? isValid;
  @JsonKey(name: 'error_code')
  final int? errorCode;
  final String? code;
  @JsonKey(name: 'discount_id')
  final int? discountId;
  @JsonKey(name: 'discount_code_id')
  final int? discountCodeId;
  final int? percent;
  final String? message;
  @JsonKey(name: 'payment_links')
  final List<PurchaseLink>? paymentLinks;

  /// Server-priced offering returned by Web discount validation.
  final OfferingModel? offering;

  factory ValidateDiscountCodeData.fromJson(Map<String, dynamic> json) =>
      _$ValidateDiscountCodeDataFromJson(json);
  Map<String, dynamic> toJson() => _$ValidateDiscountCodeDataToJson(this);
}
