// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'minted_link.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

MintedLink _$MintedLinkFromJson(
  Map<String, dynamic> json,
) => $checkedCreate('MintedLink', json, ($checkedConvert) {
  $checkKeys(json, requiredKeys: const ['token', 'expiresAt', 'superseded']);
  final val = MintedLink(
    token: $checkedConvert('token', (v) => v as String),
    expiresAt: $checkedConvert('expiresAt', (v) => DateTime.parse(v as String)),
    superseded: $checkedConvert('superseded', (v) => v as String?),
  );
  return val;
});

Map<String, dynamic> _$MintedLinkToJson(MintedLink instance) =>
    <String, dynamic>{
      'token': instance.token,
      'expiresAt': instance.expiresAt.toIso8601String(),
      'superseded': instance.superseded,
    };
