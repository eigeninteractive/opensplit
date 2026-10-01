// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'member.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

Member _$MemberFromJson(
  Map<String, dynamic> json,
) => $checkedCreate('Member', json, ($checkedConvert) {
  $checkKeys(
    json,
    requiredKeys: const [
      'id',
      'profileId',
      'displayName',
      'upiVpa',
      'joinedAt',
      'leftAt',
      'updatedAt',
      'seq',
    ],
  );
  final val = Member(
    id: $checkedConvert('id', (v) => v as String),
    profileId: $checkedConvert('profileId', (v) => v as String?),
    displayName: $checkedConvert('displayName', (v) => v as String),
    upiVpa: $checkedConvert('upiVpa', (v) => v as String?),
    joinedAt: $checkedConvert('joinedAt', (v) => DateTime.parse(v as String)),
    leftAt: $checkedConvert(
      'leftAt',
      (v) => v == null ? null : DateTime.parse(v as String),
    ),
    updatedAt: $checkedConvert('updatedAt', (v) => DateTime.parse(v as String)),
    seq: $checkedConvert('seq', (v) => (v as num).toInt()),
  );
  return val;
});

Map<String, dynamic> _$MemberToJson(Member instance) => <String, dynamic>{
  'id': instance.id,
  'profileId': instance.profileId,
  'displayName': instance.displayName,
  'upiVpa': instance.upiVpa,
  'joinedAt': instance.joinedAt.toIso8601String(),
  'leftAt': instance.leftAt?.toIso8601String(),
  'updatedAt': instance.updatedAt.toIso8601String(),
  'seq': instance.seq,
};
