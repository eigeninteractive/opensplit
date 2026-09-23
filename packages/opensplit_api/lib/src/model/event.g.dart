// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'event.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

Event _$EventFromJson(Map<String, dynamic> json) =>
    $checkedCreate('Event', json, ($checkedConvert) {
      $checkKeys(
        json,
        requiredKeys: const [
          'id',
          'actorId',
          'createdAt',
          'kind',
          'subjectId',
          'seq',
          'ordinal',
        ],
      );
      final val = Event(
        id: $checkedConvert('id', (v) => v as String),
        actorId: $checkedConvert('actorId', (v) => v as String?),
        createdAt: $checkedConvert(
          'createdAt',
          (v) => DateTime.parse(v as String),
        ),
        kind: $checkedConvert(
          'kind',
          (v) => $enumDecode(
            _$EventKindEnumMap,
            v,
            unknownValue: EventKind.unknownDefaultOpenApi,
          ),
        ),
        subjectId: $checkedConvert('subjectId', (v) => v as String?),
        payload: $checkedConvert('payload', (v) => v as Map<String, dynamic>?),
        seq: $checkedConvert('seq', (v) => (v as num).toInt()),
        ordinal: $checkedConvert('ordinal', (v) => (v as num).toInt()),
      );
      return val;
    });

Map<String, dynamic> _$EventToJson(Event instance) => <String, dynamic>{
  'id': instance.id,
  'actorId': instance.actorId,
  'createdAt': instance.createdAt.toIso8601String(),
  'kind': _$EventKindEnumMap[instance.kind]!,
  'subjectId': instance.subjectId,
  'payload': ?instance.payload,
  'seq': instance.seq,
  'ordinal': instance.ordinal,
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
