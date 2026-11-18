// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'group_seen.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

GroupSeen _$GroupSeenFromJson(Map<String, dynamic> json) =>
    $checkedCreate('GroupSeen', json, ($checkedConvert) {
      $checkKeys(json, requiredKeys: const ['groupId', 'seenAt']);
      final val = GroupSeen(
        groupId: $checkedConvert('groupId', (v) => v as String),
        seenAt: $checkedConvert('seenAt', (v) => DateTime.parse(v as String)),
      );
      return val;
    });

Map<String, dynamic> _$GroupSeenToJson(GroupSeen instance) => <String, dynamic>{
  'groupId': instance.groupId,
  'seenAt': instance.seenAt.toIso8601String(),
};
