// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'account.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

Account _$AccountFromJson(Map<String, dynamic> json) =>
    $checkedCreate('Account', json, ($checkedConvert) {
      $checkKeys(
        json,
        requiredKeys: const ['id', 'isAnonymous', 'email', 'displayName'],
      );
      final val = Account(
        id: $checkedConvert('id', (v) => v as String),
        isAnonymous: $checkedConvert('isAnonymous', (v) => v as bool),
        email: $checkedConvert('email', (v) => v as String?),
        displayName: $checkedConvert('displayName', (v) => v as String?),
      );
      return val;
    });

Map<String, dynamic> _$AccountToJson(Account instance) => <String, dynamic>{
  'id': instance.id,
  'isAnonymous': instance.isAnonymous,
  'email': instance.email,
  'displayName': instance.displayName,
};
