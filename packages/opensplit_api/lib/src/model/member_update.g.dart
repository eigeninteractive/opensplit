// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'member_update.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

MemberUpdate _$MemberUpdateFromJson(Map<String, dynamic> json) =>
    $checkedCreate('MemberUpdate', json, ($checkedConvert) {
      $checkKeys(json, requiredKeys: const ['displayName', 'upiVpa', 'leftAt']);
      final val = MemberUpdate(
        displayName: $checkedConvert('displayName', (v) => v as String),
        upiVpa: $checkedConvert('upiVpa', (v) => v as String?),
        leftAt: $checkedConvert(
          'leftAt',
          (v) => v == null ? null : DateTime.parse(v as String),
        ),
      );
      return val;
    });

Map<String, dynamic> _$MemberUpdateToJson(MemberUpdate instance) =>
    <String, dynamic>{
      'displayName': instance.displayName,
      'upiVpa': instance.upiVpa,
      'leftAt': instance.leftAt?.toIso8601String(),
    };
