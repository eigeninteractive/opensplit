// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'profile_page.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

ProfilePage _$ProfilePageFromJson(Map<String, dynamic> json) =>
    $checkedCreate('ProfilePage', json, ($checkedConvert) {
      $checkKeys(
        json,
        requiredKeys: const ['profiles', 'cursor', 'cursorId', 'hasMore'],
      );
      final val = ProfilePage(
        profiles: $checkedConvert(
          'profiles',
          (v) => (v as List<dynamic>)
              .map((e) => Profile.fromJson(e as Map<String, dynamic>))
              .toList(),
        ),
        cursor: $checkedConvert(
          'cursor',
          (v) => v == null ? null : DateTime.parse(v as String),
        ),
        cursorId: $checkedConvert('cursorId', (v) => v as String?),
        hasMore: $checkedConvert('hasMore', (v) => v as bool),
      );
      return val;
    });

Map<String, dynamic> _$ProfilePageToJson(ProfilePage instance) =>
    <String, dynamic>{
      'profiles': instance.profiles.map((e) => e.toJson()).toList(),
      'cursor': instance.cursor?.toIso8601String(),
      'cursorId': instance.cursorId,
      'hasMore': instance.hasMore,
    };
