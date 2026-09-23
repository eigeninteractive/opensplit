// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'entry.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

Entry _$EntryFromJson(
  Map<String, dynamic> json,
) => $checkedCreate('Entry', json, ($checkedConvert) {
  $checkKeys(
    json,
    requiredKeys: const [
      'id',
      'kind',
      'description',
      'categoryId',
      'currency',
      'amountMinor',
      'entryDate',
      'splitKind',
      'fxRate',
      'fxSource',
      'fxAt',
      'notes',
      'createdBy',
      'clientKey',
      'createdAt',
      'updatedAt',
      'deletedAt',
      'payers',
      'shares',
      'seq',
    ],
  );
  final val = Entry(
    id: $checkedConvert('id', (v) => v as String),
    kind: $checkedConvert(
      'kind',
      (v) => $enumDecode(
        _$EntryKindEnumMap,
        v,
        unknownValue: EntryKind.unknownDefaultOpenApi,
      ),
    ),
    description: $checkedConvert('description', (v) => v as String),
    categoryId: $checkedConvert('categoryId', (v) => v as String?),
    currency: $checkedConvert('currency', (v) => v as String),
    amountMinor: $checkedConvert('amountMinor', (v) => (v as num).toInt()),
    entryDate: $checkedConvert('entryDate', (v) => v as String),
    splitKind: $checkedConvert(
      'splitKind',
      (v) => $enumDecode(
        _$SplitKindEnumMap,
        v,
        unknownValue: SplitKind.unknownDefaultOpenApi,
      ),
    ),
    fxRate: $checkedConvert('fxRate', (v) => v as num?),
    fxSource: $checkedConvert('fxSource', (v) => v as String?),
    fxAt: $checkedConvert(
      'fxAt',
      (v) => v == null ? null : DateTime.parse(v as String),
    ),
    notes: $checkedConvert('notes', (v) => v as String?),
    createdBy: $checkedConvert('createdBy', (v) => v as String),
    clientKey: $checkedConvert('clientKey', (v) => v as String?),
    createdAt: $checkedConvert('createdAt', (v) => DateTime.parse(v as String)),
    updatedAt: $checkedConvert('updatedAt', (v) => DateTime.parse(v as String)),
    deletedAt: $checkedConvert(
      'deletedAt',
      (v) => v == null ? null : DateTime.parse(v as String),
    ),
    payers: $checkedConvert(
      'payers',
      (v) => (v as List<dynamic>)
          .map((e) => Payer.fromJson(e as Map<String, dynamic>))
          .toList(),
    ),
    shares: $checkedConvert(
      'shares',
      (v) => (v as List<dynamic>)
          .map((e) => Share.fromJson(e as Map<String, dynamic>))
          .toList(),
    ),
    seq: $checkedConvert('seq', (v) => (v as num).toInt()),
  );
  return val;
});

Map<String, dynamic> _$EntryToJson(Entry instance) => <String, dynamic>{
  'id': instance.id,
  'kind': _$EntryKindEnumMap[instance.kind]!,
  'description': instance.description,
  'categoryId': instance.categoryId,
  'currency': instance.currency,
  'amountMinor': instance.amountMinor,
  'entryDate': instance.entryDate,
  'splitKind': _$SplitKindEnumMap[instance.splitKind]!,
  'fxRate': instance.fxRate,
  'fxSource': instance.fxSource,
  'fxAt': instance.fxAt?.toIso8601String(),
  'notes': instance.notes,
  'createdBy': instance.createdBy,
  'clientKey': instance.clientKey,
  'createdAt': instance.createdAt.toIso8601String(),
  'updatedAt': instance.updatedAt.toIso8601String(),
  'deletedAt': instance.deletedAt?.toIso8601String(),
  'payers': instance.payers.map((e) => e.toJson()).toList(),
  'shares': instance.shares.map((e) => e.toJson()).toList(),
  'seq': instance.seq,
};

const _$EntryKindEnumMap = {
  EntryKind.expense: 'expense',
  EntryKind.settlement: 'settlement',
  EntryKind.unknownDefaultOpenApi: 'unknown_default_open_api',
};

const _$SplitKindEnumMap = {
  SplitKind.equal: 'equal',
  SplitKind.exact: 'exact',
  SplitKind.shares: 'shares',
  SplitKind.percent: 'percent',
  SplitKind.unknownDefaultOpenApi: 'unknown_default_open_api',
};
