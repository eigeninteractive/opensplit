//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:json_annotation/json_annotation.dart';

part 'invite_superseded_inner.g.dart';

@JsonSerializable(
  checked: true,
  createToJson: true,
  disallowUnrecognizedKeys: false,
  explicitToJson: true,
)
class InviteSupersededInner {
  /// Returns a new [InviteSupersededInner] instance.
  InviteSupersededInner({required this.token});

  @JsonKey(name: r'token', required: true, includeIfNull: false)
  final String token;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is InviteSupersededInner && other.token == token;

  @override
  int get hashCode => token.hashCode;

  factory InviteSupersededInner.fromJson(Map<String, dynamic> json) =>
      _$InviteSupersededInnerFromJson(json);

  Map<String, dynamic> toJson() => _$InviteSupersededInnerToJson(this);

  @override
  String toString() {
    return toJson().toString();
  }
}
