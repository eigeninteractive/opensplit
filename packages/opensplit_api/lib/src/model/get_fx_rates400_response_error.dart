//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:json_annotation/json_annotation.dart';

part 'get_fx_rates400_response_error.g.dart';

@JsonSerializable(
  checked: true,
  createToJson: true,
  disallowUnrecognizedKeys: false,
  explicitToJson: true,
)
class GetFxRates400ResponseError {
  /// Returns a new [GetFxRates400ResponseError] instance.
  GetFxRates400ResponseError({
    required this.code,

    required this.message,

    required this.retry,
  });

  @JsonKey(name: r'code', required: true, includeIfNull: false)
  final String code;

  @JsonKey(name: r'message', required: true, includeIfNull: false)
  final String message;

  @JsonKey(name: r'retry', required: true, includeIfNull: false)
  final String retry;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is GetFxRates400ResponseError &&
          other.code == code &&
          other.message == message &&
          other.retry == retry;

  @override
  int get hashCode => code.hashCode + message.hashCode + retry.hashCode;

  factory GetFxRates400ResponseError.fromJson(Map<String, dynamic> json) =>
      _$GetFxRates400ResponseErrorFromJson(json);

  Map<String, dynamic> toJson() => _$GetFxRates400ResponseErrorToJson(this);

  @override
  String toString() {
    return toJson().toString();
  }
}
