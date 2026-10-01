//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:json_annotation/json_annotation.dart';

part 'currency.g.dart';

@JsonSerializable(
  checked: true,
  createToJson: true,
  disallowUnrecognizedKeys: false,
  explicitToJson: true,
)
class Currency {
  /// Returns a new [Currency] instance.
  Currency({
    required this.code,

    required this.exponent,

    required this.symbol,

    required this.name,
  });

  @JsonKey(name: r'code', required: true, includeIfNull: false)
  final String code;

  // minimum: 0
  // maximum: 4
  @JsonKey(name: r'exponent', required: true, includeIfNull: false)
  final int exponent;

  @JsonKey(name: r'symbol', required: true, includeIfNull: true)
  final String? symbol;

  @JsonKey(name: r'name', required: true, includeIfNull: false)
  final String name;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Currency &&
          other.code == code &&
          other.exponent == exponent &&
          other.symbol == symbol &&
          other.name == name;

  @override
  int get hashCode =>
      code.hashCode +
      exponent.hashCode +
      (symbol == null ? 0 : symbol.hashCode) +
      name.hashCode;

  factory Currency.fromJson(Map<String, dynamic> json) =>
      _$CurrencyFromJson(json);

  Map<String, dynamic> toJson() => _$CurrencyToJson(this);

  @override
  String toString() {
    return toJson().toString();
  }
}
