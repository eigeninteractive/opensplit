// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'get_fx_rates400_response.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

GetFxRates400Response _$GetFxRates400ResponseFromJson(
  Map<String, dynamic> json,
) => $checkedCreate('GetFxRates400Response', json, ($checkedConvert) {
  $checkKeys(json, requiredKeys: const ['error']);
  final val = GetFxRates400Response(
    error: $checkedConvert(
      'error',
      (v) => GetFxRates400ResponseError.fromJson(v as Map<String, dynamic>),
    ),
  );
  return val;
});

Map<String, dynamic> _$GetFxRates400ResponseToJson(
  GetFxRates400Response instance,
) => <String, dynamic>{'error': instance.error.toJson()};
