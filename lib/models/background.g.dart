// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'background.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

Background _$BackgroundFromJson(Map<String, dynamic> json) => Background(
      color:
          (json['color'] as List<dynamic>?)?.map((e) => e as String).toList(),
      image_name: json['image_name'] as String?,
      image: json['image'] as String?,
    );

Map<String, dynamic> _$BackgroundToJson(Background instance) =>
    <String, dynamic>{
      'color': instance.color,
      'image': instance.image,
      'image_name': instance.image_name,
    };
