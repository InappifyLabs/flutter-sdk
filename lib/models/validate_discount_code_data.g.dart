// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'validate_discount_code_data.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

ValidateDiscountCodeData _$ValidateDiscountCodeDataFromJson(
  Map<String, dynamic> json,
) => ValidateDiscountCodeData(
  isValid: json['is_valid'] as bool?,
  errorCode: (json['error_code'] as num?)?.toInt(),
  code: json['code'] as String?,
  discountId: (json['discount_id'] as num?)?.toInt(),
  discountCodeId: (json['discount_code_id'] as num?)?.toInt(),
  percent: (json['percent'] as num?)?.toInt(),
  message: json['message'] as String?,
  paymentLinks: (json['payment_links'] as List<dynamic>?)
      ?.map((e) => PurchaseLink.fromJson(e as Map<String, dynamic>))
      .toList(),
  offering: json['offering'] == null
      ? null
      : OfferingModel.fromJson(json['offering'] as Map<String, dynamic>),
);

Map<String, dynamic> _$ValidateDiscountCodeDataToJson(
  ValidateDiscountCodeData instance,
) => <String, dynamic>{
  'is_valid': instance.isValid,
  'error_code': instance.errorCode,
  'code': instance.code,
  'discount_id': instance.discountId,
  'discount_code_id': instance.discountCodeId,
  'percent': instance.percent,
  'message': instance.message,
  'payment_links': instance.paymentLinks,
  'offering': instance.offering,
};
