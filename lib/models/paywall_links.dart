import 'package:json_annotation/json_annotation.dart';

part 'paywall_links.g.dart';

@JsonSerializable()
class PaywallLinks {
  PaywallLinks({
    this.login,
    this.terms,
    this.privacy,
    this.restore,
  });

  final PaywallLinkItem? login;
  final PaywallLinkItem? terms;
  final PaywallLinkItem? privacy;
  final PaywallLinkItem? restore;

  factory PaywallLinks.fromJson(Map<String, dynamic> json) =>
      _$PaywallLinksFromJson(json);
  Map<String, dynamic> toJson() => _$PaywallLinksToJson(this);
}

@JsonSerializable()
class PaywallLinkItem {
  PaywallLinkItem({
    this.visible,
    this.stringId,
    this.urlId,
  });

  final bool? visible;
  final String? stringId;
  final String? urlId;

  factory PaywallLinkItem.fromJson(Map<String, dynamic> json) =>
      _$PaywallLinkItemFromJson(json);
  Map<String, dynamic> toJson() => _$PaywallLinkItemToJson(this);
}
