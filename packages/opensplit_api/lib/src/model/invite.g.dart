// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'invite.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

Invite _$InviteFromJson(
  Map<String, dynamic> json,
) => $checkedCreate('Invite', json, ($checkedConvert) {
  $checkKeys(
    json,
    requiredKeys: const [
      'token',
      'memberId',
      'createdBy',
      'createdAt',
      'expiresAt',
      'redeemedAt',
      'redeemedBy',
      'superseded',
    ],
  );
  final val = Invite(
    token: $checkedConvert('token', (v) => v as String),
    memberId: $checkedConvert('memberId', (v) => v as String),
    createdBy: $checkedConvert('createdBy', (v) => v as String),
    createdAt: $checkedConvert('createdAt', (v) => DateTime.parse(v as String)),
    expiresAt: $checkedConvert('expiresAt', (v) => DateTime.parse(v as String)),
    redeemedAt: $checkedConvert(
      'redeemedAt',
      (v) => v == null ? null : DateTime.parse(v as String),
    ),
    redeemedBy: $checkedConvert('redeemedBy', (v) => v as String?),
    superseded: $checkedConvert(
      'superseded',
      (v) => (v as List<dynamic>)
          .map((e) => InviteSupersededInner.fromJson(e as Map<String, dynamic>))
          .toList(),
    ),
  );
  return val;
});

Map<String, dynamic> _$InviteToJson(Invite instance) => <String, dynamic>{
  'token': instance.token,
  'memberId': instance.memberId,
  'createdBy': instance.createdBy,
  'createdAt': instance.createdAt.toIso8601String(),
  'expiresAt': instance.expiresAt.toIso8601String(),
  'redeemedAt': instance.redeemedAt?.toIso8601String(),
  'redeemedBy': instance.redeemedBy,
  'superseded': instance.superseded.map((e) => e.toJson()).toList(),
};
