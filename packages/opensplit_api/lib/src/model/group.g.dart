// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'group.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

Group _$GroupFromJson(
  Map<String, dynamic> json,
) => $checkedCreate('Group', json, ($checkedConvert) {
  $checkKeys(
    json,
    requiredKeys: const [
      'id',
      'name',
      'defaultCurrency',
      'isDirect',
      'simplifyDebts',
      'createdBy',
      'createdAt',
      'archivedAt',
      'updatedAt',
      'seq',
    ],
  );
  final val = Group(
    id: $checkedConvert('id', (v) => v as String),
    name: $checkedConvert('name', (v) => v as String),
    defaultCurrency: $checkedConvert('defaultCurrency', (v) => v as String),
    isDirect: $checkedConvert('isDirect', (v) => v as bool),
    simplifyDebts: $checkedConvert('simplifyDebts', (v) => v as bool),
    createdBy: $checkedConvert('createdBy', (v) => v as String),
    createdAt: $checkedConvert('createdAt', (v) => DateTime.parse(v as String)),
    archivedAt: $checkedConvert(
      'archivedAt',
      (v) => v == null ? null : DateTime.parse(v as String),
    ),
    updatedAt: $checkedConvert('updatedAt', (v) => DateTime.parse(v as String)),
    seq: $checkedConvert('seq', (v) => (v as num).toInt()),
  );
  return val;
});

Map<String, dynamic> _$GroupToJson(Group instance) => <String, dynamic>{
  'id': instance.id,
  'name': instance.name,
  'defaultCurrency': instance.defaultCurrency,
  'isDirect': instance.isDirect,
  'simplifyDebts': instance.simplifyDebts,
  'createdBy': instance.createdBy,
  'createdAt': instance.createdAt.toIso8601String(),
  'archivedAt': instance.archivedAt?.toIso8601String(),
  'updatedAt': instance.updatedAt.toIso8601String(),
  'seq': instance.seq,
};
