// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'customer_info.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

CustomerInfo _$CustomerInfoFromJson(Map<String, dynamic> json) => CustomerInfo(
      originalAppUserId: json['originalAppUserId'] as String?,
      firstSeen: json['firstSeen'] as String?,
      entitlementEvaluationTimeMillis: (json['entitlementEvaluationTimeMillis'] as num?)?.toInt(),
      requestDate: json['requestDate'] as String?,
      entitlements: (json['entitlements'] as List<dynamic>?)
          ?.map((e) => EntitlementModel.fromJson(e as Map<String, dynamic>))
          .toList(),
      transactions: (json['transactions'] as List<dynamic>?)
          ?.map((e) => TransactionModel.fromJson(e as Map<String, dynamic>))
          .toList(),
      latestExpirationDate: json['latestExpirationDate'] as String?,
      attributes: (json['attributes'] as List<dynamic>?)
          ?.map((e) => Attribute.fromJson(e as Map<String, dynamic>))
          .toList(),
      hasUsedTrial: json['hasUsedTrial'] as bool?,
    );

Map<String, dynamic> _$CustomerInfoToJson(CustomerInfo instance) =>
    <String, dynamic>{
      'originalAppUserId': instance.originalAppUserId,
      'firstSeen': instance.firstSeen,
      'requestDate': instance.requestDate,
      'latestExpirationDate': instance.latestExpirationDate,
      'entitlements': instance.entitlements,
      'transactions': instance.transactions,
      'attributes': instance.attributes,
      'hasUsedTrial': instance.hasUsedTrial,
    };
