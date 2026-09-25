// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'link_event_payload.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

LinkEventPayload _$LinkEventPayloadFromJson(Map<String, dynamic> json) =>
    $checkedCreate('LinkEventPayload', json, ($checkedConvert) {
      $checkKeys(json, requiredKeys: const ['expiresAt']);
      final val = LinkEventPayload(
        expiresAt: $checkedConvert(
          'expiresAt',
          (v) => DateTime.parse(v as String),
        ),
      );
      return val;
    });

Map<String, dynamic> _$LinkEventPayloadToJson(LinkEventPayload instance) =>
    <String, dynamic>{'expiresAt': instance.expiresAt.toIso8601String()};
