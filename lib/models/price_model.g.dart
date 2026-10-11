// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'price_model.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

PriceModel _$PriceModelFromJson(Map<String, dynamic> json) {
  return PriceModel(
    id: (json['id'] as num?)?.toInt(),
    appProductId: (json['app_product_id'] as num?)?.toInt(),
    currency: json['currency'] as String?,
    amount: json['amount'] as num?,
    originalAmount: (json['originalAmount'] ?? json['originPrice']) as num?,
    discountAmount: json['discountAmount'] as num?,
    price: ((json['price'] ?? json['amount']) as num?)?.toInt(),
    createdAt: json['created_at'] as String?,
    updatedAt: json['updated_at'] as String?,
    originPrice: ((json['originPrice'] ?? json['originalAmount']) as num?)
        ?.toInt(),
  );
}

Map<String, dynamic> _$PriceModelToJson(PriceModel instance) =>
    <String, dynamic>{
      'id': instance.id,
      'app_product_id': instance.appProductId,
      'currency': instance.currency,
      'amount': instance.amount,
      'originalAmount': instance.originalAmount,
      'discountAmount': instance.discountAmount,
      'price': instance.price,
      'created_at': instance.createdAt,
      'updated_at': instance.updatedAt,
      'originPrice': instance.originPrice,
    };
