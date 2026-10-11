// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'purchase_result.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

PurchaseResult _$PurchaseResultFromJson(Map<String, dynamic> json) =>
    PurchaseResult(
      url: json['url'] as String?,
      purchaseStatus: $enumDecodeNullable(
        _$PurchaseStatusEnumMap,
        json['purchaseStatus'],
      ),
      checkoutId: json['checkoutId'] as String?,
      checkoutStatus: json['checkoutStatus'] as String?,
      nextActionType: json['nextActionType'] as String?,
      mobile: PurchaseResult._mobileFromJson(
        json['mobile'] as Map<String, dynamic>?,
      ),
    );

Map<String, dynamic> _$PurchaseResultToJson(PurchaseResult instance) =>
    <String, dynamic>{
      'url': instance.url,
      'purchaseStatus': _$PurchaseStatusEnumMap[instance.purchaseStatus],
      'checkoutId': instance.checkoutId,
      'checkoutStatus': instance.checkoutStatus,
      'nextActionType': instance.nextActionType,
      'mobile': ?PurchaseResult._mobileToJson(instance.mobile),
    };

const _$PurchaseStatusEnumMap = {
  PurchaseStatus.DONE: 'DONE',
  PurchaseStatus.NEEDTOPAY: 'NEEDTOPAY',
};
