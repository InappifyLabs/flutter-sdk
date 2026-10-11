import 'package:json_annotation/json_annotation.dart';

part 'general_color.g.dart';

@JsonSerializable()
class GeneralColor {

  GeneralColor({
    this.text,
    this.color,
    this.text_color,
  });

  final String? text;
  final String? color;
  final String? text_color;

  factory GeneralColor.fromJson(Map<String, dynamic> json) =>
      _$GeneralColorFromJson(json);
  Map<String, dynamic> toJson() => _$GeneralColorToJson(this);

}
