// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'fx_backfill_response.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

FxBackfillResponse _$FxBackfillResponseFromJson(Map<String, dynamic> json) =>
    $checkedCreate('FxBackfillResponse', json, ($checkedConvert) {
      $checkKeys(json, requiredKeys: const ['accepted']);
      final val = FxBackfillResponse(
        accepted: $checkedConvert('accepted', (v) => v as bool),
      );
      return val;
    });

Map<String, dynamic> _$FxBackfillResponseToJson(FxBackfillResponse instance) =>
    <String, dynamic>{'accepted': instance.accepted};
