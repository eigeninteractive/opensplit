// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'pull.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

Pull _$PullFromJson(Map<String, dynamic> json) =>
    $checkedCreate('Pull', json, ($checkedConvert) {
      $checkKeys(json, requiredKeys: const ['groupIds', 'pages', 'refusals']);
      final val = Pull(
        groupIds: $checkedConvert(
          'groupIds',
          (v) => (v as List<dynamic>).map((e) => e as String).toList(),
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
  'pages': instance.pages.map((e) => e.toJson()).toList(),
  'refusals': instance.refusals.map((e) => e.toJson()).toList(),
};
