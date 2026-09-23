//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:opensplit_api/src/model/account.dart';
import 'package:json_annotation/json_annotation.dart';

part 'identity_outcome_one_of1.g.dart';

@JsonSerializable(
  checked: true,
  createToJson: true,
  disallowUnrecognizedKeys: false,
  explicitToJson: true,
)
class IdentityOutcomeOneOf1 {
  /// Returns a new [IdentityOutcomeOneOf1] instance.
  IdentityOutcomeOneOf1({
    required this.outcome,

    required this.account,

    required this.token,

    required this.strandedUserId,
  });

  @JsonKey(
    name: r'outcome',
    required: true,
    includeIfNull: false,
    unknownEnumValue: IdentityOutcomeOneOf1OutcomeEnum.unknownDefaultOpenApi,
  )
  final IdentityOutcomeOneOf1OutcomeEnum outcome;

  @JsonKey(name: r'account', required: true, includeIfNull: false)
  final Account account;

  @JsonKey(name: r'token', required: true, includeIfNull: true)
  final String? token;

  @JsonKey(name: r'strandedUserId', required: true, includeIfNull: false)
  final String strandedUserId;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is IdentityOutcomeOneOf1 &&
          other.outcome == outcome &&
          other.account == account &&
          other.token == token &&
          other.strandedUserId == strandedUserId;

  @override
  int get hashCode =>
      outcome.hashCode +
      account.hashCode +
      (token == null ? 0 : token.hashCode) +
      strandedUserId.hashCode;

  factory IdentityOutcomeOneOf1.fromJson(Map<String, dynamic> json) =>
      _$IdentityOutcomeOneOf1FromJson(json);

  Map<String, dynamic> toJson() => _$IdentityOutcomeOneOf1ToJson(this);

  @override
  String toString() {
    return toJson().toString();
  }
}

enum IdentityOutcomeOneOf1OutcomeEnum {
  @JsonValue(r'replaced')
  replaced(r'replaced'),
  @JsonValue(r'unknown_default_open_api')
  unknownDefaultOpenApi(r'unknown_default_open_api');

  const IdentityOutcomeOneOf1OutcomeEnum(this.value);

  final String value;

  @override
  String toString() => value;
}
