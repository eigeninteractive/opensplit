//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:json_annotation/json_annotation.dart';

part 'account.g.dart';

@JsonSerializable(
  checked: true,
  createToJson: true,
  disallowUnrecognizedKeys: false,
  explicitToJson: true,
)
class Account {
  /// Returns a new [Account] instance.
  Account({
    required this.id,

    required this.isAnonymous,

    required this.email,

    required this.displayName,
  });

  @JsonKey(name: r'id', required: true, includeIfNull: false)
  final String id;

  @JsonKey(name: r'isAnonymous', required: true, includeIfNull: false)
  final bool isAnonymous;

  @JsonKey(name: r'email', required: true, includeIfNull: true)
  final String? email;

  @JsonKey(name: r'displayName', required: true, includeIfNull: true)
  final String? displayName;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Account &&
          other.id == id &&
          other.isAnonymous == isAnonymous &&
          other.email == email &&
          other.displayName == displayName;

  @override
  int get hashCode =>
      id.hashCode +
      isAnonymous.hashCode +
      (email == null ? 0 : email.hashCode) +
      (displayName == null ? 0 : displayName.hashCode);

  factory Account.fromJson(Map<String, dynamic> json) =>
      _$AccountFromJson(json);

  Map<String, dynamic> toJson() => _$AccountToJson(this);

  @override
  String toString() {
    return toJson().toString();
  }
}
