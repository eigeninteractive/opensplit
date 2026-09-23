// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'member_patch.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

MemberPatch _$MemberPatchFromJson(Map<String, dynamic> json) =>
    $checkedCreate('MemberPatch', json, ($checkedConvert) {
      final val = MemberPatch(
        displayName: $checkedConvert('displayName', (v) => v as String?),
        upiVpa: $checkedConvert('upiVpa', (v) => v as String?),
        leftAt: $checkedConvert(
          'leftAt',
          (v) => v == null ? null : DateTime.parse(v as String),
        ),
      );
      return val;
    });

Map<String, dynamic> _$MemberPatchToJson(MemberPatch instance) =>
    <String, dynamic>{
      'displayName': ?instance.displayName,
      'upiVpa': ?instance.upiVpa,
      'leftAt': ?instance.leftAt?.toIso8601String(),
    };
