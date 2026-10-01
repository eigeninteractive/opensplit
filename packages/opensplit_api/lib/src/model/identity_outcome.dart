//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:opensplit_api/src/model/account.dart';
import 'package:opensplit_api/src/model/identity_outcome_kind.dart';
import 'package:json_annotation/json_annotation.dart';

part 'identity_outcome.g.dart';

@JsonSerializable(
  checked: true,
  createToJson: true,
  disallowUnrecognizedKeys: false,
  explicitToJson: true,
)
class IdentityOutcome {
  /// Returns a new [IdentityOutcome] instance.
  IdentityOutcome({
    required this.outcome,

    required this.account,

    required this.token,

    required this.strandedUserId,
  });

  @JsonKey(
    name: r'outcome',
    required: true,
    includeIfNull: false,
    unknownEnumValue: IdentityOutcomeKind.unknownDefaultOpenApi,
  )
  final IdentityOutcomeKind outcome;

  @JsonKey(name: r'account', required: true, includeIfNull: false)
  final Account account;

  @JsonKey(name: r'token', required: true, includeIfNull: true)
  final String? token;

  @JsonKey(name: r'strandedUserId', required: true, includeIfNull: true)
  final String? strandedUserId;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is IdentityOutcome &&
          other.outcome == outcome &&
          other.account == account &&
          other.token == token &&
          other.strandedUserId == strandedUserId;

  @override
  int get hashCode =>
      outcome.hashCode +
      account.hashCode +
      (token == null ? 0 : token.hashCode) +
      (strandedUserId == null ? 0 : strandedUserId.hashCode);

  factory IdentityOutcome.fromJson(Map<String, dynamic> json) =>
      _$IdentityOutcomeFromJson(json);

  Map<String, dynamic> toJson() => _$IdentityOutcomeToJson(this);

  @override
  String toString() {
    return toJson().toString();
  }
}
