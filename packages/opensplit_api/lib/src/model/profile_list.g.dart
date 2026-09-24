// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'profile_list.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

ProfileList _$ProfileListFromJson(Map<String, dynamic> json) =>
    $checkedCreate('ProfileList', json, ($checkedConvert) {
      $checkKeys(json, requiredKeys: const ['profiles']);
      final val = ProfileList(
        profiles: $checkedConvert(
          'profiles',
          (v) => (v as List<dynamic>)
              .map((e) => Profile.fromJson(e as Map<String, dynamic>))
              .toList(),
        ),
      );
      return val;
    });

Map<String, dynamic> _$ProfileListToJson(ProfileList instance) =>
    <String, dynamic>{
      'profiles': instance.profiles.map((e) => e.toJson()).toList(),
    };
