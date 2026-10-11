import 'package:json_annotation/json_annotation.dart';

part 'packages_color.g.dart';

@JsonSerializable()
class PackagesColor {
  PackagesColor({
    this.default_background_color,
    this.default_border_color,
    this.default_text_color,
    this.selected_background_color,
    this.selected_border_color,
    this.selected_text_color,
  });

  final String? default_text_color;
  final String? selected_text_color;
  final String? default_border_color;
  final String? selected_border_color;
  final String? default_background_color;
  final String? selected_background_color;

  factory PackagesColor.fromJson(Map<String, dynamic> json) =>
      _$PackagesColorFromJson(json);
  Map<String, dynamic> toJson() => _$PackagesColorToJson(this);
}
