//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:opensplit_api/src/model/money_row.dart';
import 'package:opensplit_api/src/model/split_kind.dart';
import 'package:opensplit_api/src/model/entry_kind.dart';
import 'package:json_annotation/json_annotation.dart';

part 'entry_snapshot.g.dart';

@JsonSerializable(
  checked: true,
  createToJson: true,
  disallowUnrecognizedKeys: false,
  explicitToJson: true,
)
class EntrySnapshot {
  /// Returns a new [EntrySnapshot] instance.
  EntrySnapshot({
    required this.kind,

    required this.description,

    required this.currency,

    required this.amountMinor,

    required this.entryDate,

    required this.splitKind,

    required this.categoryId,

    required this.notes,

    required this.deletedAt,

    required this.payers,

    required this.shares,
  });

  @JsonKey(
    name: r'kind',
    required: true,
    includeIfNull: false,
    unknownEnumValue: EntryKind.unknownDefaultOpenApi,
  )
  final EntryKind kind;

  @JsonKey(name: r'description', required: true, includeIfNull: false)
  final String description;

  @JsonKey(name: r'currency', required: true, includeIfNull: false)
  final String currency;

  // minimum: 0
  @JsonKey(name: r'amountMinor', required: true, includeIfNull: false)
  final int amountMinor;

  @JsonKey(name: r'entryDate', required: true, includeIfNull: false)
  final String entryDate;

  @JsonKey(
    name: r'splitKind',
    required: true,
    includeIfNull: false,
    unknownEnumValue: SplitKind.unknownDefaultOpenApi,
  )
  final SplitKind splitKind;

  @JsonKey(name: r'categoryId', required: true, includeIfNull: true)
  final String? categoryId;

  @JsonKey(name: r'notes', required: true, includeIfNull: true)
  final String? notes;

  @JsonKey(name: r'deletedAt', required: true, includeIfNull: true)
  final DateTime? deletedAt;

  @JsonKey(name: r'payers', required: true, includeIfNull: false)
  final List<MoneyRow> payers;

  @JsonKey(name: r'shares', required: true, includeIfNull: false)
  final List<MoneyRow> shares;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is EntrySnapshot &&
          other.kind == kind &&
          other.description == description &&
          other.currency == currency &&
          other.amountMinor == amountMinor &&
          other.entryDate == entryDate &&
          other.splitKind == splitKind &&
          other.categoryId == categoryId &&
          other.notes == notes &&
          other.deletedAt == deletedAt &&
          other.payers == payers &&
          other.shares == shares;

  @override
  int get hashCode =>
      kind.hashCode +
      description.hashCode +
      currency.hashCode +
      amountMinor.hashCode +
      entryDate.hashCode +
      splitKind.hashCode +
      (categoryId == null ? 0 : categoryId.hashCode) +
      (notes == null ? 0 : notes.hashCode) +
      (deletedAt == null ? 0 : deletedAt.hashCode) +
      payers.hashCode +
      shares.hashCode;

  factory EntrySnapshot.fromJson(Map<String, dynamic> json) =>
      _$EntrySnapshotFromJson(json);

  Map<String, dynamic> toJson() => _$EntrySnapshotToJson(this);

  @override
  String toString() {
    return toJson().toString();
  }
}
