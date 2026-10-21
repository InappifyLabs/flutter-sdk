import 'package:inappify_sdk/src/logging/sdk_logger.dart';
import 'package:inappify_sdk/models/offering_model.dart';
import 'package:inappify_sdk/models/rule.dart';
import 'package:inappify_sdk/offering_evaluation_context.dart';
import 'package:inappify_sdk/src/domain/legacy_offering_evaluation_context.dart';
import 'package:inappify_sdk/src/domain/offering_resolver.dart';
import 'package:json_annotation/json_annotation.dart';

part 'offerings_model.g.dart';

@JsonSerializable()
class OfferingsModel {
  OfferingsModel({
    this.offerings,
    this.rules,
    this.forceVersion,
    this.fetchedAt,
    this.currentOfferingIdentifier,
    this.placements,
    this.usesServerTargeting = false,
  });

  final List<OfferingModel>? offerings;
  final List<Rule>? rules;

  /// Offering selected by the V2 server for the current session and attributes.
  @JsonKey(name: 'currentOffering', includeIfNull: false)
  final String? currentOfferingIdentifier;

  @JsonKey(includeIfNull: false)
  final Map<String, String?>? placements;

  /// Retains server-selection semantics even when its selection is explicitly null.
  final bool usesServerTargeting;

  /// Service force-version used to invalidate cached offerings.
  final int? forceVersion;

  /// ISO-8601 timestamp at which the Web SDK fetched this collection.
  final String? fetchedAt;

  factory OfferingsModel.fromJson(Map<String, dynamic> json) =>
      _$OfferingsModelFromJson({
        ...json,
        'usesServerTargeting':
            json['usesServerTargeting'] == true ||
            json.containsKey('currentOffering') ||
            json.containsKey('placements'),
      });
  Map<String, dynamic> toJson() => _$OfferingsModelToJson(this);

  Map<String, OfferingModel> get all => Map.unmodifiable({
    for (final offering in offerings ?? <OfferingModel>[])
      if (offering.identifier != null) offering.identifier!: offering,
  });
  OfferingModel? getOffering(String identifier) => all[identifier];
  OfferingModel? get current => getCurrentOfferingForPlacement(null);
  OfferingModel? getCurrentOfferingForPlacement(String? placementIdentifier) =>
      resolveOffering(
        placement: placementIdentifier,
        evaluationContext: createLegacyOfferingEvaluationContext(),
      );

  /// Returns the offering marked as the server default.
  ///
  /// This retains the historical `firstWhere` behavior: a non-null offering
  /// list without a default entry throws [StateError].
  OfferingModel? defaultOffering() {
    return offerings?.firstWhere((offering) => offering.isDefault ?? false);
  }

  /// Resolves the offering for the current customer and optional placement.
  ///
  /// The historical `placment` spelling is retained for source compatibility.
  /// This compatibility method builds its inputs from the synchronous
  /// `InappifySdk` snapshot. New code should use [resolveOffering].
  OfferingModel? currentOffering({String? placment}) {
    return resolveOffering(
      placement: placment,
      evaluationContext: createLegacyOfferingEvaluationContext(),
    );
  }

  /// Resolves an offering using explicit, platform-independent inputs.
  OfferingModel? resolveOffering({
    required OfferingEvaluationContext evaluationContext,
    String? placement,
  }) {
    try {
      if (usesServerTargeting) {
        OfferingModel? find(String? identifier) {
          if (identifier == null) return null;
          for (final offering in offerings ?? <OfferingModel>[]) {
            if (offering.identifier == identifier) return offering;
          }
          return null;
        }

        return find(placements?[placement]) ??
            find(currentOfferingIdentifier) ??
            offerings
                ?.where((offering) => offering.isDefault == true)
                .firstOrNull;
      }
      return OfferingResolver.resolve(
        offerings: offerings,
        rules: rules,
        placement: placement,
        context: evaluationContext,
      );
    } catch (error) {
      SdkLogger.error('Inappify offering resolution failed: ${error.runtimeType}');
      return null;
    }
  }

  /// Evaluates one offering condition using the compatibility context.
  ///
  /// The historical `filedName` spelling is retained for source compatibility.
  bool evaluateField({
    required String filedName,
    required String operator,
    required String data,
    String? context,
  }) {
    return evaluateFieldWithContext(
      filedName: filedName,
      operator: operator,
      data: data,
      context: context,
      evaluationContext: createLegacyOfferingEvaluationContext(),
    );
  }

  /// Evaluates one condition using explicit, platform-independent inputs.
  bool evaluateFieldWithContext({
    required String filedName,
    required String operator,
    required String data,
    required OfferingEvaluationContext evaluationContext,
    String? context,
  }) {
    return OfferingResolver.evaluateField(
      fieldName: filedName,
      operator: operator,
      data: data,
      attributeKey: context,
      context: evaluationContext,
    );
  }

  /// Applies one of the stable server-defined comparison operators.
  bool evaluateOperator(dynamic left, String operator, dynamic right) {
    return OfferingResolver.evaluateOperator(left, operator, right);
  }

  /// Converts a dotted version using the SDK's historical comparison format.
  double convertVersionToDouble(String version) {
    return OfferingResolver.convertVersionToDouble(version);
  }
}
