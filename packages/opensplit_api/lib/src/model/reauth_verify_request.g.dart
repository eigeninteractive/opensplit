// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'reauth_verify_request.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

ReauthVerifyRequest _$ReauthVerifyRequestFromJson(Map<String, dynamic> json) =>
    $checkedCreate('ReauthVerifyRequest', json, ($checkedConvert) {
      $checkKeys(json, requiredKeys: const ['code']);
      final val = ReauthVerifyRequest(
        code: $checkedConvert('code', (v) => v as String),
      );
      return val;
    });

Map<String, dynamic> _$ReauthVerifyRequestToJson(
  ReauthVerifyRequest instance,
) => <String, dynamic>{'code': instance.code};
