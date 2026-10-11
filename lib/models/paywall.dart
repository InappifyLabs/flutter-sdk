import 'package:json_annotation/json_annotation.dart';
import 'offering_packages.dart';
import 'paywall_element.dart';
import 'paywall_asset.dart';
import 'paywall_item_tree_state.dart';
import 'paywall_localization.dart';

part 'paywall.g.dart';

@JsonSerializable()
class Paywall {
  Paywall({
    this.id,
    this.currentLocale,
    this.state,
    this.templateType,
    this.elements,
    this.assets,
    this.itemsTreesState,
    this.localizations,
    this.createdAt,
    this.updatedAt,
    this.offeringPackages,
  });

  final int? id;
  @JsonKey(name: 'current_locale')
  final String? currentLocale;
  final int? state;
  @JsonKey(name: 'template_type')
  final int? templateType;
  final List<PaywallElement>? elements;
  final List<PaywallAsset>? assets;
  @JsonKey(name: 'items_trees_state')
  final List<PaywallItemTreeState>? itemsTreesState;
  final List<PaywallLocalization>? localizations;
  final String? createdAt;
  final String? updatedAt;
  @JsonKey(name: 'offering_packages')
  final List<OfferingPackages>? offeringPackages;

  factory Paywall.fromJson(Map<String, dynamic> json) =>
      _$PaywallFromJson(json);
  Map<String, dynamic> toJson() => _$PaywallToJson(this);
}
