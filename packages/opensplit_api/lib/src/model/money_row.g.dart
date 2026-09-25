// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'money_row.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

MoneyRow _$MoneyRowFromJson(Map<String, dynamic> json) =>
    $checkedCreate('MoneyRow', json, ($checkedConvert) {
      $checkKeys(json, requiredKeys: const ['memberId', 'amountMinor']);
      final val = MoneyRow(
        memberId: $checkedConvert('memberId', (v) => v as String),
        amountMinor: $checkedConvert('amountMinor', (v) => (v as num).toInt()),
      );
      return val;
    });

Map<String, dynamic> _$MoneyRowToJson(MoneyRow instance) => <String, dynamic>{
  'memberId': instance.memberId,
  'amountMinor': instance.amountMinor,
};
