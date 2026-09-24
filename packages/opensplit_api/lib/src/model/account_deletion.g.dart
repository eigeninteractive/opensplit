// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'account_deletion.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

AccountDeletion _$AccountDeletionFromJson(Map<String, dynamic> json) =>
    $checkedCreate('AccountDeletion', json, ($checkedConvert) {
      $checkKeys(json, requiredKeys: const ['forgotten', 'purged']);
      final val = AccountDeletion(
        forgotten: $checkedConvert('forgotten', (v) => (v as num).toInt()),
        purged: $checkedConvert('purged', (v) => (v as num).toInt()),
      );
      return val;
    });

Map<String, dynamic> _$AccountDeletionToJson(AccountDeletion instance) =>
    <String, dynamic>{
      'forgotten': instance.forgotten,
      'purged': instance.purged,
    };
