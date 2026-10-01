//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:json_annotation/json_annotation.dart';

part 'reauth_start.g.dart';

@JsonSerializable(
  checked: true,
  createToJson: true,
  disallowUnrecognizedKeys: false,
  explicitToJson: true,
)
class ReauthStart {
  /// Returns a new [ReauthStart] instance.
  ReauthStart({required this.email});

  @JsonKey(name: r'email', required: true, includeIfNull: false)
  final String email;

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is ReauthStart && other.email == email;

  @override
  int get hashCode => email.hashCode;

  factory ReauthStart.fromJson(Map<String, dynamic> json) =>
      _$ReauthStartFromJson(json);

  Map<String, dynamic> toJson() => _$ReauthStartToJson(this);

  @override
  String toString() {
    return toJson().toString();
  }
}
