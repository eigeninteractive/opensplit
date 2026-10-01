// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'device.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

Device _$DeviceFromJson(Map<String, dynamic> json) =>
    $checkedCreate('Device', json, ($checkedConvert) {
      $checkKeys(json, requiredKeys: const ['token', 'platform']);
      final val = Device(
        token: $checkedConvert('token', (v) => v as String),
        platform: $checkedConvert(
          'platform',
          (v) => $enumDecode(
            _$PlatformEnumMap,
            v,
            unknownValue: Platform.unknownDefaultOpenApi,
          ),
        ),
      );
      return val;
    });

Map<String, dynamic> _$DeviceToJson(Device instance) => <String, dynamic>{
  'token': instance.token,
  'platform': _$PlatformEnumMap[instance.platform]!,
};

const _$PlatformEnumMap = {
  Platform.android: 'android',
  Platform.web: 'web',
  Platform.unknownDefaultOpenApi: 'unknown_default_open_api',
};
