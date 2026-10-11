import 'package:inappify_sdk/models/enums/purchase_status.dart';
import 'package:inappify_sdk/models/mobile_v2.dart';
import 'package:json_annotation/json_annotation.dart';

part 'purchase_result.g.dart';

/// Backward-compatible purchase result exposed by the Flutter façade.
///
/// Native and legacy callers continue to use [url] and [purchaseStatus]. Web
/// checkout metadata is additive so applications can persist [checkoutId] and
/// later verify the authoritative state with `handlePaymentReturn`.
@JsonSerializable()
class PurchaseResult {
  /// Creates a purchase result.
  PurchaseResult({
    this.url,
    this.purchaseStatus,
    this.checkoutId,
    this.checkoutStatus,
    this.nextActionType,
    this.mobile,
  });

  /// Server-issued redirect URL, when payment must continue in a browser.
  final String? url;

  /// Legacy purchase status retained for existing host application call sites.
  final PurchaseStatus? purchaseStatus;

  /// Opaque Web checkout identifier used to verify payment return.
  final String? checkoutId;

  /// Provider-defined checkout state returned when the purchase starts.
  final String? checkoutStatus;

  /// Provider-defined next action, including the documented `redirect` type.
  final String? nextActionType;

  /// Native/Dart mobile workflow; DELIVERY_REQUIRED is not a completed grant.
  @JsonKey(
    includeIfNull: false,
    fromJson: _mobileFromJson,
    toJson: _mobileToJson,
  )
  final InappifyMobilePurchaseData? mobile;

  static InappifyMobilePurchaseData? _mobileFromJson(
    Map<String, dynamic>? value,
  ) => value == null ? null : InappifyMobilePurchaseData.fromMap(value);
  static Map<String, Object?>? _mobileToJson(
    InappifyMobilePurchaseData? value,
  ) => value?.toMap();

  factory PurchaseResult.fromJson(Map<String, dynamic> json) =>
      _$PurchaseResultFromJson(json);
  Map<String, dynamic> toJson() => _$PurchaseResultToJson(this);
}
