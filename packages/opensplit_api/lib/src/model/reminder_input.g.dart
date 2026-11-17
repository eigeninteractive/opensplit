// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'reminder_input.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

ReminderInput _$ReminderInputFromJson(Map<String, dynamic> json) =>
    $checkedCreate('ReminderInput', json, ($checkedConvert) {
      $checkKeys(json, requiredKeys: const ['memberId', 'currency']);
      final val = ReminderInput(
        memberId: $checkedConvert('memberId', (v) => v as String),
        currency: $checkedConvert('currency', (v) => v as String),
      );
      return val;
    });

Map<String, dynamic> _$ReminderInputToJson(ReminderInput instance) =>
    <String, dynamic>{
      'memberId': instance.memberId,
      'currency': instance.currency,
    };
