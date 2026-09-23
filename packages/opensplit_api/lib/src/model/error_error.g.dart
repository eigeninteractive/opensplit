// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'error_error.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

ErrorError _$ErrorErrorFromJson(Map<String, dynamic> json) =>
    $checkedCreate('ErrorError', json, ($checkedConvert) {
      $checkKeys(json, requiredKeys: const ['code', 'message', 'retry']);
      final val = ErrorError(
        code: $checkedConvert('code', (v) => v as String),
        message: $checkedConvert('message', (v) => v as String),
        retry: $checkedConvert(
          'retry',
          (v) => $enumDecode(
            _$RetryEnumMap,
            v,
            unknownValue: Retry.unknownDefaultOpenApi,
          ),
        ),
      );
      return val;
    });

Map<String, dynamic> _$ErrorErrorToJson(ErrorError instance) =>
    <String, dynamic>{
      'code': instance.code,
      'message': instance.message,
      'retry': _$RetryEnumMap[instance.retry]!,
    };

const _$RetryEnumMap = {
  Retry.stale: 'stale',
  Retry.permanent: 'permanent',
  Retry.transient: 'transient',
  Retry.unknownDefaultOpenApi: 'unknown_default_open_api',
};
