// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'member_create.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

MemberCreate _$MemberCreateFromJson(Map<String, dynamic> json) =>
    $checkedCreate('MemberCreate', json, ($checkedConvert) {
      $checkKeys(json, requiredKeys: const ['id', 'displayName', 'upiVpa']);
      final val = MemberCreate(
        id: $checkedConvert('id', (v) => v as String),
        displayName: $checkedConvert('displayName', (v) => v as String),
        upiVpa: $checkedConvert('upiVpa', (v) => v as String?),
      );
      return val;
    });

Map<String, dynamic> _$MemberCreateToJson(MemberCreate instance) =>
    <String, dynamic>{
      'id': instance.id,
      'displayName': instance.displayName,
      'upiVpa': instance.upiVpa,
    };
