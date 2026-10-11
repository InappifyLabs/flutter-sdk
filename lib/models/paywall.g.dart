// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'paywall.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

Paywall _$PaywallFromJson(Map<String, dynamic> json) => Paywall(
      id: (json['id'] as num?)?.toInt(),
      currentLocale: json['current_locale'] as String?,
      state: (json['state'] as num?)?.toInt(),
      templateType: (json['template_type'] as num?)?.toInt(),
      elements: (json['elements'] as List<dynamic>?)
          ?.map((e) => PaywallElement.fromJson(e as Map<String, dynamic>))
          .toList(),
      assets: (json['assets'] as List<dynamic>?)
          ?.map((e) => PaywallAsset.fromJson(e as Map<String, dynamic>))
          .toList(),
      itemsTreesState: (json['items_trees_state'] as List<dynamic>?)
          ?.map((e) => PaywallItemTreeState.fromJson(e as Map<String, dynamic>))
          .toList(),
      localizations: (json['localizations'] as List<dynamic>?)
          ?.map((e) => PaywallLocalization.fromJson(e as Map<String, dynamic>))
          .toList(),
      createdAt: json['createdAt'] as String?,
      updatedAt: json['updatedAt'] as String?,
      offeringPackages: (json['offering_packages'] as List<dynamic>?)
          ?.map((e) => OfferingPackages.fromJson(e as Map<String, dynamic>))
          .toList(),
    );

Map<String, dynamic> _$PaywallToJson(Paywall instance) => <String, dynamic>{
      'id': instance.id,
      'current_locale': instance.currentLocale,
      'state': instance.state,
      'template_type': instance.templateType,
      'elements': instance.elements,
      'assets': instance.assets,
      'items_trees_state': instance.itemsTreesState,
      'localizations': instance.localizations,
      'createdAt': instance.createdAt,
      'updatedAt': instance.updatedAt,
      'offering_packages': instance.offeringPackages,
    };
