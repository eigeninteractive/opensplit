// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'error_error.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

ErrorError _$ErrorErrorFromJson(Map<String, dynamic> json) =>
    $checkedCreate('ErrorError', json, ($checkedConvert) {
      $checkKeys(json, requiredKeys: const ['code', 'message', 'retry']);
      final val = ErrorError(
        code: $checkedConvert(
          'code',
          (v) => $enumDecode(
            _$ErrorCodeEnumMap,
            v,
            unknownValue: ErrorCode.unknownDefaultOpenApi,
          ),
        ),
        message: $checkedConvert('message', (v) => v as String),
        retry: $checkedConvert(
          'retry',
          (v) => $enumDecode(
            _$RetryEnumMap,
            v,
            unknownValue: Retry.unknownDefaultOpenApi,
          ),
        ),
      );
      return val;
    });

Map<String, dynamic> _$ErrorErrorToJson(ErrorError instance) =>
    <String, dynamic>{
      'code': _$ErrorCodeEnumMap[instance.code]!,
      'message': instance.message,
      'retry': _$RetryEnumMap[instance.retry]!,
    };

const _$ErrorCodeEnumMap = {
  ErrorCode.notMember: 'not_member',
  ErrorCode.noGroup: 'no_group',
  ErrorCode.groupPurged: 'group_purged',
  ErrorCode.groupExists: 'group_exists',
  ErrorCode.noSuchEntry: 'no_such_entry',
  ErrorCode.noSuchMember: 'no_such_member',
  ErrorCode.unbalanced: 'unbalanced',
  ErrorCode.staleBase: 'stale_base',
  ErrorCode.forbidden: 'forbidden',
  ErrorCode.notSettled: 'not_settled',
  ErrorCode.inviteInvalid: 'invite_invalid',
  ErrorCode.inviteSpent: 'invite_spent',
  ErrorCode.inviteExpired: 'invite_expired',
  ErrorCode.alreadyMember: 'already_member',
  ErrorCode.slotTaken: 'slot_taken',
  ErrorCode.malformed: 'malformed',
  ErrorCode.noSession: 'no_session',
  ErrorCode.notFound: 'not_found',
  ErrorCode.internal: 'internal',
  ErrorCode.identityAlreadyInUse: 'identity_already_in_use',
  ErrorCode.unknownDefaultOpenApi: 'unknown_default_open_api',
};

const _$RetryEnumMap = {
  Retry.stale: 'stale',
  Retry.permanent: 'permanent',
  Retry.transient: 'transient',
  Retry.unknownDefaultOpenApi: 'unknown_default_open_api',
};
