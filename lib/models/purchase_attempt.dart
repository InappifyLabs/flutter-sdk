import 'package:flutter/foundation.dart';
import 'package:inappify_sdk/models/purchase_result.dart';
import 'package:inappify_sdk/models/enums/purchase_status.dart';
import 'package:inappify_sdk/src/platform/contracts/sdk_failure.dart';

enum InappifyPurchaseAttemptStatus { pending, succeeded, failed }

/// Local correlation history for the current native app/customer/market.
/// A missing record is unknown; recorded success is not current access authority.
@immutable
class InappifyPurchaseAttempt {
  const InappifyPurchaseAttempt({
    required this.attemptId,
    required this.productIdentifier,
    required this.offeringIdentifier,
    required this.market,
    required this.status,
    required this.updatedAtEpochMillis,
    this.purchase,
    this.failure,
  });

  final String attemptId, productIdentifier, offeringIdentifier, market;
  final InappifyPurchaseAttemptStatus status;
  final int updatedAtEpochMillis;
  final PurchaseResult? purchase;
  final InappifyFailure? failure;
  bool get isFinal => status != InappifyPurchaseAttemptStatus.pending;

  factory InappifyPurchaseAttempt.fromMap(Map<String, dynamic> map) {
    final id = map['attemptId'];
    final product = map['productIdentifier'];
    final offering = map['offeringIdentifier'];
    final market = map['market'];
    final updated = map['updatedAtEpochMillis'];
    final status = switch (map['status']) {
      'PENDING' => InappifyPurchaseAttemptStatus.pending,
      'SUCCEEDED' => InappifyPurchaseAttemptStatus.succeeded,
      'FAILED' => InappifyPurchaseAttemptStatus.failed,
      _ => throw const FormatException('Invalid purchase attempt status.'),
    };
    if (id is! String ||
        !RegExp(r'^[A-Za-z0-9_.:-]{1,128}$').hasMatch(id) ||
        product is! String ||
        product.isEmpty ||
        offering is! String ||
        !{'none', 'bazar', 'myket'}.contains(market) ||
        updated is! num ||
        !updated.isFinite ||
        updated < 0 ||
        updated != updated.toInt()) {
      throw const FormatException('Invalid purchase attempt fields.');
    }
    final rawPurchase = map['purchase'];
    final purchase = rawPurchase == null
        ? null
        : PurchaseResult.fromJson(
            Map<String, dynamic>.from(rawPurchase as Map),
          );
    final rawError = map['error'];
    InappifyFailure? failure;
    if (rawError != null) {
      final error = Map<String, dynamic>.from(rawError as Map);
      if (error['code'] is! String ||
          error['message'] is! String ||
          error['retryable'] is! bool) {
        throw const FormatException('Invalid purchase attempt failure.');
      }
      failure = InappifyFailure(
        code: InappifyFailureCode.values.firstWhere(
          (value) => value.name == error['code'],
          orElse: () => InappifyFailureCode.unknown,
        ),
        message: error['message'] as String,
        isRetryable: error['retryable'] as bool,
        details: Map<String, Object?>.unmodifiable(
          Map<String, Object?>.from(error['details'] as Map? ?? const {}),
        ),
      );
    }
    if (purchase != null &&
            (purchase.mobile?.idempotencyKey != id ||
                purchase.mobile?.productIdentifier != product ||
                purchase.mobile?.offeringIdentifier != offering ||
                purchase.mobile?.market != market) ||
        status == InappifyPurchaseAttemptStatus.succeeded &&
            purchase?.purchaseStatus != PurchaseStatus.DONE ||
        status == InappifyPurchaseAttemptStatus.failed && failure == null) {
      throw const FormatException(
        'Purchase attempt result does not match its identity.',
      );
    }
    return InappifyPurchaseAttempt(
      attemptId: id,
      productIdentifier: product,
      offeringIdentifier: offering,
      market: market as String,
      status: status,
      updatedAtEpochMillis: updated.toInt(),
      purchase: purchase,
      failure: failure,
    );
  }
}
