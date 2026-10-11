import 'package:json_annotation/json_annotation.dart';

part 'purchase_link.g.dart';

@JsonSerializable()
class PurchaseLink {
  final String offering;
  final String url;

  PurchaseLink({required this.offering, required this.url});

  factory PurchaseLink.fromJson(Map<String, dynamic> json) => _$PurchaseLinkFromJson(json);
  Map<String, dynamic> toJson() => _$PurchaseLinkToJson(this);
}
