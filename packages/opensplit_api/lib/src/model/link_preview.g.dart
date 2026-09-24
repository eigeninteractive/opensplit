// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'link_preview.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

LinkPreview _$LinkPreviewFromJson(Map<String, dynamic> json) =>
    $checkedCreate('LinkPreview', json, ($checkedConvert) {
      $checkKeys(
        json,
        requiredKeys: const [
          'kind',
          'groupId',
          'groupName',
          'inviterName',
          'memberCount',
          'memberName',
          'isRedeemed',
          'isExpired',
          'isRevoked',
          'isMember',
        ],
      );
      final val = LinkPreview(
        kind: $checkedConvert(
          'kind',
          (v) => $enumDecode(
            _$LinkPreviewKindEnumEnumMap,
            v,
            unknownValue: LinkPreviewKindEnum.unknownDefaultOpenApi,
          ),
        ),
        groupId: $checkedConvert('groupId', (v) => v as String),
        groupName: $checkedConvert('groupName', (v) => v as String),
        inviterName: $checkedConvert('inviterName', (v) => v as String?),
        memberCount: $checkedConvert('memberCount', (v) => (v as num).toInt()),
        memberName: $checkedConvert('memberName', (v) => v as String?),
        isRedeemed: $checkedConvert('isRedeemed', (v) => v as bool),
        isExpired: $checkedConvert('isExpired', (v) => v as bool),
        isRevoked: $checkedConvert('isRevoked', (v) => v as bool),
        isMember: $checkedConvert('isMember', (v) => v as bool),
      );
      return val;
    });

Map<String, dynamic> _$LinkPreviewToJson(LinkPreview instance) =>
    <String, dynamic>{
      'kind': _$LinkPreviewKindEnumEnumMap[instance.kind]!,
      'groupId': instance.groupId,
      'groupName': instance.groupName,
      'inviterName': instance.inviterName,
      'memberCount': instance.memberCount,
      'memberName': instance.memberName,
      'isRedeemed': instance.isRedeemed,
      'isExpired': instance.isExpired,
      'isRevoked': instance.isRevoked,
      'isMember': instance.isMember,
    };

const _$LinkPreviewKindEnumEnumMap = {
  LinkPreviewKindEnum.invite: 'invite',
  LinkPreviewKindEnum.groupLink: 'group_link',
  LinkPreviewKindEnum.unknownDefaultOpenApi: 'unknown_default_open_api',
};
