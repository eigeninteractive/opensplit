// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'group_update.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

GroupUpdate _$GroupUpdateFromJson(Map<String, dynamic> json) =>
    $checkedCreate('GroupUpdate', json, ($checkedConvert) {
      $checkKeys(
        json,
        requiredKeys: const ['name', 'simplifyDebts', 'archivedAt'],
      );
      final val = GroupUpdate(
        name: $checkedConvert('name', (v) => v as String),
        simplifyDebts: $checkedConvert('simplifyDebts', (v) => v as bool),
        archivedAt: $checkedConvert(
          'archivedAt',
          (v) => v == null ? null : DateTime.parse(v as String),
        ),
      );
      return val;
    });

Map<String, dynamic> _$GroupUpdateToJson(GroupUpdate instance) =>
    <String, dynamic>{
      'name': instance.name,
      'simplifyDebts': instance.simplifyDebts,
      'archivedAt': instance.archivedAt?.toIso8601String(),
    };
