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
            _$PushKindEnumMap,
            v,
            unknownValue: PushKind.unknownDefaultOpenApi,
          ),
        ),
        subjectId: $checkedConvert('subjectId', (v) => v as String),
        currency: $checkedConvert('currency', (v) => v as String?),
      );
      return val;
    });

Map<String, dynamic> _$PushDataToJson(PushData instance) => <String, dynamic>{
  'groupId': instance.groupId,
  'eventId': instance.eventId,
  'kind': _$PushKindEnumMap[instance.kind]!,
  'subjectId': instance.subjectId,
  'currency': ?instance.currency,
};

const _$PushKindEnumMap = {
  PushKind.entry: 'entry',
  PushKind.memberAdded: 'member_added',
  PushKind.memberJoined: 'member_joined',
  PushKind.memberLeft: 'member_left',
  PushKind.memberRenamed: 'member_renamed',
  PushKind.groupRenamed: 'group_renamed',
  PushKind.linkCreated: 'link_created',
  PushKind.linkRevoked: 'link_revoked',
  PushKind.reminder: 'reminder',
  PushKind.unknownDefaultOpenApi: 'unknown_default_open_api',
};
