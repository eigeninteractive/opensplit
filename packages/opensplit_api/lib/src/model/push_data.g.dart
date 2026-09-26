// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'push_data.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

PushData _$PushDataFromJson(Map<String, dynamic> json) =>
    $checkedCreate('PushData', json, ($checkedConvert) {
      $checkKeys(
        json,
        requiredKeys: const ['groupId', 'eventId', 'kind', 'subjectId'],
      );
      final val = PushData(
        groupId: $checkedConvert('groupId', (v) => v as String),
        eventId: $checkedConvert('eventId', (v) => v as String),
        kind: $checkedConvert(
          'kind',
          (v) => $enumDecode(
            _$EventKindEnumMap,
            v,
            unknownValue: EventKind.unknownDefaultOpenApi,
          ),
        ),
        subjectId: $checkedConvert('subjectId', (v) => v as String),
      );
      return val;
    });

Map<String, dynamic> _$PushDataToJson(PushData instance) => <String, dynamic>{
  'groupId': instance.groupId,
  'eventId': instance.eventId,
  'kind': _$EventKindEnumMap[instance.kind]!,
  'subjectId': instance.subjectId,
};

const _$EventKindEnumMap = {
  EventKind.entry: 'entry',
  EventKind.memberAdded: 'member_added',
  EventKind.memberJoined: 'member_joined',
  EventKind.memberLeft: 'member_left',
  EventKind.memberRenamed: 'member_renamed',
  EventKind.groupRenamed: 'group_renamed',
  EventKind.groupArchived: 'group_archived',
  EventKind.groupRestored: 'group_restored',
  EventKind.linkCreated: 'link_created',
  EventKind.linkRevoked: 'link_revoked',
  EventKind.unknownDefaultOpenApi: 'unknown_default_open_api',
};
