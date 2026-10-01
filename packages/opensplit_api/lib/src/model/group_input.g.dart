// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'group_input.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

GroupInput _$GroupInputFromJson(Map<String, dynamic> json) =>
    $checkedCreate('GroupInput', json, ($checkedConvert) {
      $checkKeys(
        json,
        requiredKeys: const [
          'name',
          'defaultCurrency',
          'isDirect',
          'simplifyDebts',
          'archivedAt',
          'creatorId',
          'creatorName',
        ],
      );
      final val = GroupInput(
        name: $checkedConvert('name', (v) => v as String),
        defaultCurrency: $checkedConvert('defaultCurrency', (v) => v as String),
        isDirect: $checkedConvert('isDirect', (v) => v as bool),
        simplifyDebts: $checkedConvert('simplifyDebts', (v) => v as bool),
        archivedAt: $checkedConvert(
          'archivedAt',
          (v) => v == null ? null : DateTime.parse(v as String),
        ),
        creatorId: $checkedConvert('creatorId', (v) => v as String),
        creatorName: $checkedConvert('creatorName', (v) => v as String),
      );
      return val;
    });

Map<String, dynamic> _$GroupInputToJson(GroupInput instance) =>
    <String, dynamic>{
      'name': instance.name,
      'defaultCurrency': instance.defaultCurrency,
      'isDirect': instance.isDirect,
      'simplifyDebts': instance.simplifyDebts,
      'archivedAt': instance.archivedAt?.toIso8601String(),
      'creatorId': instance.creatorId,
      'creatorName': instance.creatorName,
    };
