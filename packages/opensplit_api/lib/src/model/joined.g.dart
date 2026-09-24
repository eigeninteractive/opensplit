// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'joined.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

Joined _$JoinedFromJson(Map<String, dynamic> json) =>
    $checkedCreate('Joined', json, ($checkedConvert) {
      $checkKeys(json, requiredKeys: const ['groupId', 'member']);
      final val = Joined(
        groupId: $checkedConvert('groupId', (v) => v as String),
        member: $checkedConvert(
          'member',
          (v) => Member.fromJson(v as Map<String, dynamic>),
        ),
      );
      return val;
    });

Map<String, dynamic> _$JoinedToJson(Joined instance) => <String, dynamic>{
  'groupId': instance.groupId,
  'member': instance.member.toJson(),
};
