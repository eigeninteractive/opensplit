// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'group_cursor.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

GroupCursor _$GroupCursorFromJson(Map<String, dynamic> json) =>
    $checkedCreate('GroupCursor', json, ($checkedConvert) {
      $checkKeys(json, requiredKeys: const ['groupId', 'since']);
      final val = GroupCursor(
        groupId: $checkedConvert('groupId', (v) => v as String),
        since: $checkedConvert('since', (v) => (v as num).toInt()),
      );
      return val;
    });

Map<String, dynamic> _$GroupCursorToJson(GroupCursor instance) =>
    <String, dynamic>{'groupId': instance.groupId, 'since': instance.since};
