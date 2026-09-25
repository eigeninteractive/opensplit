// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'group_patch.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

GroupPatch _$GroupPatchFromJson(Map<String, dynamic> json) =>
    $checkedCreate('GroupPatch', json, ($checkedConvert) {
      $checkKeys(json, requiredKeys: const ['archivedAt']);
      final val = GroupPatch(
        name: $checkedConvert('name', (v) => v as String?),
        simplifyDebts: $checkedConvert('simplifyDebts', (v) => v as bool?),
        archivedAt: $checkedConvert(
          'archivedAt',
          (v) => v == null ? null : DateTime.parse(v as String),
        ),
      );
      return val;
    });

Map<String, dynamic> _$GroupPatchToJson(GroupPatch instance) =>
    <String, dynamic>{
      'name': ?instance.name,
      'simplifyDebts': ?instance.simplifyDebts,
      'archivedAt': instance.archivedAt?.toIso8601String(),
    };
