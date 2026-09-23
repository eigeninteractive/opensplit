//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:opensplit_api/src/model/account.dart';
import 'package:json_annotation/json_annotation.dart';

part 'identity_outcome_one_of.g.dart';

@JsonSerializable(
  checked: true,
  createToJson: true,
  disallowUnrecognizedKeys: false,
  explicitToJson: true,
)
class IdentityOutcomeOneOf {
  /// Returns a new [IdentityOutcomeOneOf] instance.
  IdentityOutcomeOneOf({
    required this.outcome,

    required this.account,

    required this.token,
  });

  @JsonKey(
    name: r'outcome',
    required: true,
    includeIfNull: false,
    unknownEnumValue: IdentityOutcomeOneOfOutcomeEnum.unknownDefaultOpenApi,
  )
  final IdentityOutcomeOneOfOutcomeEnum outcome;

  @JsonKey(name: r'account', required: true, includeIfNull: false)
  final Account account;

  @JsonKey(name: r'token', required: true, includeIfNull: true)
  final String? token;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is IdentityOutcomeOneOf &&
          other.outcome == outcome &&
          other.account == account &&
          other.token == token;

  @override
  int get hashCode =>
      outcome.hashCode +
      account.hashCode +
      (token == null ? 0 : token.hashCode);

  factory IdentityOutcomeOneOf.fromJson(Map<String, dynamic> json) =>
      _$IdentityOutcomeOneOfFromJson(json);

  Map<String, dynamic> toJson() => _$IdentityOutcomeOneOfToJson(this);

  @override
  String toString() {
    return toJson().toString();
  }
}

enum IdentityOutcomeOneOfOutcomeEnum {
  @JsonValue(r'kept')
  kept(r'kept'),
  @JsonValue(r'unknown_default_open_api')
  unknownDefaultOpenApi(r'unknown_default_open_api');

  const IdentityOutcomeOneOfOutcomeEnum(this.value);

  final String value;

  @override
  String toString() => value;
}
