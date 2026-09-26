//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:opensplit_api/src/model/account.dart';
import 'package:json_annotation/json_annotation.dart';

part 'session.g.dart';

@JsonSerializable(
  checked: true,
  createToJson: true,
  disallowUnrecognizedKeys: false,
  explicitToJson: true,
)
class Session {
  /// Returns a new [Session] instance.
  Session({required this.account, required this.token});

  @JsonKey(name: r'account', required: true, includeIfNull: true)
  final Account? account;

  @JsonKey(name: r'token', required: true, includeIfNull: true)
  final String? token;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Session && other.account == account && other.token == token;

  @override
  int get hashCode =>
      (account == null ? 0 : account.hashCode) +
      (token == null ? 0 : token.hashCode);

  factory Session.fromJson(Map<String, dynamic> json) =>
      _$SessionFromJson(json);

  Map<String, dynamic> toJson() => _$SessionToJson(this);

  @override
  String toString() {
    return toJson().toString();
  }
}
