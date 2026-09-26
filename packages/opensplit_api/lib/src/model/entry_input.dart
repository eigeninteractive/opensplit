//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:opensplit_api/src/model/share.dart';
import 'package:opensplit_api/src/model/split_kind.dart';
import 'package:opensplit_api/src/model/entry_kind.dart';
import 'package:opensplit_api/src/model/payer.dart';
import 'package:json_annotation/json_annotation.dart';

part 'entry_input.g.dart';

@JsonSerializable(
  checked: true,
  createToJson: true,
  disallowUnrecognizedKeys: false,
  explicitToJson: true,
)
class EntryInput {
  /// Returns a new [EntryInput] instance.
  EntryInput({
    required this.id,

    required this.clientKey,

    required this.kind,

    required this.description,

    required this.categoryId,

    required this.currency,

    required this.amountMinor,

    required this.entryDate,

    required this.occurredAt,

    required this.timeZone,

    required this.splitKind,

    required this.fxRate,

    required this.fxSource,

    required this.notes,

    required this.payers,

    required this.shares,

    required this.baseSeq,
  });

  @JsonKey(name: r'id', required: true, includeIfNull: false)
  final String id;

  @JsonKey(name: r'clientKey', required: true, includeIfNull: true)
  final String? clientKey;

  @JsonKey(
    name: r'kind',
    required: true,
    includeIfNull: false,
    unknownEnumValue: EntryKind.unknownDefaultOpenApi,
  )
  final EntryKind kind;

  @JsonKey(name: r'description', required: true, includeIfNull: false)
  final String description;

  @JsonKey(name: r'categoryId', required: true, includeIfNull: true)
  final String? categoryId;

  @JsonKey(name: r'currency', required: true, includeIfNull: false)
  final String currency;

  // minimum: 0
  @JsonKey(name: r'amountMinor', required: true, includeIfNull: false)
  final int amountMinor;

  @JsonKey(name: r'entryDate', required: true, includeIfNull: false)
  final String entryDate;

  @JsonKey(name: r'occurredAt', required: true, includeIfNull: true)
  final DateTime? occurredAt;

  @JsonKey(name: r'timeZone', required: true, includeIfNull: true)
  final String? timeZone;

  @JsonKey(
    name: r'splitKind',
    required: true,
    includeIfNull: false,
    unknownEnumValue: SplitKind.unknownDefaultOpenApi,
  )
  final SplitKind splitKind;

  // minimum: 0
  @JsonKey(name: r'fxRate', required: true, includeIfNull: true)
  final num? fxRate;

  @JsonKey(name: r'fxSource', required: true, includeIfNull: true)
  final String? fxSource;

  @JsonKey(name: r'notes', required: true, includeIfNull: true)
  final String? notes;

  @JsonKey(name: r'payers', required: true, includeIfNull: false)
  final List<Payer> payers;

  @JsonKey(name: r'shares', required: true, includeIfNull: false)
  final List<Share> shares;

  // minimum: 0
  @JsonKey(name: r'baseSeq', required: true, includeIfNull: true)
  final int? baseSeq;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is EntryInput &&
          other.id == id &&
          other.clientKey == clientKey &&
          other.kind == kind &&
          other.description == description &&
          other.categoryId == categoryId &&
          other.currency == currency &&
          other.amountMinor == amountMinor &&
          other.entryDate == entryDate &&
          other.occurredAt == occurredAt &&
          other.timeZone == timeZone &&
          other.splitKind == splitKind &&
          other.fxRate == fxRate &&
          other.fxSource == fxSource &&
          other.notes == notes &&
          other.payers == payers &&
          other.shares == shares &&
          other.baseSeq == baseSeq;

  @override
  int get hashCode =>
      id.hashCode +
      (clientKey == null ? 0 : clientKey.hashCode) +
      kind.hashCode +
      description.hashCode +
      (categoryId == null ? 0 : categoryId.hashCode) +
      currency.hashCode +
      amountMinor.hashCode +
      entryDate.hashCode +
      (occurredAt == null ? 0 : occurredAt.hashCode) +
      (timeZone == null ? 0 : timeZone.hashCode) +
      splitKind.hashCode +
      (fxRate == null ? 0 : fxRate.hashCode) +
      (fxSource == null ? 0 : fxSource.hashCode) +
      (notes == null ? 0 : notes.hashCode) +
      payers.hashCode +
      shares.hashCode +
      (baseSeq == null ? 0 : baseSeq.hashCode);

  factory EntryInput.fromJson(Map<String, dynamic> json) =>
      _$EntryInputFromJson(json);

  Map<String, dynamic> toJson() => _$EntryInputToJson(this);

  @override
  String toString() {
    return toJson().toString();
  }
}
