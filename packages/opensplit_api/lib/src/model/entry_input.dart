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

    this.kind,

    this.description = '',

    this.categoryId,

    required this.currency,

    required this.amountMinor,

    required this.entryDate,

    this.splitKind,

    this.fxRate,

    this.fxSource,

    this.notes,

    this.clientKey,

    required this.payers,

    required this.shares,

    this.baseSeq,
  });

  @JsonKey(name: r'id', required: true, includeIfNull: false)
  final String id;

  @JsonKey(
    name: r'kind',
    required: false,
    includeIfNull: false,
    unknownEnumValue: EntryKind.unknownDefaultOpenApi,
  )
  final EntryKind? kind;

  @JsonKey(
    defaultValue: '',
    name: r'description',
    required: false,
    includeIfNull: false,
  )
  final String? description;

  @JsonKey(name: r'categoryId', required: false, includeIfNull: false)
  final String? categoryId;

  @JsonKey(name: r'currency', required: true, includeIfNull: false)
  final String currency;

  // minimum: 0
  @JsonKey(name: r'amountMinor', required: true, includeIfNull: false)
  final int amountMinor;

  @JsonKey(name: r'entryDate', required: true, includeIfNull: false)
  final String entryDate;

  @JsonKey(
    name: r'splitKind',
    required: false,
    includeIfNull: false,
    unknownEnumValue: SplitKind.unknownDefaultOpenApi,
  )
  final SplitKind? splitKind;

  // minimum: 0
  @JsonKey(name: r'fxRate', required: false, includeIfNull: false)
  final num? fxRate;

  @JsonKey(name: r'fxSource', required: false, includeIfNull: false)
  final String? fxSource;

  @JsonKey(name: r'notes', required: false, includeIfNull: false)
  final String? notes;

  @JsonKey(name: r'clientKey', required: false, includeIfNull: false)
  final String? clientKey;

  @JsonKey(name: r'payers', required: true, includeIfNull: false)
  final List<Payer> payers;

  @JsonKey(name: r'shares', required: true, includeIfNull: false)
  final List<Share> shares;

  // minimum: 0
  @JsonKey(name: r'baseSeq', required: false, includeIfNull: false)
  final int? baseSeq;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is EntryInput &&
          other.id == id &&
          other.kind == kind &&
          other.description == description &&
          other.categoryId == categoryId &&
          other.currency == currency &&
          other.amountMinor == amountMinor &&
          other.entryDate == entryDate &&
          other.splitKind == splitKind &&
          other.fxRate == fxRate &&
          other.fxSource == fxSource &&
          other.notes == notes &&
          other.clientKey == clientKey &&
          other.payers == payers &&
          other.shares == shares &&
          other.baseSeq == baseSeq;

  @override
  int get hashCode =>
      id.hashCode +
      kind.hashCode +
      description.hashCode +
      (categoryId == null ? 0 : categoryId.hashCode) +
      currency.hashCode +
      amountMinor.hashCode +
      entryDate.hashCode +
      splitKind.hashCode +
      (fxRate == null ? 0 : fxRate.hashCode) +
      (fxSource == null ? 0 : fxSource.hashCode) +
      (notes == null ? 0 : notes.hashCode) +
      (clientKey == null ? 0 : clientKey.hashCode) +
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
