// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'identity_outcome_one_of1.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

IdentityOutcomeOneOf1 _$IdentityOutcomeOneOf1FromJson(
  Map<String, dynamic> json,
) => $checkedCreate('IdentityOutcomeOneOf1', json, ($checkedConvert) {
  $checkKeys(
    json,
    requiredKeys: const ['outcome', 'account', 'token', 'strandedUserId'],
  );
  final val = IdentityOutcomeOneOf1(
    outcome: $checkedConvert(
      'outcome',
      (v) => $enumDecode(
        _$IdentityOutcomeOneOf1OutcomeEnumEnumMap,
        v,
        unknownValue: IdentityOutcomeOneOf1OutcomeEnum.unknownDefaultOpenApi,
      ),
    ),
    account: $checkedConvert(
      'account',
      (v) => Account.fromJson(v as Map<String, dynamic>),
    ),
    token: $checkedConvert('token', (v) => v as String?),
    strandedUserId: $checkedConvert('strandedUserId', (v) => v as String),
  );
  return val;
});

Map<String, dynamic> _$IdentityOutcomeOneOf1ToJson(
  IdentityOutcomeOneOf1 instance,
) => <String, dynamic>{
  'outcome': _$IdentityOutcomeOneOf1OutcomeEnumEnumMap[instance.outcome]!,
  'account': instance.account.toJson(),
  'token': instance.token,
  'strandedUserId': instance.strandedUserId,
};

const _$IdentityOutcomeOneOf1OutcomeEnumEnumMap = {
  IdentityOutcomeOneOf1OutcomeEnum.replaced: 'replaced',
  IdentityOutcomeOneOf1OutcomeEnum.unknownDefaultOpenApi:
      'unknown_default_open_api',
};
