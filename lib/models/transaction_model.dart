import 'package:json_annotation/json_annotation.dart';

part 'transaction_model.g.dart';

@JsonSerializable()
class TransactionModel {

  TransactionModel({
    this.number,
    this.amount,
    this.isCryptoGate,
    this.packageName,
    this.status,
    this.trackingNumber,
    this.transactionDate,
    this.storePurchaseRefId,
    this.isTrial,
  });

  final String? number;
  final int? status;
  final int? amount;
  final String? transactionDate;
  final String? trackingNumber;
  final bool? isCryptoGate;
  final String? packageName;
  final String? storePurchaseRefId;
  final bool? isTrial;


  factory TransactionModel.fromJson(Map<String, dynamic> json) =>
      _$TransactionModelFromJson(json);
  Map<String, dynamic> toJson() => _$TransactionModelToJson(this);

}
