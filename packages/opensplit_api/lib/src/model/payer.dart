//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:json_annotation/json_annotation.dart';

part 'payer.g.dart';

@JsonSerializable(
  checked: true,
  createToJson: true,
  disallowUnrecognizedKeys: false,
  explicitToJson: true,
)
class Payer {
  /// Returns a new [Payer] instance.
  Payer({required this.memberId, required this.amountMinor});

  @JsonKey(name: r'memberId', required: true, includeIfNull: false)
  final String memberId;

  // minimum: 0
  @JsonKey(name: r'amountMinor', required: true, includeIfNull: false)
  final int amountMinor;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Payer &&
          other.memberId == memberId &&
          other.amountMinor == amountMinor;

  @override
  int get hashCode => memberId.hashCode + amountMinor.hashCode;

  factory Payer.fromJson(Map<String, dynamic> json) => _$PayerFromJson(json);

  Map<String, dynamic> toJson() => _$PayerToJson(this);

  @override
  String toString() {
    return toJson().toString();
  }
}
