//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:json_annotation/json_annotation.dart';

part 'fx_backfill_response.g.dart';

@JsonSerializable(
  checked: true,
  createToJson: true,
  disallowUnrecognizedKeys: false,
  explicitToJson: true,
)
class FxBackfillResponse {
  /// Returns a new [FxBackfillResponse] instance.
  FxBackfillResponse({required this.accepted});

  @JsonKey(name: r'accepted', required: true, includeIfNull: false)
  final bool accepted;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FxBackfillResponse && other.accepted == accepted;

  @override
  int get hashCode => accepted.hashCode;

  factory FxBackfillResponse.fromJson(Map<String, dynamic> json) =>
      _$FxBackfillResponseFromJson(json);

  Map<String, dynamic> toJson() => _$FxBackfillResponseToJson(this);

  @override
  String toString() {
    return toJson().toString();
  }
}
