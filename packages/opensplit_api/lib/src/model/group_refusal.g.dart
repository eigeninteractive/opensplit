// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'group_refusal.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

GroupRefusal _$GroupRefusalFromJson(Map<String, dynamic> json) =>
    $checkedCreate('GroupRefusal', json, ($checkedConvert) {
      $checkKeys(json, requiredKeys: const ['groupId', 'code', 'message']);
      final val = GroupRefusal(
        groupId: $checkedConvert('groupId', (v) => v as String),
        code: $checkedConvert(
          'code',
          (v) => $enumDecode(
            _$ErrorCodeEnumMap,
            v,
            unknownValue: ErrorCode.unknownDefaultOpenApi,
          ),
        ),
        message: $checkedConvert('message', (v) => v as String),
      );
      return val;
    });

Map<String, dynamic> _$GroupRefusalToJson(GroupRefusal instance) =>
    <String, dynamic>{
      'groupId': instance.groupId,
      'code': _$ErrorCodeEnumMap[instance.code]!,
      'message': instance.message,
    };

const _$ErrorCodeEnumMap = {
  ErrorCode.notMember: 'not_member',
  ErrorCode.noGroup: 'no_group',
  ErrorCode.groupPurged: 'group_purged',
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
  ErrorCode.authFailed: 'auth_failed',
  ErrorCode.rateLimited: 'rate_limited',
  ErrorCode.reauthRequired: 'reauth_required',
  ErrorCode.unknownDefaultOpenApi: 'unknown_default_open_api',
};
