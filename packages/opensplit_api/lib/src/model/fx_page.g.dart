// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'fx_page.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

FxPage _$FxPageFromJson(Map<String, dynamic> json) =>
    $checkedCreate('FxPage', json, ($checkedConvert) {
      $checkKeys(json, requiredKeys: const ['rates', 'hasMore']);
      final val = FxPage(
        rates: $checkedConvert(
          'rates',
          (v) => (v as List<dynamic>)
              .map((e) => FxRate.fromJson(e as Map<String, dynamic>))
              .toList(),
        ),
        hasMore: $checkedConvert('hasMore', (v) => v as bool),
      );
      return val;
    });

Map<String, dynamic> _$FxPageToJson(FxPage instance) => <String, dynamic>{
  'rates': instance.rates.map((e) => e.toJson()).toList(),
  'hasMore': instance.hasMore,
};
