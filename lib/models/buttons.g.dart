// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'buttons.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

Buttons _$ButtonsFromJson(Map<String, dynamic> json) => Buttons(
      main: json['main'] == null
          ? null
          : GeneralColor.fromJson(json['main'] as Map<String, dynamic>),
      crypto: json['crypto'] == null
          ? null
          : GeneralColor.fromJson(json['crypto'] as Map<String, dynamic>),
    );

Map<String, dynamic> _$ButtonsToJson(Buttons instance) => <String, dynamic>{
      'main': instance.main,
      'crypto': instance.crypto,
    };
