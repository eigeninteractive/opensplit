// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'currency.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

Currency _$CurrencyFromJson(Map<String, dynamic> json) =>
    $checkedCreate('Currency', json, ($checkedConvert) {
      $checkKeys(
        json,
        requiredKeys: const ['code', 'exponent', 'symbol', 'name'],
      );
      final val = Currency(
        code: $checkedConvert('code', (v) => v as String),
        exponent: $checkedConvert('exponent', (v) => (v as num).toInt()),
        symbol: $checkedConvert('symbol', (v) => v as String?),
        name: $checkedConvert('name', (v) => v as String),
      );
      return val;
    });

Map<String, dynamic> _$CurrencyToJson(Currency instance) => <String, dynamic>{
  'code': instance.code,
  'exponent': instance.exponent,
  'symbol': instance.symbol,
  'name': instance.name,
};
