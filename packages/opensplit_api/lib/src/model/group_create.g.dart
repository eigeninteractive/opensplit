// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'group_create.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

GroupCreate _$GroupCreateFromJson(Map<String, dynamic> json) =>
    $checkedCreate('GroupCreate', json, ($checkedConvert) {
      $checkKeys(
        json,
        requiredKeys: const [
          'id',
          'name',
          'defaultCurrency',
          'isDirect',
          'simplifyDebts',
          'memberId',
          'displayName',
        ],
      );
      final val = GroupCreate(
        id: $checkedConvert('id', (v) => v as String),
        name: $checkedConvert('name', (v) => v as String),
        defaultCurrency: $checkedConvert('defaultCurrency', (v) => v as String),
        isDirect: $checkedConvert('isDirect', (v) => v as bool),
        simplifyDebts: $checkedConvert('simplifyDebts', (v) => v as bool),
        memberId: $checkedConvert('memberId', (v) => v as String),
        displayName: $checkedConvert('displayName', (v) => v as String),
      );
      return val;
    });

Map<String, dynamic> _$GroupCreateToJson(GroupCreate instance) =>
    <String, dynamic>{
      'id': instance.id,
      'name': instance.name,
      'defaultCurrency': instance.defaultCurrency,
      'isDirect': instance.isDirect,
      'simplifyDebts': instance.simplifyDebts,
      'memberId': instance.memberId,
      'displayName': instance.displayName,
    };
