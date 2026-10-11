import 'package:flutter/foundation.dart';
import 'package:inappify_sdk/inappify_sdk.dart' show InappifySdk;
import 'package:inappify_sdk/offering_evaluation_context.dart';

/// Builds the evaluation context used by the legacy `currentOffering` API.
///
/// New domain code should pass an explicit [OfferingEvaluationContext] to
/// `OfferingResolver`. This compatibility factory is the only offering-rule
/// boundary allowed to read the synchronous `InappifySdk` state mirror.
OfferingEvaluationContext createLegacyOfferingEvaluationContext() {
  final attributes = <String, String?>{};
  for (final attribute in InappifySdk.customerInfo?.attributes ?? const []) {
    final key = attribute.key;
    if (key != null && !attributes.containsKey(key)) {
      attributes[key] = attribute.value;
    }
  }

  return OfferingEvaluationContext(
    country: InappifySdk.country,
    platform: kIsWeb
        ? 'web'
        : switch (defaultTargetPlatform) {
            TargetPlatform.android => 'android',
            TargetPlatform.iOS => 'ios',
            _ => '',
          },
    appVersion: InappifySdk.vName,
    sdkVersion: InappifySdk.sdkVersion ?? '',
    appId: InappifySdk.appId,
    customAttributes: attributes,
  );
}
