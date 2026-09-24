//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:opensplit_api/src/model/get_fx_rates400_response_error.dart';
import 'package:json_annotation/json_annotation.dart';

part 'get_fx_rates400_response.g.dart';

@JsonSerializable(
  checked: true,
  createToJson: true,
  disallowUnrecognizedKeys: false,
  explicitToJson: true,
)
class GetFxRates400Response {
  /// Returns a new [GetFxRates400Response] instance.
  GetFxRates400Response({required this.error});

  @JsonKey(name: r'error', required: true, includeIfNull: false)
  final GetFxRates400ResponseError error;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is GetFxRates400Response && other.error == error;

  @override
  int get hashCode => error.hashCode;

  factory GetFxRates400Response.fromJson(Map<String, dynamic> json) =>
      _$GetFxRates400ResponseFromJson(json);

  Map<String, dynamic> toJson() => _$GetFxRates400ResponseToJson(this);

  @override
  String toString() {
    return toJson().toString();
  }
}
