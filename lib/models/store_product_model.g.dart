// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'store_product_model.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

StoreProductModel _$StoreProductModelFromJson(Map<String, dynamic> json) {
  try {
    return StoreProductModel(
      identifier: json['identifier'] as String?,
      name: json['name'] as String?,
      prices: json['prices'] != null
          ? (json['prices'] as List<dynamic>?)
              ?.map((e) => PriceModel.fromJson(e as Map<String, dynamic>))
              .toList()
          : (json['price'] as List<dynamic>?)
              ?.map((e) => PriceModel.fromJson(e as Map<String, dynamic>))
              .toList(),
      dollarPrice: (json['dollarPrice'] as num?)?.toDouble(),
      trialDays: (json['trialDays'] as num?)?.toInt(),
    );
  } catch (_) {
    return StoreProductModel();
  }
}

Map<String, dynamic> _$StoreProductModelToJson(StoreProductModel instance) =>
    <String, dynamic>{
      'identifier': instance.identifier,
      'name': instance.name,
      'price': instance.prices,
      'dollarPrice': instance.dollarPrice,
      'trialDays': instance.trialDays,
    };
