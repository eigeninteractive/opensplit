// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'entry_input.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

EntryInput _$EntryInputFromJson(Map<String, dynamic> json) =>
    $checkedCreate('EntryInput', json, ($checkedConvert) {
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
          'occurredAt',
          'timeZone',
          'splitKind',
          'fxRate',
          'fxSource',
          'notes',
          'clientKey',
          'payers',
          'shares',
          'baseSeq',
        ],
      );
      final val = EntryInput(
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
        occurredAt: $checkedConvert(
          'occurredAt',
          (v) => v == null ? null : DateTime.parse(v as String),
        ),
        timeZone: $checkedConvert('timeZone', (v) => v as String?),
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
        notes: $checkedConvert('notes', (v) => v as String?),
        clientKey: $checkedConvert('clientKey', (v) => v as String?),
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
        baseSeq: $checkedConvert('baseSeq', (v) => (v as num?)?.toInt()),
      );
      return val;
    });

Map<String, dynamic> _$EntryInputToJson(EntryInput instance) =>
    <String, dynamic>{
      'id': instance.id,
      'kind': _$EntryKindEnumMap[instance.kind]!,
      'description': instance.description,
      'categoryId': instance.categoryId,
      'currency': instance.currency,
      'amountMinor': instance.amountMinor,
      'entryDate': instance.entryDate,
      'occurredAt': instance.occurredAt?.toIso8601String(),
      'timeZone': instance.timeZone,
      'splitKind': _$SplitKindEnumMap[instance.splitKind]!,
      'fxRate': instance.fxRate,
      'fxSource': instance.fxSource,
      'notes': instance.notes,
      'clientKey': instance.clientKey,
      'payers': instance.payers.map((e) => e.toJson()).toList(),
      'shares': instance.shares.map((e) => e.toJson()).toList(),
      'baseSeq': instance.baseSeq,
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
