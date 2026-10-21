import 'package:flutter_test/flutter_test.dart';
import 'package:inappify_sdk/models/attribute.dart';
import 'package:inappify_sdk/src/platform/web/web_payload_codec.dart';

void main() {
  group('InappifyWebPayloadCodec', () {
    test(
      'normalizes documented customer maps and camel-case entitlement data',
      () {
        final customer = InappifyWebPayloadCodec.customerInfo(<String, Object?>{
          'originalAppUserId': 'customer-1',
          'entitlements': <String, Object?>{
            'premium': <String, Object?>{
              'isActive': true,
              'isSandbox': false,
              'expirationDate': '2026-09-01T00:00:00Z',
            },
          },
          'attributes': <String, Object?>{'language': 'fa', 'theme': 'dark'},
        });

        expect(customer.originalAppUserId, 'customer-1');
        expect(customer.entitlements, hasLength(1));
        expect(customer.entitlements.single.identifier, 'premium');
        expect(customer.entitlements.single.isActive, isTrue);
        expect(
          customer.entitlements.single.expirationDate,
          '2026-09-01T00:00:00Z',
        );
        expect(customer.attributes, hasLength(2));
        expect(
          customer.attributes?.map((attribute) => attribute.key),
          containsAll(<String>['language', 'theme']),
        );
      },
    );

    test('marks the Web SDK current offering as the compatibility default', () {
      final offerings = InappifyWebPayloadCodec.offerings(<String, Object?>{
        'all': <Object?>[
          <String, Object?>{'identifier': 'regular', 'isDefault': false},
          <String, Object?>{
            'identifier': 'website-pricing',
            'isDefault': false,
          },
        ],
        'current': <String, Object?>{
          'identifier': 'website-pricing',
          'isDefault': false,
        },
      });

      expect(offerings.offerings, hasLength(2));
      expect(offerings.defaultOffering()?.identifier, 'website-pricing');
    });

    test('accepts an offering array returned directly by the bridge', () {
      final offerings = InappifyWebPayloadCodec.offerings(<Object?>[
        <String, Object?>{'identifier': 'main', 'isDefault': true},
      ]);

      expect(offerings.offerings?.single.identifier, 'main');
    });

    test('preserves beta.1 offering metadata and camel-case rules', () {
      final offerings = InappifyWebPayloadCodec.offerings(<String, Object?>{
        'all': <Object?>[
          <String, Object?>{'identifier': 'main', 'isDefault': true},
        ],
        'forceVersion': 17,
        'fetchedAt': '2026-08-11T10:00:00Z',
        'rules': <Object?>[
          <String, Object?>{
            'defaultOfferingIdentifier': 'main',
            'sort': 3,
            'conditions': <Object?>[
              <String, Object?>{
                'context': 73,
                'field': 'country',
                'operator': '=',
                'value': 'IR',
              },
              <String, Object?>{
                'field': 'platform',
                'operator': 'in',
                'value': <Object?>['web', 3],
              },
            ],
            'placements': <String, Object?>{
              'fallbackOfferingIdentifier': 'main',
              'offerings': <Object?>[
                <String, Object?>{
                  'placementIdentifier': 'pricing',
                  'offeringIdentifier': 'main',
                },
              ],
            },
          },
        ],
      });

      expect(offerings.forceVersion, 17);
      expect(offerings.fetchedAt, '2026-08-11T10:00:00Z');
      expect(offerings.rules?.single.default_offering, 'main');
      expect(offerings.rules?.single.conditions?[0].context, '73');
      expect(offerings.rules?.single.conditions?[0].value, '"IR"');
      expect(offerings.rules?.single.conditions?[1].value, '["web",3]');
      expect(offerings.rules?.single.placements?.fallback_offering_id, 'main');
      expect(
        offerings
            .rules
            ?.single
            .placements
            ?.placement_offerings
            ?.single
            .placement_identifier,
        'pricing',
      );
    });

    test('encodes updateAttributes and syncAttributes shapes separately', () {
      final attributes = <Attribute>[
        Attribute(key: 'language', value: 'fa'),
        Attribute(key: 'theme', value: null),
      ];

      expect(
        InappifyWebPayloadCodec.attributeMap(attributes),
        <String, Object?>{'language': 'fa', 'theme': null},
      );
      expect(InappifyWebPayloadCodec.attributeList(attributes), <Object?>[
        <String, Object?>{'key': 'language', 'value': 'fa'},
        <String, Object?>{'key': 'theme', 'value': null},
      ]);
    });

    test('rejects empty attribute keys before crossing the JS boundary', () {
      expect(
        () => InappifyWebPayloadCodec.attributeMap(<Attribute>[
          Attribute(key: '', value: 'value'),
        ]),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => InappifyWebPayloadCodec.attributeList(<Attribute>[
          Attribute(value: 'value'),
        ]),
        throwsA(isA<FormatException>()),
      );
    });

    test('rejects non-JSON values returned by JavaScript', () {
      expect(
        () => InappifyWebPayloadCodec.optionalMap(<String, Object?>{
          'unsafe': Object(),
        }, field: 'response'),
        throwsA(isA<FormatException>()),
      );
    });

    test('requires strict booleans for entitlement checks', () {
      expect(
        InappifyWebPayloadCodec.boolean(true, field: 'entitlement'),
        isTrue,
      );
      expect(
        () => InappifyWebPayloadCodec.boolean(1, field: 'entitlement'),
        throwsA(isA<FormatException>()),
      );
    });

    test('decodes the nested beta.1 discount validation response', () {
      final result = InappifyWebPayloadCodec.discountValidation(
        <String, Object?>{
          'discount': <String, Object?>{
            'code': 'WELCOME20',
            'isValid': true,
            'percent': 20,
          },
          'offering': <String, Object?>{
            'identifier': 'main',
            'isDefault': true,
            'packages': <Object?>[
              <String, Object?>{
                'identifier': 'monthly',
                'product': <String, Object?>{
                  'identifier': 'premium-monthly',
                  'prices': <Object?>[
                    <String, Object?>{'amount': 190000, 'currency': 'IRR'},
                  ],
                },
              },
            ],
          },
        },
      );

      expect(result.isValid, isTrue);
      expect(result.code, 'WELCOME20');
      expect(result.percent, 20);
      expect(result.offering?.identifier, 'main');
      expect(
        result.offering?.packages?.single.product?.prices?.single.price,
        190000,
      );
    });

    test('requires an offering for nested beta.1 discount validation', () {
      expect(
        () => InappifyWebPayloadCodec.discountValidation(<String, Object?>{
          'discount': <String, Object?>{
            'code': 'WELCOME20',
            'isValid': true,
            'percent': 20,
          },
        }),
        throwsA(isA<FormatException>()),
      );
    });
  });
}
