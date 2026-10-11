// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'transaction_model.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

TransactionModel _$TransactionModelFromJson(Map<String, dynamic> json) =>
    TransactionModel(
      number: json['number'] as String?,
      amount: (json['amount'] as num?)?.toInt(),
      isCryptoGate: json['isCryptoGate'] as bool?,
      packageName: json['packageName'] as String?,
      status: (json['status'] as num?)?.toInt(),
      trackingNumber: json['trackingNumber'] as String?,
      transactionDate: json['transactionDate'] as String?,
      storePurchaseRefId: json['storePurchaseRefId'] as String?,
      isTrial: json['isTrial'] as bool?,
    );

Map<String, dynamic> _$TransactionModelToJson(TransactionModel instance) =>
    <String, dynamic>{
      'number': instance.number,
      'status': instance.status,
      'amount': instance.amount,
      'transactionDate': instance.transactionDate,
      'trackingNumber': instance.trackingNumber,
      'isCryptoGate': instance.isCryptoGate,
      'packageName': instance.packageName,
      'storePurchaseRefId': instance.storePurchaseRefId,
      'isTrial': instance.isTrial,
    };
