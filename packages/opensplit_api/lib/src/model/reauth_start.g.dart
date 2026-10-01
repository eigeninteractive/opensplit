// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'reauth_start.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

ReauthStart _$ReauthStartFromJson(Map<String, dynamic> json) =>
    $checkedCreate('ReauthStart', json, ($checkedConvert) {
      $checkKeys(json, requiredKeys: const ['email']);
      final val = ReauthStart(
        email: $checkedConvert('email', (v) => v as String),
      );
      return val;
    });

Map<String, dynamic> _$ReauthStartToJson(ReauthStart instance) =>
    <String, dynamic>{'email': instance.email};
