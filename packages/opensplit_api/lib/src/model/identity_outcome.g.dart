// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'identity_outcome.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

IdentityOutcome _$IdentityOutcomeFromJson(Map<String, dynamic> json) =>
    $checkedCreate('IdentityOutcome', json, ($checkedConvert) {
      $checkKeys(
        json,
        requiredKeys: const ['outcome', 'account', 'token', 'strandedUserId'],
      );
      final val = IdentityOutcome(
        outcome: $checkedConvert(
          'outcome',
          (v) => $enumDecode(
            _$IdentityOutcomeOutcomeEnumEnumMap,
            v,
            unknownValue: IdentityOutcomeOutcomeEnum.unknownDefaultOpenApi,
          ),
        ),
        account: $checkedConvert(
          'account',
          (v) => Account.fromJson(v as Map<String, dynamic>),
        ),
        token: $checkedConvert('token', (v) => v as String?),
        strandedUserId: $checkedConvert('strandedUserId', (v) => v as String?),
      );
      return val;
    });

Map<String, dynamic> _$IdentityOutcomeToJson(IdentityOutcome instance) =>
    <String, dynamic>{
      'outcome': _$IdentityOutcomeOutcomeEnumEnumMap[instance.outcome]!,
      'account': instance.account.toJson(),
      'token': instance.token,
      'strandedUserId': instance.strandedUserId,
    };

const _$IdentityOutcomeOutcomeEnumEnumMap = {
  IdentityOutcomeOutcomeEnum.kept: 'kept',
  IdentityOutcomeOutcomeEnum.replaced: 'replaced',
  IdentityOutcomeOutcomeEnum.unknownDefaultOpenApi: 'unknown_default_open_api',
};
