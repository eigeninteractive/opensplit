// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'profile_page.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

ProfilePage _$ProfilePageFromJson(Map<String, dynamic> json) =>
    $checkedCreate('ProfilePage', json, ($checkedConvert) {
      $checkKeys(json, requiredKeys: const ['profiles', 'seq', 'hasMore']);
      final val = ProfilePage(
        profiles: $checkedConvert(
          'profiles',
          (v) => (v as List<dynamic>)
              .map((e) => Profile.fromJson(e as Map<String, dynamic>))
              .toList(),
        ),
        seq: $checkedConvert('seq', (v) => (v as num).toInt()),
        hasMore: $checkedConvert('hasMore', (v) => v as bool),
      );
      return val;
    });

Map<String, dynamic> _$ProfilePageToJson(ProfilePage instance) =>
    <String, dynamic>{
      'profiles': instance.profiles.map((e) => e.toJson()).toList(),
      'seq': instance.seq,
      'hasMore': instance.hasMore,
    };
