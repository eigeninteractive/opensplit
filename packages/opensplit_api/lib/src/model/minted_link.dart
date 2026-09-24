//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:json_annotation/json_annotation.dart';

part 'minted_link.g.dart';

@JsonSerializable(
  checked: true,
  createToJson: true,
  disallowUnrecognizedKeys: false,
  explicitToJson: true,
)
class MintedLink {
  /// Returns a new [MintedLink] instance.
  MintedLink({
    required this.token,

    required this.expiresAt,

    required this.superseded,
  });

  @JsonKey(name: r'token', required: true, includeIfNull: false)
  final String token;

  @JsonKey(name: r'expiresAt', required: true, includeIfNull: false)
  final DateTime expiresAt;

  @JsonKey(name: r'superseded', required: true, includeIfNull: true)
  final String? superseded;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MintedLink &&
          other.token == token &&
          other.expiresAt == expiresAt &&
          other.superseded == superseded;

  @override
  int get hashCode =>
      token.hashCode +
      expiresAt.hashCode +
      (superseded == null ? 0 : superseded.hashCode);

  factory MintedLink.fromJson(Map<String, dynamic> json) =>
      _$MintedLinkFromJson(json);

  Map<String, dynamic> toJson() => _$MintedLinkToJson(this);

  @override
  String toString() {
    return toJson().toString();
  }
}
