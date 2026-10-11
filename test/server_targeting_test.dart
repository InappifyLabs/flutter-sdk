import 'dart:io';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:inappify_sdk/models/offerings_model.dart';
import 'package:inappify_sdk/models/mobile_v2.dart';

void main() {
  Map<String, dynamic> catalog(String? selected) => {
    'offerings': [
      {'identifier': 'default', 'isDefault': true},
      {'identifier': 'family'},
      {'identifier': 'sdk3'},
    ],
    'currentOffering': selected,
    'placements': {'home': 'sdk3', 'missing': null},
  };

  test('cached offering retains server attribute selection and placements', () {
    final value = OfferingsModel.fromJson(catalog('family'));
    expect(value.currentOffering()?.identifier, 'family');
    expect(value.currentOffering(placment: 'home')?.identifier, 'sdk3');
    expect(value.currentOffering(placment: 'missing')?.identifier, 'family');
    final restored = OfferingsModel.fromJson(
      jsonDecode(jsonEncode(value.toJson())),
    );
    expect(restored.usesServerTargeting, true);
    expect(restored.currentOffering()?.identifier, 'family');
    expect(restored.currentOffering(placment: 'home')?.identifier, 'sdk3');
  });
  test('null or unknown selection falls back to server default', () {
    for (final selected in [null, 'unavailable']) {
      final value = OfferingsModel.fromJson(catalog(selected));
      expect(value.currentOffering()?.identifier, 'default');
      expect(value.currentOffering(placment: 'home')?.identifier, 'sdk3');
      expect(
        OfferingsModel.fromJson(
          jsonDecode(jsonEncode(value.toJson())),
        ).usesServerTargeting,
        true,
      );
    }
  });
  test('SDK source has no V1 HTTP route or selectable V1 protocol', () {
    expect(InappifyMobileProtocol.values, [InappifyMobileProtocol.goV2]);
    for (final entry in Directory('lib').listSync(recursive: true)) {
      if (entry is File && entry.path.endsWith('.dart')) {
        expect(
          entry.readAsStringSync(),
          isNot(contains('/app/v1/')),
          reason: entry.path,
        );
      }
    }
  });
}
