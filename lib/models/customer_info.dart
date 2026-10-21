import 'package:inappify_sdk/models/entitlement_infos.dart';
import 'package:inappify_sdk/models/attribute.dart';
import 'package:inappify_sdk/models/entitlement_model.dart';
import 'package:inappify_sdk/models/transaction_model.dart';
import 'package:json_annotation/json_annotation.dart';

part 'customer_info.g.dart';

@JsonSerializable()
class CustomerInfo {
  CustomerInfo({
    this.originalAppUserId,
    this.firstSeen,
    this.requestDate,
    List<EntitlementModel>? entitlements,
    int? entitlementEvaluationTimeMillis,
    this.transactions,
    this.hasUsedTrial,
    this.latestExpirationDate,
    this.attributes,
  }) : entitlements = InappifyEntitlementInfos(
         entitlements ?? const [],
         evaluationTimeMillis: entitlementEvaluationTimeMillis,
       );

  final String? originalAppUserId;
  final String? firstSeen;
  final String? requestDate;
  final String? latestExpirationDate;
  final bool? hasUsedTrial;
  final InappifyEntitlementInfos entitlements;
  final List<TransactionModel>? transactions;
  List<Attribute>? attributes;

  factory CustomerInfo.fromJson(Map<String, dynamic> json) =>
      _$CustomerInfoFromJson(json);
  Map<String, dynamic> toJson() => _$CustomerInfoToJson(this);
}
