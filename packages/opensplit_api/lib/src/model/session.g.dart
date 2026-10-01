// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'session.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

Session _$SessionFromJson(Map<String, dynamic> json) =>
    $checkedCreate('Session', json, ($checkedConvert) {
      $checkKeys(json, requiredKeys: const ['account', 'token']);
      final val = Session(
        account: $checkedConvert(
          'account',
          (v) => v == null ? null : Account.fromJson(v as Map<String, dynamic>),
        ),
        token: $checkedConvert('token', (v) => v as String?),
      );
      return val;
    });

Map<String, dynamic> _$SessionToJson(Session instance) => <String, dynamic>{
  'account': instance.account?.toJson(),
  'token': instance.token,
};
