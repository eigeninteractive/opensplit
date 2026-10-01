// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'email_start_request.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

EmailStartRequest _$EmailStartRequestFromJson(Map<String, dynamic> json) =>
    $checkedCreate('EmailStartRequest', json, ($checkedConvert) {
      $checkKeys(json, requiredKeys: const ['email']);
      final val = EmailStartRequest(
        email: $checkedConvert('email', (v) => v as String),
      );
      return val;
    });

Map<String, dynamic> _$EmailStartRequestToJson(EmailStartRequest instance) =>
    <String, dynamic>{'email': instance.email};
