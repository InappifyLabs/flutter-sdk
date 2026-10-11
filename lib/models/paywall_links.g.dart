// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'paywall_links.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

PaywallLinks _$PaywallLinksFromJson(Map<String, dynamic> json) => PaywallLinks(
      login: json['login'] == null
          ? null
          : PaywallLinkItem.fromJson(json['login'] as Map<String, dynamic>),
      terms: json['terms'] == null
          ? null
          : PaywallLinkItem.fromJson(json['terms'] as Map<String, dynamic>),
      privacy: json['privacy'] == null
          ? null
          : PaywallLinkItem.fromJson(json['privacy'] as Map<String, dynamic>),
      restore: json['restore'] == null
          ? null
          : PaywallLinkItem.fromJson(json['restore'] as Map<String, dynamic>),
    );

Map<String, dynamic> _$PaywallLinksToJson(PaywallLinks instance) =>
    <String, dynamic>{
      'login': instance.login,
      'terms': instance.terms,
      'privacy': instance.privacy,
      'restore': instance.restore,
    };

PaywallLinkItem _$PaywallLinkItemFromJson(Map<String, dynamic> json) =>
    PaywallLinkItem(
      visible: json['visible'] as bool?,
      stringId: json['stringId'] as String?,
      urlId: json['urlId'] as String?,
    );

Map<String, dynamic> _$PaywallLinkItemToJson(PaywallLinkItem instance) =>
    <String, dynamic>{
      'visible': instance.visible,
      'stringId': instance.stringId,
      'urlId': instance.urlId,
    };
