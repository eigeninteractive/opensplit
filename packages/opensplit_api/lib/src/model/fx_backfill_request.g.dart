// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'fx_backfill_request.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

FxBackfillRequest _$FxBackfillRequestFromJson(Map<String, dynamic> json) =>
    $checkedCreate('FxBackfillRequest', json, ($checkedConvert) {
      $checkKeys(json, requiredKeys: const ['asOf', 'currency']);
      final val = FxBackfillRequest(
        asOf: $checkedConvert('asOf', (v) => v as String),
        currency: $checkedConvert('currency', (v) => v as String),
      );
      return val;
    });

Map<String, dynamic> _$FxBackfillRequestToJson(FxBackfillRequest instance) =>
    <String, dynamic>{'asOf': instance.asOf, 'currency': instance.currency};
