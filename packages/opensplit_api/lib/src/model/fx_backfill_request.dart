//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:json_annotation/json_annotation.dart';

part 'fx_backfill_request.g.dart';

@JsonSerializable(
  checked: true,
  createToJson: true,
  disallowUnrecognizedKeys: false,
  explicitToJson: true,
)
class FxBackfillRequest {
  /// Returns a new [FxBackfillRequest] instance.
  FxBackfillRequest({required this.asOf, required this.currency});

  @JsonKey(name: r'asOf', required: true, includeIfNull: false)
  final String asOf;

  @JsonKey(name: r'currency', required: true, includeIfNull: false)
  final String currency;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FxBackfillRequest &&
          other.asOf == asOf &&
          other.currency == currency;

  @override
  int get hashCode => asOf.hashCode + currency.hashCode;

  factory FxBackfillRequest.fromJson(Map<String, dynamic> json) =>
      _$FxBackfillRequestFromJson(json);

  Map<String, dynamic> toJson() => _$FxBackfillRequestToJson(this);

  @override
  String toString() {
    return toJson().toString();
  }
}
