// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'group_event_payload.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

GroupEventPayload _$GroupEventPayloadFromJson(Map<String, dynamic> json) =>
    $checkedCreate('GroupEventPayload', json, ($checkedConvert) {
      $checkKeys(json, requiredKeys: const ['name', 'previousName']);
      final val = GroupEventPayload(
        name: $checkedConvert('name', (v) => v as String),
        previousName: $checkedConvert('previousName', (v) => v as String?),
      );
      return val;
    });

Map<String, dynamic> _$GroupEventPayloadToJson(GroupEventPayload instance) =>
    <String, dynamic>{
      'name': instance.name,
      'previousName': instance.previousName,
    };
