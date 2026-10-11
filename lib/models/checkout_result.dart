import 'package:flutter/foundation.dart';

/// Authoritative checkout state returned by Inappify.
@immutable
class InappifyCheckout {
  /// Creates an immutable checkout value.
  const InappifyCheckout({
    required this.id,
    required this.status,
    this.expiresAt,
  });

  /// Opaque checkout identifier used when verifying a payment return.
  final String id;

  /// Provider-defined checkout state such as `Paid` or `Pending`.
  final String status;

  /// ISO-8601 checkout expiration supplied by the service.
  final String? expiresAt;

  /// Decodes checkout state while accepting documented camel-case aliases.
  factory InappifyCheckout.fromMap(Map<String, dynamic> map) {
    final id = map['id'] ?? map['checkoutId'] ?? map['checkout_id'];
    final status = map['status'] ?? map['checkoutStatus'];
    final expiresAt = map['expiresAt'] ?? map['expires_at'];
    if (id is! String || id.isEmpty || status is! String || status.isEmpty) {
      throw const FormatException(
        'Checkout id and status must be non-empty strings.',
      );
    }
    if (expiresAt != null && expiresAt is! String) {
      throw const FormatException('Checkout expiresAt must be a string.');
    }
    return InappifyCheckout(
      id: id,
      status: status,
      expiresAt: expiresAt as String?,
    );
  }

  /// Encodes checkout state using standard message-codec values.
  Map<String, Object?> toMap() => <String, Object?>{
    'id': id,
    'status': status,
    'expiresAt': expiresAt,
  };
}

/// Server-authoritative price attached to a Web checkout.
@immutable
class InappifyCheckoutPrice {
  /// Creates an immutable checkout price.
  const InappifyCheckoutPrice({
    required this.originalAmount,
    required this.discountAmount,
    required this.finalAmount,
    required this.currency,
  });

  /// Price before discounts, in the server-defined currency unit.
  final num originalAmount;

  /// Discount applied by the server.
  final num discountAmount;

  /// Final payable amount. Browser code must not recalculate this value.
  final num finalAmount;

  /// ISO-style currency code returned by the service.
  final String currency;

  /// Decodes the documented checkout price shape.
  factory InappifyCheckoutPrice.fromMap(Map<String, dynamic> map) {
    final original = map['originalAmount'] ?? map['original_amount'];
    final discount = map['discountAmount'] ?? map['discount_amount'];
    final finalAmount = map['finalAmount'] ?? map['final_amount'];
    final currency = map['currency'];
    if (original is! num ||
        discount is! num ||
        finalAmount is! num ||
        currency is! String ||
        currency.isEmpty) {
      throw const FormatException('Checkout price is malformed.');
    }
    return InappifyCheckoutPrice(
      originalAmount: original,
      discountAmount: discount,
      finalAmount: finalAmount,
      currency: currency,
    );
  }

  /// Encodes this price using standard message-codec values.
  Map<String, Object?> toMap() => <String, Object?>{
    'originalAmount': originalAmount,
    'discountAmount': discountAmount,
    'finalAmount': finalAmount,
    'currency': currency,
  };
}

/// Follow-up action required to continue a checkout.
@immutable
class InappifyCheckoutNextAction {
  /// Creates an immutable next action.
  const InappifyCheckoutNextAction({required this.type, this.url});

  /// Provider-defined action type, including the documented `redirect` value.
  final String type;

  /// Server-issued redirect URL, when required.
  final String? url;

  /// Decodes a checkout next action.
  factory InappifyCheckoutNextAction.fromMap(Map<String, dynamic> map) {
    final type = map['type'];
    final url = map['url'];
    if (type is! String || type.isEmpty || (url != null && url is! String)) {
      throw const FormatException('Checkout nextAction has invalid fields.');
    }
    if (url is String) {
      final parsed = Uri.tryParse(url);
      if (parsed == null ||
          (parsed.hasScheme &&
              parsed.scheme != 'https' &&
              parsed.scheme != 'http')) {
        throw const FormatException(
          'Checkout redirect URL uses an unsupported scheme.',
        );
      }
    }
    return InappifyCheckoutNextAction(type: type, url: url as String?);
  }

  /// Encodes this action using standard message-codec values.
  Map<String, Object?> toMap() => <String, Object?>{'type': type, 'url': url};
}

/// Result of creating or polling an Inappify checkout.
///
/// Callback query parameters are intentionally absent. Payment state is
/// authoritative only when returned by the backend for [checkout.id].
@immutable
class InappifyCheckoutResult {
  /// Creates a checkout result.
  const InappifyCheckoutResult({
    required this.checkout,
    required this.nextAction,
    this.price,
  });

  /// Current authoritative checkout state.
  final InappifyCheckout checkout;

  /// Action required by the customer, if any.
  final InappifyCheckoutNextAction nextAction;

  /// Server-authoritative price, when returned by the selected backend.
  final InappifyCheckoutPrice? price;

  /// Whether the checkout is in the documented paid state.
  bool get isPaid => checkout.status.toLowerCase() == 'paid';

  /// Decodes a checkout response from JavaScript or MethodChannel.
  factory InappifyCheckoutResult.fromMap(Map<String, dynamic> map) {
    final checkout = _stringMap(map['checkout']);
    final nextAction = _stringMap(map['nextAction'] ?? map['next_action']);
    final price = _stringMap(map['price']);
    if (checkout == null) {
      throw const FormatException('Checkout result requires a checkout map.');
    }
    return InappifyCheckoutResult(
      checkout: InappifyCheckout.fromMap(checkout),
      nextAction: nextAction == null
          ? const InappifyCheckoutNextAction(type: 'none')
          : InappifyCheckoutNextAction.fromMap(nextAction),
      price: price == null ? null : InappifyCheckoutPrice.fromMap(price),
    );
  }

  /// Encodes this result using standard message-codec values.
  Map<String, Object?> toMap() => <String, Object?>{
    'checkout': checkout.toMap(),
    'nextAction': nextAction.toMap(),
    'price': price?.toMap(),
  };

  static Map<String, dynamic>? _stringMap(Object? value) {
    if (value is! Map) return null;
    return value.map<String, dynamic>(
      (key, item) => MapEntry<String, dynamic>(key.toString(), item),
    );
  }
}
