// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'profile.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

Profile _$ProfileFromJson(Map<String, dynamic> json) =>
    $checkedCreate('Profile', json, ($checkedConvert) {
      $checkKeys(
        json,
        requiredKeys: const [
          'id',
          'displayName',
          'upiVpa',
          'avatarKind',
          'avatarColor',
          'avatarEmoji',
          'avatarIcon',
          'avatarPhoto',
          'updatedAt',
          'deletedAt',
        ],
      );
      final val = Profile(
        id: $checkedConvert('id', (v) => v as String),
        displayName: $checkedConvert('displayName', (v) => v as String?),
        upiVpa: $checkedConvert('upiVpa', (v) => v as String?),
        avatarKind: $checkedConvert(
          'avatarKind',
          (v) => $enumDecode(
            _$AvatarKindEnumMap,
            v,
            unknownValue: AvatarKind.unknownDefaultOpenApi,
          ),
        ),
        avatarColor: $checkedConvert(
          'avatarColor',
          (v) => $enumDecodeNullable(
            _$AvatarColorEnumMap,
            v,
            unknownValue: AvatarColor.unknownDefaultOpenApi,
          ),
        ),
        avatarEmoji: $checkedConvert('avatarEmoji', (v) => v as String?),
        avatarIcon: $checkedConvert(
          'avatarIcon',
          (v) => $enumDecodeNullable(
            _$AvatarIconEnumMap,
            v,
            unknownValue: AvatarIcon.unknownDefaultOpenApi,
          ),
        ),
        avatarPhoto: $checkedConvert('avatarPhoto', (v) => v as String?),
        updatedAt: $checkedConvert(
          'updatedAt',
          (v) => DateTime.parse(v as String),
        ),
        deletedAt: $checkedConvert(
          'deletedAt',
          (v) => v == null ? null : DateTime.parse(v as String),
        ),
      );
      return val;
    });

Map<String, dynamic> _$ProfileToJson(Profile instance) => <String, dynamic>{
  'id': instance.id,
  'displayName': instance.displayName,
  'upiVpa': instance.upiVpa,
  'avatarKind': _$AvatarKindEnumMap[instance.avatarKind]!,
  'avatarColor': _$AvatarColorEnumMap[instance.avatarColor],
  'avatarEmoji': instance.avatarEmoji,
  'avatarIcon': _$AvatarIconEnumMap[instance.avatarIcon],
  'avatarPhoto': instance.avatarPhoto,
  'updatedAt': instance.updatedAt.toIso8601String(),
  'deletedAt': instance.deletedAt?.toIso8601String(),
};

const _$AvatarKindEnumMap = {
  AvatarKind.initials: 'initials',
  AvatarKind.emoji: 'emoji',
  AvatarKind.icon: 'icon',
  AvatarKind.photo: 'photo',
  AvatarKind.unknownDefaultOpenApi: 'unknown_default_open_api',
};

const _$AvatarColorEnumMap = {
  AvatarColor.purple: 'purple',
  AvatarColor.blue: 'blue',
  AvatarColor.teal: 'teal',
  AvatarColor.green: 'green',
  AvatarColor.olive: 'olive',
  AvatarColor.amber: 'amber',
  AvatarColor.orange: 'orange',
  AvatarColor.pink: 'pink',
  AvatarColor.unknownDefaultOpenApi: 'unknown_default_open_api',
};

const _$AvatarIconEnumMap = {
  AvatarIcon.flight: 'flight',
  AvatarIcon.luggage: 'luggage',
  AvatarIcon.beachAccess: 'beach_access',
  AvatarIcon.hiking: 'hiking',
  AvatarIcon.sailing: 'sailing',
  AvatarIcon.train: 'train',
  AvatarIcon.directionsCar: 'directions_car',
  AvatarIcon.home: 'home',
  AvatarIcon.apartment: 'apartment',
  AvatarIcon.restaurant: 'restaurant',
  AvatarIcon.localCafe: 'local_cafe',
  AvatarIcon.localBar: 'local_bar',
  AvatarIcon.celebration: 'celebration',
  AvatarIcon.cake: 'cake',
  AvatarIcon.sportsSoccer: 'sports_soccer',
  AvatarIcon.sportsCricket: 'sports_cricket',
  AvatarIcon.sportsBasketball: 'sports_basketball',
  AvatarIcon.fitnessCenter: 'fitness_center',
  AvatarIcon.musicNote: 'music_note',
  AvatarIcon.school: 'school',
  AvatarIcon.work: 'work',
  AvatarIcon.pets: 'pets',
  AvatarIcon.favorite: 'favorite',
  AvatarIcon.familyRestroom: 'family_restroom',
  AvatarIcon.unknownDefaultOpenApi: 'unknown_default_open_api',
};
