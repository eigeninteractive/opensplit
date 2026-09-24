//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:opensplit_api/src/model/account.dart';
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

  /// kept: the account id did not change, so nothing on the device has to move. replaced: a different account holds the session now, and `strandedUserId` names the one this device's ledger stays with.
  @JsonKey(
    name: r'outcome',
    required: true,
    includeIfNull: false,
    unknownEnumValue: IdentityOutcomeOutcomeEnum.unknownDefaultOpenApi,
  )
  final IdentityOutcomeOutcomeEnum outcome;

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

/// kept: the account id did not change, so nothing on the device has to move. replaced: a different account holds the session now, and `strandedUserId` names the one this device's ledger stays with.
enum IdentityOutcomeOutcomeEnum {
  @JsonValue(r'kept')
  kept(r'kept'),
  @JsonValue(r'replaced')
  replaced(r'replaced'),
  @JsonValue(r'unknown_default_open_api')
  unknownDefaultOpenApi(r'unknown_default_open_api');

  const IdentityOutcomeOutcomeEnum(this.value);

  final String value;

  @override
  String toString() => value;
}
