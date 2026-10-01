// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'entry_snapshot.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

EntrySnapshot _$EntrySnapshotFromJson(Map<String, dynamic> json) =>
    $checkedCreate('EntrySnapshot', json, ($checkedConvert) {
      $checkKeys(
        json,
        requiredKeys: const [
          'kind',
          'description',
          'currency',
          'amountMinor',
          'entryDate',
          'splitKind',
          'categoryId',
          'notes',
          'deletedAt',
          'payers',
          'shares',
        ],
      );
      final val = EntrySnapshot(
        kind: $checkedConvert(
          'kind',
          (v) => $enumDecode(
            _$EntryKindEnumMap,
            v,
            unknownValue: EntryKind.unknownDefaultOpenApi,
          ),
        ),
        description: $checkedConvert('description', (v) => v as String),
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
        categoryId: $checkedConvert('categoryId', (v) => v as String?),
        notes: $checkedConvert('notes', (v) => v as String?),
        deletedAt: $checkedConvert(
          'deletedAt',
          (v) => v == null ? null : DateTime.parse(v as String),
        ),
        payers: $checkedConvert(
          'payers',
          (v) => (v as List<dynamic>)
              .map((e) => MoneyRow.fromJson(e as Map<String, dynamic>))
              .toList(),
        ),
        shares: $checkedConvert(
          'shares',
          (v) => (v as List<dynamic>)
              .map((e) => MoneyRow.fromJson(e as Map<String, dynamic>))
              .toList(),
        ),
      );
      return val;
    });

Map<String, dynamic> _$EntrySnapshotToJson(EntrySnapshot instance) =>
    <String, dynamic>{
      'kind': _$EntryKindEnumMap[instance.kind]!,
      'description': instance.description,
      'currency': instance.currency,
      'amountMinor': instance.amountMinor,
      'entryDate': instance.entryDate,
      'splitKind': _$SplitKindEnumMap[instance.splitKind]!,
      'categoryId': instance.categoryId,
      'notes': instance.notes,
      'deletedAt': instance.deletedAt?.toIso8601String(),
      'payers': instance.payers.map((e) => e.toJson()).toList(),
      'shares': instance.shares.map((e) => e.toJson()).toList(),
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
