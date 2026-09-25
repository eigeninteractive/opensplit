// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'member_event_payload.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

MemberEventPayload _$MemberEventPayloadFromJson(Map<String, dynamic> json) =>
    $checkedCreate('MemberEventPayload', json, ($checkedConvert) {
      $checkKeys(json, requiredKeys: const ['displayName', 'previousName']);
      final val = MemberEventPayload(
        displayName: $checkedConvert('displayName', (v) => v as String),
        previousName: $checkedConvert('previousName', (v) => v as String?),
      );
      return val;
    });

Map<String, dynamic> _$MemberEventPayloadToJson(MemberEventPayload instance) =>
    <String, dynamic>{
      'displayName': instance.displayName,
      'previousName': instance.previousName,
    };
