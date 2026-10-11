// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'paywall_element.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

PaywallElement _$PaywallElementFromJson(Map<String, dynamic> json) =>
    PaywallElement(
      id: json['id'] as String?,
      type: json['type'] as String?,
      padding: (json['padding'] as List<dynamic>?)
          ?.map((e) => (e as num).toInt())
          .toList(),
      spacing: json['spacing'] as String?,
      topButton: json['topButton'] == null
          ? null
          : PaywallTopButton.fromJson(
              json['topButton'] as Map<String, dynamic>),
      background: json['background'] as String?,
      offset: json['offset'] as String?,
      maskType: json['maskType'] as String?,
      imageFile: json['imageFile'] == null
          ? null
          : PaywallImageFile.fromJson(
              json['imageFile'] as Map<String, dynamic>),
      iconFile: json['iconFile'] == null
          ? null
          : PaywallImageFile.fromJson(json['iconFile'] as Map<String, dynamic>),
      iconWidth: json['iconWidth'] as String?,
      iconHeight: json['iconHeight'] as String?,
      tintColor: json['tintColor'] as String?,
      maskHeight: (json['maskHeight'] as num?)?.toInt(),
      imageHeight: (json['imageHeight'] as num?)?.toInt(),
      cornerRadius: (json['cornerRadius'] as List<dynamic>?)
          ?.map((e) => (e as num).toInt())
          .toList(),
      color: json['color'] as String?,
      fontId: json['fontId'] as String?,
      hAlign: json['hAlign'] as String?,
      margin: (json['margin'] as List<dynamic>?)
          ?.map((e) => (e as num).toInt())
          .toList(),
      maxRows: json['maxRows'] as String?,
      stringId: json['stringId'] as String?,
      onOverflow: json['onOverflow'] as String?,
      text: json['text'] == null
          ? null
          : PaywallText.fromJson(json['text'] as Map<String, dynamic>),
      title: json['title'] as String?,
      action: json['action'] == null
          ? null
          : PaywallAction.fromJson(json['action'] as Map<String, dynamic>),
      border: json['border'] as String?,
      previewType: json['previewType'] as String?,
      primaryFont: json['primaryFont'] as String?,
      primaryColor: json['primaryColor'] as String?,
      contentLayout: json['contentLayout'] == null
          ? null
          : PaywallContentLayout.fromJson(
              json['contentLayout'] as Map<String, dynamic>),
      secondaryFont: json['secondaryFont'] as String?,
      secondaryColor: json['secondaryColor'] as String?,
      borderThickness: json['borderThickness'] as String?,
      links: json['links'] == null
          ? null
          : PaywallLinks.fromJson(json['links'] as Map<String, dynamic>),
      divider: json['divider'] == null
          ? null
          : PaywallDivider.fromJson(json['divider'] as Map<String, dynamic>),
      textStyle: json['textStyle'] == null
          ? null
          : PaywallTextStyle.fromJson(
              json['textStyle'] as Map<String, dynamic>),
      states: json['states'] == null
          ? null
          : PaywallElementStates.fromJson(
              json['states'] as Map<String, dynamic>),
      groupBy: json['groupBy'] as String?,
      previewState: json['previewState'] as String?,
      previewTextStyle: json['previewTextStyle'] as String?,
      selectedPackageId: json['selectedPackageId'] as String?,
      badge: json['badge'] as String?,
      badgeStyle: json['badgeStyle'] == null
          ? null
          : PaywallBadgeStyle.fromJson(
              json['badgeStyle'] as Map<String, dynamic>),
      key: json['key'] as String?,
      connector: json['connector'] == null
          ? null
          : PaywallConnector.fromJson(
              json['connector'] as Map<String, dynamic>),
    );

Map<String, dynamic> _$PaywallElementToJson(PaywallElement instance) =>
    <String, dynamic>{
      'id': instance.id,
      'type': instance.type,
      'padding': instance.padding,
      'spacing': instance.spacing,
      'topButton': instance.topButton,
      'background': instance.background,
      'offset': instance.offset,
      'maskType': instance.maskType,
      'imageFile': instance.imageFile,
      'iconFile': instance.iconFile,
      'iconWidth': instance.iconWidth,
      'iconHeight': instance.iconHeight,
      'tintColor': instance.tintColor,
      'maskHeight': instance.maskHeight,
      'imageHeight': instance.imageHeight,
      'cornerRadius': instance.cornerRadius,
      'color': instance.color,
      'fontId': instance.fontId,
      'hAlign': instance.hAlign,
      'margin': instance.margin,
      'maxRows': instance.maxRows,
      'stringId': instance.stringId,
      'onOverflow': instance.onOverflow,
      'text': instance.text,
      'title': instance.title,
      'action': instance.action,
      'border': instance.border,
      'previewType': instance.previewType,
      'primaryFont': instance.primaryFont,
      'primaryColor': instance.primaryColor,
      'contentLayout': instance.contentLayout,
      'secondaryFont': instance.secondaryFont,
      'secondaryColor': instance.secondaryColor,
      'borderThickness': instance.borderThickness,
      'links': instance.links,
      'divider': instance.divider,
      'textStyle': instance.textStyle,
      'states': instance.states,
      'groupBy': instance.groupBy,
      'previewState': instance.previewState,
      'previewTextStyle': instance.previewTextStyle,
      'selectedPackageId': instance.selectedPackageId,
      'badge': instance.badge,
      'badgeStyle': instance.badgeStyle,
      'key': instance.key,
      'connector': instance.connector,
    };
