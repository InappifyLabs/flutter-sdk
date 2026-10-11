// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'paywall_action.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

PaywallAction _$PaywallActionFromJson(Map<String, dynamic> json) =>
    PaywallAction(
      id: json['id'] as String?,
      type: json['type'] as String?,
      enable: json['enable'] as bool?,
    );

Map<String, dynamic> _$PaywallActionToJson(PaywallAction instance) =>
    <String, dynamic>{
      'id': instance.id,
      'type': instance.type,
      'enable': instance.enable,
    };
