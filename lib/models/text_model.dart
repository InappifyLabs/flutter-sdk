import 'package:json_annotation/json_annotation.dart';

part 'text_model.g.dart';

@JsonSerializable()
class TextModel {
  final String? primary;
  final String? secondary;
  final String? text1;
  final String? text2;
  final String? text3;
  final String? text4;

  TextModel({
    this.primary,
    this.secondary,
    this.text1,
    this.text2,
    this.text3,
    this.text4,
  });

  factory TextModel.fromJson(Map<String, dynamic> json) =>
      _$TextModelFromJson(json);
  Map<String, dynamic> toJson() => _$TextModelToJson(this);
}
