import 'package:inappify_sdk/models/background.dart';
import 'package:inappify_sdk/models/buttons.dart';
import 'package:inappify_sdk/models/feature.dart';
import 'package:inappify_sdk/models/packages_color.dart';
import 'package:json_annotation/json_annotation.dart';

part 'template.g.dart';

@JsonSerializable()
class Template {
  Template({
    this.buttons,
    this.dark,
    this.icon,
    this.icon_name,
    this.packages,
    this.sub_title,
    this.text_color,
    this.sub_text_color,
    this.title,
    this.feature_border_color,
    this.background,
    this.features,
  });

  final String? icon;
  final String? title;
  final Buttons? buttons;
  final PackagesColor? packages;
  final String? icon_name;
  final String? sub_title;
  final String? text_color;
  final String? sub_text_color;
  final String? feature_border_color;
  final Background? background;
  final Template? dark;
  final List<Feature>? features;

  factory Template.fromJson(Map<String, dynamic> json) =>
      _$TemplateFromJson(json);
  Map<String, dynamic> toJson() => _$TemplateToJson(this);
}
