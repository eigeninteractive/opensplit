// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'fx_rate.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

FxRate _$FxRateFromJson(Map<String, dynamic> json) =>
    $checkedCreate('FxRate', json, ($checkedConvert) {
      $checkKeys(
        json,
        requiredKeys: const ['asOf', 'currency', 'rate', 'source'],
      );
      final val = FxRate(
        asOf: $checkedConvert('asOf', (v) => v as String),
        currency: $checkedConvert('currency', (v) => v as String),
        rate: $checkedConvert('rate', (v) => v as num),
        source_: $checkedConvert('source', (v) => v as String),
      );
      return val;
    }, fieldKeyMap: const {'source_': 'source'});

Map<String, dynamic> _$FxRateToJson(FxRate instance) => <String, dynamic>{
  'asOf': instance.asOf,
  'currency': instance.currency,
  'rate': instance.rate,
  'source': instance.source_,
};
