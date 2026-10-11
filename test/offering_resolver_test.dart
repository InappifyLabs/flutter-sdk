import 'package:flutter_test/flutter_test.dart';
import 'package:inappify_sdk/models/condition.dart';
import 'package:inappify_sdk/models/offering_model.dart';
import 'package:inappify_sdk/models/offerings_model.dart';
import 'package:inappify_sdk/models/placement.dart';
import 'package:inappify_sdk/models/placement_offering.dart';
import 'package:inappify_sdk/models/rule.dart';
import 'package:inappify_sdk/offering_evaluation_context.dart';
import 'package:inappify_sdk/src/domain/offering_resolver.dart';

void main() {
  final defaultOffering = OfferingModel(identifier: 'default', isDefault: true);
  final premiumOffering = OfferingModel(identifier: 'premium');
  final context = OfferingEvaluationContext(
    country: 'IR',
    platform: 'web',
    appVersion: '3.4.0',
    appId: 23,
    customAttributes: const <String, String?>{'tier': 'gold'},
  );

  test('retains the legacy offering-evaluation method signatures', () {
    final model = OfferingsModel();
    final OfferingModel? Function({String? placment}) currentOffering =
        model.currentOffering;
    final bool Function({
      required String filedName,
      required String operator,
      required String data,
      String? context,
    })
    evaluateField = model.evaluateField;

    expect(currentOffering(), isNull);
    expect(
      evaluateField(filedName: 'any_audience', operator: '', data: ''),
      isTrue,
    );
  });

  test('returns the default offering when no rule matches', () {
    final result = OfferingResolver.resolve(
      offerings: <OfferingModel>[defaultOffering, premiumOffering],
      rules: <Rule>[
        Rule(
          default_offering: 'premium',
          conditions: <Condition>[
            Condition(field: 'country', operator: 'in', value: '["US"]'),
          ],
        ),
      ],
      context: context,
    );

    expect(result?.identifier, 'default');
  });

  test('resolves a matching rule from an explicit context', () {
    final model = OfferingsModel(
      offerings: <OfferingModel>[defaultOffering, premiumOffering],
      rules: <Rule>[
        Rule(
          default_offering: 'premium',
          conditions: <Condition>[
            Condition(
              field: 'custom_attribute',
              context: 'tier',
              operator: 'in',
              value: '["gold"]',
            ),
          ],
        ),
      ],
    );

    final result = model.resolveOffering(evaluationContext: context);

    expect(result?.identifier, 'premium');
  });

  test('uses the placement mapping before rule fallbacks', () {
    final result = OfferingResolver.resolve(
      offerings: <OfferingModel>[defaultOffering, premiumOffering],
      rules: <Rule>[
        Rule(
          default_offering: 'default',
          conditions: <Condition>[Condition(field: 'any_audience')],
          placements: Placement(
            fallback_offering_id: 'default',
            placement_offerings: <PlacementOffering>[
              PlacementOffering(
                placement_identifier: 'checkout',
                offering_identifier: 'premium',
              ),
            ],
          ),
        ),
      ],
      context: context,
      placement: 'checkout',
    );

    expect(result?.identifier, 'premium');
  });

  test('preserves historical dotted-version conversion', () {
    expect(OfferingResolver.convertVersionToDouble('3.4.0'), 3.40);
    expect(
      OfferingResolver.evaluateField(
        fieldName: 'app_version',
        operator: '>=',
        data: '"3.3.9"',
        context: context,
      ),
      isTrue,
    );
  });
}
