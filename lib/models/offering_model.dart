import 'package:inappify_sdk/models/package_model.dart';
import 'package:inappify_sdk/models/paywall.dart';
import 'package:inappify_sdk/ui/paywall_modal.dart';
import 'package:flutter/material.dart';
import 'package:json_annotation/json_annotation.dart';

part 'offering_model.g.dart';

@JsonSerializable()
class OfferingModel {
  OfferingModel({
    this.identifier,
    this.isDefault,
    this.serverDescription,
    this.trialDays,
    this.metadata,
    this.packages,
    this.paywall,
  });

  final String? identifier;
  final bool? isDefault;
  final String? serverDescription;
  final int? trialDays;
  final dynamic metadata;
  final List<PackageModel>? packages;
  final Paywall? paywall;

  /// Shows the paywall modal for this offering
  ///
  /// This method will display the paywall UI if a paywall is available for this offering.
  /// Returns true if the paywall was shown, false if no paywall is available.
  bool showPaywall(BuildContext context, {String? fontFamily}) {
    if (paywall == null) {
      debugPrint('No paywall available for this offering');
      return false;
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (BuildContext context) {
        return PaywallModal(
          paywall: paywall!,
          fontFamily: fontFamily,
        );
      },
    );

    return true;
  }

  factory OfferingModel.fromJson(Map<String, dynamic> json) =>
      _$OfferingModelFromJson(json);
  Map<String, dynamic> toJson() => _$OfferingModelToJson(this);
}

extension OfferingModelListExtension on List<OfferingModel> {
  OfferingModel? get current {
    return firstWhere((offering) => offering.isDefault ?? false);
  }
}
