// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'group_link.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

GroupLink _$GroupLinkFromJson(Map<String, dynamic> json) =>
    $checkedCreate('GroupLink', json, ($checkedConvert) {
      $checkKeys(json, requiredKeys: const ['token', 'expiresAt']);
      final val = GroupLink(
        token: $checkedConvert('token', (v) => v as String),
        expiresAt: $checkedConvert(
          'expiresAt',
          (v) => DateTime.parse(v as String),
        ),
      );
      return val;
    });

Map<String, dynamic> _$GroupLinkToJson(GroupLink instance) => <String, dynamic>{
  'token': instance.token,
  'expiresAt': instance.expiresAt.toIso8601String(),
};
