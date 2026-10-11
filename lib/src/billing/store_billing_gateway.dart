import 'package:flutter/foundation.dart';
import 'package:inappify_sdk/models/enums/market.dart';

/// Store-neutral purchase metadata forwarded to the Inappify backend.
///
/// Store SDK classes must never cross this boundary. Purchase tokens are
/// sensitive and must not be logged by gateway implementations.
@immutable
class InappifyStorePurchase {
  const InappifyStorePurchase({
    required this.token,
    required this.purchaseTime,
  });

  final String token;
  final int? purchaseTime;
}

/// Isolates marketplace SDKs from the platform-neutral Inappify workflow.
abstract interface class InappifyStoreBillingGateway {
  /// Initializes the requested marketplace connection.
  Future<bool> initialize({required Market market, required String publicKey});

  /// Runs the marketplace purchase UI and returns codec-neutral metadata.
  Future<InappifyStorePurchase?> purchase({
    required Market market,
    required String publicKey,
    required String productIdentifier,
    required String payload,
  });
}
