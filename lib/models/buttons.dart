import 'package:inappify_sdk/models/general_color.dart';
import 'package:json_annotation/json_annotation.dart';

part 'buttons.g.dart';

@JsonSerializable()
class Buttons {
  Buttons({
    this.main,
    this.crypto,
  });

  final GeneralColor? main;
  final GeneralColor? crypto;

  factory Buttons.fromJson(Map<String, dynamic> json) =>
      _$ButtonsFromJson(json);
  Map<String, dynamic> toJson() => _$ButtonsToJson(this);
}
