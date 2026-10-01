//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:json_annotation/json_annotation.dart';

part 'group_link.g.dart';

@JsonSerializable(
  checked: true,
  createToJson: true,
  disallowUnrecognizedKeys: false,
  explicitToJson: true,
)
class GroupLink {
  /// Returns a new [GroupLink] instance.
  GroupLink({required this.token, required this.expiresAt});

  @JsonKey(name: r'token', required: true, includeIfNull: false)
  final String token;

  @JsonKey(name: r'expiresAt', required: true, includeIfNull: false)
  final DateTime expiresAt;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is GroupLink &&
          other.token == token &&
          other.expiresAt == expiresAt;

  @override
  int get hashCode => token.hashCode + expiresAt.hashCode;

  factory GroupLink.fromJson(Map<String, dynamic> json) =>
      _$GroupLinkFromJson(json);

  Map<String, dynamic> toJson() => _$GroupLinkToJson(this);

  @override
  String toString() {
    return toJson().toString();
  }
}
