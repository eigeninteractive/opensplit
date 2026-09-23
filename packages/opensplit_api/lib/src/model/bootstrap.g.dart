// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'bootstrap.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

Bootstrap _$BootstrapFromJson(Map<String, dynamic> json) =>
    $checkedCreate('Bootstrap', json, ($checkedConvert) {
      $checkKeys(
        json,
        requiredKeys: const [
          'profileId',
          'displayName',
          'upiVpa',
          'isAnonymous',
          'groupIds',
        ],
      );
      final val = Bootstrap(
        profileId: $checkedConvert('profileId', (v) => v as String),
        displayName: $checkedConvert('displayName', (v) => v as String?),
        upiVpa: $checkedConvert('upiVpa', (v) => v as String?),
        isAnonymous: $checkedConvert('isAnonymous', (v) => v as bool),
        groupIds: $checkedConvert(
          'groupIds',
          (v) => (v as List<dynamic>).map((e) => e as String).toList(),
        ),
      );
      return val;
    });

Map<String, dynamic> _$BootstrapToJson(Bootstrap instance) => <String, dynamic>{
  'profileId': instance.profileId,
  'displayName': instance.displayName,
  'upiVpa': instance.upiVpa,
  'isAnonymous': instance.isAnonymous,
  'groupIds': instance.groupIds,
};
