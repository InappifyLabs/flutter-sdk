import 'package:flutter_test/flutter_test.dart';
import 'package:inappify_sdk/offering_evaluation_context.dart';
import 'package:inappify_sdk/src/domain/offering_resolver.dart';

void main() {
  group('beta.1 Web offering resolver contract', () {
    final context = OfferingEvaluationContext(
      country: 'IR',
      platform: 'web',
      appVersion: '3.4.0',
      sdkVersion: '1.10.0',
      appId: 73,
    );

    test('compares dotted versions segment by segment', () {
      expect(OfferingResolver.compareVersions('1.10.0', '1.9.9'), 1);
      expect(OfferingResolver.compareVersions('1.9.9', '1.10.0'), -1);
      expect(OfferingResolver.compareVersions('1.10', '1.10.0'), 0);
    });

    test('evaluates sdk_version against the mirrored SDK version', () {
      expect(
        OfferingResolver.evaluateField(
          fieldName: 'sdk_version',
          operator: '>',
          data: '"1.9.9"',
          context: context,
        ),
        isTrue,
      );
      expect(
        OfferingResolver.evaluateField(
          fieldName: 'sdk_version',
          operator: '<',
          data: '"1.9.9"',
          context: context,
        ),
        isFalse,
      );
    });

    test('treats Web string and numeric platform identifiers as aliases', () {
      expect(
        OfferingResolver.evaluateField(
          fieldName: 'platform',
          operator: '=',
          data: '3',
          context: context,
        ),
        isTrue,
      );
      expect(
        OfferingResolver.evaluateField(
          fieldName: 'platform',
          operator: 'in',
          data: '["android","3"]',
          context: context,
        ),
        isTrue,
      );
      expect(
        OfferingResolver.evaluateField(
          fieldName: 'platform',
          operator: 'not in',
          data: '["android",2]',
          context: context,
        ),
        isTrue,
      );
    });
  });
}
