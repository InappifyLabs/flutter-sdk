import 'package:inappify_sdk/inappify_sdk_platform_interface.dart';
import 'package:inappify_sdk/models/offerings_model.dart';
import 'package:inappify_sdk/src/platform/mobile/go_v2_infrastructure.dart';

/// Commerce-only fixtures; no legacy client, credentials, or resource routes.
class DirectFakeTransport {
  Map<String, dynamic> standard(String endpoint) {
    if (endpoint == 'purchase') {
      return {
        'status': true,
        'data': {
          'purchaseStatus': 'NEEDTOPAY',
          'url': 'https://pay.inappify.com/fixture',
        },
      };
    }
    if (endpoint.endsWith('/pending')) {
      return {
        'status': true,
        'data': {
          'deliveries': [delivery()],
        },
      };
    }
    return {'status': true, 'data': delivery(completed: true)};
  }
}

Map<String, dynamic> delivery({bool completed = false}) => {
  'deliveryId': 11,
  'source': 'direct',
  'productIdentifier': 'coins',
  'status': completed ? 'COMPLETED' : 'DELIVERY_REQUIRED',
  'transactionId': 'fixture-transaction',
  'alreadyDelivered': completed,
};
const metadata = GoV2Metadata(
  identifierValue: 'com.example.fixture',
  versionName: '2.1.0',
  versionCode: 21,
);
const purchaseRequest = InappifyPurchaseRequest(
  productIdentifier: 'coins',
  offeringIdentifier: 'main',
  idempotencyKey: 'fixture-attempt',
  productType: InappifyProductType.consumable,
);
OfferingsModel get offerings => OfferingsModel.fromJson({
  'offerings': [
    {
      'identifier': 'main',
      'packages': [
        {
          'identifier': 'coin-pack',
          'product': {'identifier': 'coins'},
        },
      ],
    },
  ],
});
