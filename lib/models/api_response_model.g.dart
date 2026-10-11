// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'api_response_model.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

ApiResponseModel<T> _$ApiResponseModelFromJson<T>(
  Map<String, dynamic> json,
  T Function(Object? json) fromJsonT,
) =>
    ApiResponseModel<T>(
      status: json['status'] as bool?,
      data: _$nullableGenericFromJson(json['data'], fromJsonT),
      message: json['message'] as String?,
      token: json['token'] as String?,
      customerInfo: json['customerInfo'] == null
          ? null
          : CustomerInfo.fromJson(json['customerInfo'] as Map<String, dynamic>),
      storeInfo: json['storeInfo'] as String?,
      appId: (json['appId'] as num?)?.toInt(),
      forceVersion: (json['forceVersion'] as num?)?.toInt(),
      offerings: (json['offerings'] as List<dynamic>?)
          ?.map((e) => OfferingModel.fromJson(e as Map<String, dynamic>))
          .toList(),
      rules: (json['rules'] as List<dynamic>?)
          ?.map((e) => Rule.fromJson(e as Map<String, dynamic>))
          .toList(),
    );

Map<String, dynamic> _$ApiResponseModelToJson<T>(
  ApiResponseModel<T> instance,
  Object? Function(T value) toJsonT,
) =>
    <String, dynamic>{
      'status': instance.status,
      'data': _$nullableGenericToJson(instance.data, toJsonT),
      'message': instance.message,
      'token': instance.token,
      'customerInfo': instance.customerInfo,
      'storeInfo': instance.storeInfo,
      'appId': instance.appId,
      'forceVersion': instance.forceVersion,
      'offerings': instance.offerings,
      'rules': instance.rules,
    };

T? _$nullableGenericFromJson<T>(
  Object? input,
  T Function(Object? json) fromJson,
) =>
    input == null ? null : fromJson(input);

Object? _$nullableGenericToJson<T>(
  T? input,
  Object? Function(T value) toJson,
) =>
    input == null ? null : toJson(input);
