// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'payer.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

Payer _$PayerFromJson(Map<String, dynamic> json) =>
    $checkedCreate('Payer', json, ($checkedConvert) {
      $checkKeys(json, requiredKeys: const ['memberId', 'amountMinor']);
      final val = Payer(
        memberId: $checkedConvert('memberId', (v) => v as String),
        amountMinor: $checkedConvert('amountMinor', (v) => (v as num).toInt()),
      );
      return val;
    });

Map<String, dynamic> _$PayerToJson(Payer instance) => <String, dynamic>{
  'memberId': instance.memberId,
  'amountMinor': instance.amountMinor,
};
