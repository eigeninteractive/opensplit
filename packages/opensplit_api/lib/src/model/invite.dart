//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:json_annotation/json_annotation.dart';

part 'invite.g.dart';

@JsonSerializable(
  checked: true,
  createToJson: true,
  disallowUnrecognizedKeys: false,
  explicitToJson: true,
)
class Invite {
  /// Returns a new [Invite] instance.
  Invite({
    required this.token,

    required this.memberId,

    required this.createdBy,

    required this.createdAt,

    required this.expiresAt,

    required this.redeemedAt,

    required this.redeemedBy,
  });

  @JsonKey(name: r'token', required: true, includeIfNull: false)
  final String token;

  @JsonKey(name: r'memberId', required: true, includeIfNull: false)
  final String memberId;

  @JsonKey(name: r'createdBy', required: true, includeIfNull: false)
  final String createdBy;

  @JsonKey(name: r'createdAt', required: true, includeIfNull: false)
  final DateTime createdAt;

  @JsonKey(name: r'expiresAt', required: true, includeIfNull: false)
  final DateTime expiresAt;

  @JsonKey(name: r'redeemedAt', required: true, includeIfNull: true)
  final DateTime? redeemedAt;

  @JsonKey(name: r'redeemedBy', required: true, includeIfNull: true)
  final String? redeemedBy;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Invite &&
          other.token == token &&
          other.memberId == memberId &&
          other.createdBy == createdBy &&
          other.createdAt == createdAt &&
          other.expiresAt == expiresAt &&
          other.redeemedAt == redeemedAt &&
          other.redeemedBy == redeemedBy;

  @override
  int get hashCode =>
      token.hashCode +
      memberId.hashCode +
      createdBy.hashCode +
      createdAt.hashCode +
      expiresAt.hashCode +
      (redeemedAt == null ? 0 : redeemedAt.hashCode) +
      (redeemedBy == null ? 0 : redeemedBy.hashCode);

  factory Invite.fromJson(Map<String, dynamic> json) => _$InviteFromJson(json);

  Map<String, dynamic> toJson() => _$InviteToJson(this);

  @override
  String toString() {
    return toJson().toString();
  }
}
