// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'identity_outcome_one_of.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

IdentityOutcomeOneOf _$IdentityOutcomeOneOfFromJson(
  Map<String, dynamic> json,
) => $checkedCreate('IdentityOutcomeOneOf', json, ($checkedConvert) {
  $checkKeys(json, requiredKeys: const ['outcome', 'account', 'token']);
  final val = IdentityOutcomeOneOf(
    outcome: $checkedConvert(
      'outcome',
      (v) => $enumDecode(
        _$IdentityOutcomeOneOfOutcomeEnumEnumMap,
        v,
        unknownValue: IdentityOutcomeOneOfOutcomeEnum.unknownDefaultOpenApi,
      ),
    ),
    account: $checkedConvert(
      'account',
      (v) => Account.fromJson(v as Map<String, dynamic>),
    ),
    token: $checkedConvert('token', (v) => v as String?),
  );
  return val;
});

Map<String, dynamic> _$IdentityOutcomeOneOfToJson(
  IdentityOutcomeOneOf instance,
) => <String, dynamic>{
  'outcome': _$IdentityOutcomeOneOfOutcomeEnumEnumMap[instance.outcome]!,
  'account': instance.account.toJson(),
  'token': instance.token,
};

const _$IdentityOutcomeOneOfOutcomeEnumEnumMap = {
  IdentityOutcomeOneOfOutcomeEnum.kept: 'kept',
  IdentityOutcomeOneOfOutcomeEnum.unknownDefaultOpenApi:
      'unknown_default_open_api',
};
