// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'group_ids.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

GroupIds _$GroupIdsFromJson(Map<String, dynamic> json) =>
    $checkedCreate('GroupIds', json, ($checkedConvert) {
      $checkKeys(json, requiredKeys: const ['groupIds']);
      final val = GroupIds(
        groupIds: $checkedConvert(
          'groupIds',
          (v) => (v as List<dynamic>).map((e) => e as String).toList(),
        ),
      );
      return val;
    });

Map<String, dynamic> _$GroupIdsToJson(GroupIds instance) => <String, dynamic>{
  'groupIds': instance.groupIds,
};
