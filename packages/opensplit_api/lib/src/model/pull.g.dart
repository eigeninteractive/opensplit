// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'pull.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

Pull _$PullFromJson(Map<String, dynamic> json) =>
    $checkedCreate('Pull', json, ($checkedConvert) {
      $checkKeys(
        json,
        requiredKeys: const ['groupIds', 'seen', 'pages', 'refusals'],
      );
      final val = Pull(
        groupIds: $checkedConvert(
          'groupIds',
          (v) => (v as List<dynamic>).map((e) => e as String).toList(),
        ),
        seen: $checkedConvert(
          'seen',
          (v) => (v as List<dynamic>)
              .map((e) => GroupSeen.fromJson(e as Map<String, dynamic>))
              .toList(),
        ),
        pages: $checkedConvert(
          'pages',
          (v) => (v as List<dynamic>)
              .map((e) => ChangePage.fromJson(e as Map<String, dynamic>))
              .toList(),
        ),
        refusals: $checkedConvert(
          'refusals',
          (v) => (v as List<dynamic>)
              .map((e) => GroupRefusal.fromJson(e as Map<String, dynamic>))
              .toList(),
        ),
      );
      return val;
    });

Map<String, dynamic> _$PullToJson(Pull instance) => <String, dynamic>{
  'groupIds': instance.groupIds,
  'seen': instance.seen.map((e) => e.toJson()).toList(),
  'pages': instance.pages.map((e) => e.toJson()).toList(),
  'refusals': instance.refusals.map((e) => e.toJson()).toList(),
};
