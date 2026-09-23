// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'share.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

Share _$ShareFromJson(Map<String, dynamic> json) =>
    $checkedCreate('Share', json, ($checkedConvert) {
      $checkKeys(json, requiredKeys: const ['memberId', 'amountMinor']);
      final val = Share(
        memberId: $checkedConvert('memberId', (v) => v as String),
        amountMinor: $checkedConvert('amountMinor', (v) => (v as num).toInt()),
        weightMicros: $checkedConvert(
          'weightMicros',
          (v) => (v as num?)?.toInt(),
        ),
      );
      return val;
    });

Map<String, dynamic> _$ShareToJson(Share instance) => <String, dynamic>{
  'memberId': instance.memberId,
  'amountMinor': instance.amountMinor,
  'weightMicros': ?instance.weightMicros,
};
