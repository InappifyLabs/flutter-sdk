import 'package:inappify_sdk/models/customer_info.dart';
import 'package:inappify_sdk/models/offering_model.dart';
import 'package:inappify_sdk/models/rule.dart';
import 'package:json_annotation/json_annotation.dart';

part 'api_response_model.g.dart';

@JsonSerializable(genericArgumentFactories: true)
class ApiResponseModel<T> {
  ApiResponseModel({
    this.status,
    this.data,
    this.message,
    this.token,
    this.customerInfo,
    this.storeInfo,
    this.appId,
    this.forceVersion,
    this.offerings,
    this.rules,
  });

  final bool? status;
  final T? data;
  final String? message;
  final String? token;
  final CustomerInfo? customerInfo;
  final String? storeInfo;
  final int? appId;
  final int? forceVersion;
  final List<OfferingModel>? offerings;
  final List<Rule>? rules;

  factory ApiResponseModel.fromJson(
          Map<String, dynamic> json, T Function(dynamic) fromJsonT) =>
      _$ApiResponseModelFromJson<T>(json, fromJsonT);

  Map<String, dynamic> toJson(Object? Function(T)? toJsonT) =>
      _$ApiResponseModelToJson(this, toJsonT!);
}
