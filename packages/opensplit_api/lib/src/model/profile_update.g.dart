// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'profile_update.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

ProfileUpdate _$ProfileUpdateFromJson(Map<String, dynamic> json) =>
    $checkedCreate('ProfileUpdate', json, ($checkedConvert) {
      $checkKeys(json, requiredKeys: const ['displayName', 'upiVpa']);
      final val = ProfileUpdate(
        displayName: $checkedConvert('displayName', (v) => v as String?),
        upiVpa: $checkedConvert('upiVpa', (v) => v as String?),
      );
      return val;
    });

Map<String, dynamic> _$ProfileUpdateToJson(ProfileUpdate instance) =>
    <String, dynamic>{
      'displayName': instance.displayName,
      'upiVpa': instance.upiVpa,
    };
