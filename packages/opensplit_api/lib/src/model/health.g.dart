// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'health.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

Health _$HealthFromJson(Map<String, dynamic> json) =>
    $checkedCreate('Health', json, ($checkedConvert) {
      $checkKeys(json, requiredKeys: const ['ok', 'service', 'now']);
      final val = Health(
        ok: $checkedConvert('ok', (v) => v as bool),
        service: $checkedConvert(
          'service',
          (v) => $enumDecode(
            _$HealthServiceEnumEnumMap,
            v,
            unknownValue: HealthServiceEnum.unknownDefaultOpenApi,
          ),
        ),
        now: $checkedConvert('now', (v) => DateTime.parse(v as String)),
      );
      return val;
    });

Map<String, dynamic> _$HealthToJson(Health instance) => <String, dynamic>{
  'ok': instance.ok,
  'service': _$HealthServiceEnumEnumMap[instance.service]!,
  'now': instance.now.toIso8601String(),
};

const _$HealthServiceEnumEnumMap = {
  HealthServiceEnum.opensplit: 'opensplit',
  HealthServiceEnum.unknownDefaultOpenApi: 'unknown_default_open_api',
};
