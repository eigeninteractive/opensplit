// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'live_link.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

LiveLink _$LiveLinkFromJson(Map<String, dynamic> json) =>
    $checkedCreate('LiveLink', json, ($checkedConvert) {
      $checkKeys(json, requiredKeys: const ['link']);
      final val = LiveLink(
        link: $checkedConvert(
          'link',
          (v) =>
              v == null ? null : GroupLink.fromJson(v as Map<String, dynamic>),
        ),
      );
      return val;
    });

Map<String, dynamic> _$LiveLinkToJson(LiveLink instance) => <String, dynamic>{
  'link': instance.link?.toJson(),
};
