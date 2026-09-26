//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:json_annotation/json_annotation.dart';

part 'money_row.g.dart';

@JsonSerializable(
  checked: true,
  createToJson: true,
  disallowUnrecognizedKeys: false,
  explicitToJson: true,
)
class MoneyRow {
  /// Returns a new [MoneyRow] instance.
  MoneyRow({required this.memberId, required this.amountMinor});

  @JsonKey(name: r'memberId', required: true, includeIfNull: false)
  final String memberId;

  // minimum: 0
  @JsonKey(name: r'amountMinor', required: true, includeIfNull: false)
  final int amountMinor;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MoneyRow &&
          other.memberId == memberId &&
          other.amountMinor == amountMinor;

  @override
  int get hashCode => memberId.hashCode + amountMinor.hashCode;

  factory MoneyRow.fromJson(Map<String, dynamic> json) =>
      _$MoneyRowFromJson(json);

  Map<String, dynamic> toJson() => _$MoneyRowToJson(this);

  @override
  String toString() {
    return toJson().toString();
  }
}
