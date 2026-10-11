import 'package:json_annotation/json_annotation.dart';

part 'entitlement_model.g.dart';

@JsonSerializable()
class EntitlementModel {

  EntitlementModel({
    this.expirationDate,
    this.identifier,
    this.isActive,
    this.isSandbox,
    this.ownershipType,
    this.periodType,
    this.purchaseDate,
    this.entitlementType,
    this.purchaseStoreRefHash,
    this.purchaseStoreTime,
  });

  final String? identifier;
  @JsonKey(name: 'is_active')
  final bool? isActive;
  @JsonKey(name: 'is_sandbox')
  final bool? isSandbox;
  @JsonKey(name: 'period_type')
  final String? periodType;
  @JsonKey(name: 'purchase_date')
  final String? purchaseDate;
  // final String amountVariance;
  @JsonKey(name: 'expiration_date')
  final String? expirationDate;
  @JsonKey(name: 'ownership_type')
  final String? ownershipType;
  @JsonKey(name: 'entitlement_type')
  final String? entitlementType;

  @JsonKey(name: 'purchase_store_ref_hash')
  final String? purchaseStoreRefHash;
  @JsonKey(name: 'purchase_store_time')
  final int? purchaseStoreTime;


  factory EntitlementModel.fromJson(Map<String, dynamic> json) =>
      _$EntitlementModelFromJson(json);
  Map<String, dynamic> toJson() => _$EntitlementModelToJson(this);
}
