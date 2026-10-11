import 'package:json_annotation/json_annotation.dart';

part 'paywall_item_tree_state.g.dart';

@JsonSerializable()
class PaywallItemTreeState {
  PaywallItemTreeState({
    this.id,
    this.icon,
    this.type,
    this.depth,
    this.label,
    this.children,
    this.parentId,
    this.haveChild,
    this.sortOrder,
  });
  final String? id;
  final String? icon;
  final String? type;
  final int? depth;
  final String? label;
  final List<PaywallItemTreeState>? children;
  final String? parentId;
  final bool? haveChild;
  final int? sortOrder;
  factory PaywallItemTreeState.fromJson(Map<String, dynamic> json) =>
      _$PaywallItemTreeStateFromJson(json);
  Map<String, dynamic> toJson() => _$PaywallItemTreeStateToJson(this);
}
