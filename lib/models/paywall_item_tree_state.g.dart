// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'paywall_item_tree_state.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

PaywallItemTreeState _$PaywallItemTreeStateFromJson(
        Map<String, dynamic> json) =>
    PaywallItemTreeState(
      id: json['id'] as String?,
      icon: json['icon'] as String?,
      type: json['type'] as String?,
      depth: (json['depth'] as num?)?.toInt(),
      label: json['label'] as String?,
      children: (json['children'] as List<dynamic>?)
          ?.map((e) => PaywallItemTreeState.fromJson(e as Map<String, dynamic>))
          .toList(),
      parentId: json['parentId'] as String?,
      haveChild: json['haveChild'] as bool?,
      sortOrder: (json['sortOrder'] as num?)?.toInt(),
    );

Map<String, dynamic> _$PaywallItemTreeStateToJson(
        PaywallItemTreeState instance) =>
    <String, dynamic>{
      'id': instance.id,
      'icon': instance.icon,
      'type': instance.type,
      'depth': instance.depth,
      'label': instance.label,
      'children': instance.children,
      'parentId': instance.parentId,
      'haveChild': instance.haveChild,
      'sortOrder': instance.sortOrder,
    };
