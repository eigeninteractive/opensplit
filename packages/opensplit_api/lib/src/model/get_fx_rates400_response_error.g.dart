// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'get_fx_rates400_response_error.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

GetFxRates400ResponseError _$GetFxRates400ResponseErrorFromJson(
  Map<String, dynamic> json,
) => $checkedCreate('GetFxRates400ResponseError', json, ($checkedConvert) {
  $checkKeys(json, requiredKeys: const ['code', 'message', 'retry']);
  final val = GetFxRates400ResponseError(
    code: $checkedConvert('code', (v) => v as String),
    message: $checkedConvert('message', (v) => v as String),
    retry: $checkedConvert('retry', (v) => v as String),
  );
  return val;
});

Map<String, dynamic> _$GetFxRates400ResponseErrorToJson(
  GetFxRates400ResponseError instance,
) => <String, dynamic>{
  'code': instance.code,
  'message': instance.message,
  'retry': instance.retry,
};
