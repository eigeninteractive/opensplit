// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'device_forgotten.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

DeviceForgotten _$DeviceForgottenFromJson(Map<String, dynamic> json) =>
    $checkedCreate('DeviceForgotten', json, ($checkedConvert) {
      $checkKeys(json, requiredKeys: const ['forgotten']);
      final val = DeviceForgotten(
        forgotten: $checkedConvert('forgotten', (v) => v as bool),
      );
      return val;
    });

Map<String, dynamic> _$DeviceForgottenToJson(DeviceForgotten instance) =>
    <String, dynamic>{'forgotten': instance.forgotten};
