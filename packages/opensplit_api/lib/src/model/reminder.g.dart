// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'reminder.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

Reminder _$ReminderFromJson(Map<String, dynamic> json) =>
    $checkedCreate('Reminder', json, ($checkedConvert) {
      $checkKeys(json, requiredKeys: const ['outcome', 'sentAt']);
      final val = Reminder(
        outcome: $checkedConvert(
          'outcome',
          (v) => $enumDecode(
            _$ReminderOutcomeEnumMap,
            v,
            unknownValue: ReminderOutcome.unknownDefaultOpenApi,
          ),
        ),
        sentAt: $checkedConvert(
          'sentAt',
          (v) => v == null ? null : DateTime.parse(v as String),
        ),
      );
      return val;
    });

Map<String, dynamic> _$ReminderToJson(Reminder instance) => <String, dynamic>{
  'outcome': _$ReminderOutcomeEnumMap[instance.outcome]!,
  'sentAt': instance.sentAt?.toIso8601String(),
};

const _$ReminderOutcomeEnumMap = {
  ReminderOutcome.sent: 'sent',
  ReminderOutcome.alreadyReminded: 'already_reminded',
  ReminderOutcome.unreachable: 'unreachable',
  ReminderOutcome.unknownDefaultOpenApi: 'unknown_default_open_api',
};
