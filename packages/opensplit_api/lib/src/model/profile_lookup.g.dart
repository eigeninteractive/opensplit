// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'profile_lookup.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

ProfileLookup _$ProfileLookupFromJson(Map<String, dynamic> json) =>
    $checkedCreate('ProfileLookup', json, ($checkedConvert) {
      $checkKeys(json, requiredKeys: const ['ids']);
      final val = ProfileLookup(
        ids: $checkedConvert(
          'ids',
          (v) => (v as List<dynamic>).map((e) => e as String).toList(),
        ),
      );
      return val;
    });

Map<String, dynamic> _$ProfileLookupToJson(ProfileLookup instance) =>
    <String, dynamic>{'ids': instance.ids};
