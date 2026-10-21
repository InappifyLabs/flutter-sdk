import 'package:flutter/foundation.dart';
import 'package:inappify_sdk/models/package_model.dart';

/// Purchase a package returned by an offering. Android supplies its Activity.
@immutable
class InappifyPurchaseParams {
  const InappifyPurchaseParams({
    required this.packageToPurchase,
    this.idempotencyKey,
    this.paywallId,
    this.paywallRevision,
  });

  final PackageModel packageToPurchase;
  final String? idempotencyKey;
  final int? paywallId;
  final int? paywallRevision;
}
