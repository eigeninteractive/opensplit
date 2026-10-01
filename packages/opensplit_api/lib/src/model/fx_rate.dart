//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:json_annotation/json_annotation.dart';

part 'fx_rate.g.dart';

@JsonSerializable(
  checked: true,
  createToJson: true,
  disallowUnrecognizedKeys: false,
  explicitToJson: true,
)
class FxRate {
  /// Returns a new [FxRate] instance.
  FxRate({
    required this.asOf,

    required this.currency,

    required this.rate,

    required this.source_,
  });

  @JsonKey(name: r'asOf', required: true, includeIfNull: false)
  final String asOf;

  @JsonKey(name: r'currency', required: true, includeIfNull: false)
  final String currency;

  // minimum: 0
  @JsonKey(name: r'rate', required: true, includeIfNull: false)
  final num rate;

  @JsonKey(name: r'source', required: true, includeIfNull: false)
  final String source_;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FxRate &&
          other.asOf == asOf &&
          other.currency == currency &&
          other.rate == rate &&
          other.source_ == source_;

  @override
  int get hashCode =>
      asOf.hashCode + currency.hashCode + rate.hashCode + source_.hashCode;

  factory FxRate.fromJson(Map<String, dynamic> json) => _$FxRateFromJson(json);

  Map<String, dynamic> toJson() => _$FxRateToJson(this);

  @override
  String toString() {
    return toJson().toString();
  }
}
