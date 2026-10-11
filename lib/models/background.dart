import 'package:json_annotation/json_annotation.dart';

part 'background.g.dart';

@JsonSerializable()
class Background {
  Background({
    this.color,
    this.image_name,
    this.image,
  });

  final List<String>? color;
  final String? image;
  final String? image_name;

  factory Background.fromJson(Map<String, dynamic> json) =>
      _$BackgroundFromJson(json);
  Map<String, dynamic> toJson() => _$BackgroundToJson(this);
}
