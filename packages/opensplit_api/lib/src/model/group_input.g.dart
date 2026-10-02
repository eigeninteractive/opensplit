// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'group_input.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

GroupInput _$GroupInputFromJson(Map<String, dynamic> json) =>
    $checkedCreate('GroupInput', json, ($checkedConvert) {
      $checkKeys(
        json,
        requiredKeys: const [
          'name',
          'defaultCurrency',
          'isDirect',
          'simplifyDebts',
          'archivedAt',
          'avatarKind',
          'avatarColor',
          'avatarEmoji',
          'avatarIcon',
          'avatarPhoto',
          'coverKind',
          'coverPhoto',
          'creatorId',
          'creatorName',
        ],
      );
      final val = GroupInput(
        name: $checkedConvert('name', (v) => v as String),
        defaultCurrency: $checkedConvert('defaultCurrency', (v) => v as String),
        isDirect: $checkedConvert('isDirect', (v) => v as bool),
        simplifyDebts: $checkedConvert('simplifyDebts', (v) => v as bool),
        archivedAt: $checkedConvert(
          'archivedAt',
          (v) => v == null ? null : DateTime.parse(v as String),
        ),
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
        coverKind: $checkedConvert(
          'coverKind',
          (v) => $enumDecode(
            _$CoverKindEnumMap,
            v,
            unknownValue: CoverKind.unknownDefaultOpenApi,
          ),
        ),
        coverPhoto: $checkedConvert('coverPhoto', (v) => v as String?),
        creatorId: $checkedConvert('creatorId', (v) => v as String),
        creatorName: $checkedConvert('creatorName', (v) => v as String),
      );
      return val;
    });

Map<String, dynamic> _$GroupInputToJson(GroupInput instance) =>
    <String, dynamic>{
      'name': instance.name,
      'defaultCurrency': instance.defaultCurrency,
      'isDirect': instance.isDirect,
      'simplifyDebts': instance.simplifyDebts,
      'archivedAt': instance.archivedAt?.toIso8601String(),
      'avatarKind': _$AvatarKindEnumMap[instance.avatarKind]!,
      'avatarColor': _$AvatarColorEnumMap[instance.avatarColor],
      'avatarEmoji': instance.avatarEmoji,
      'avatarIcon': _$AvatarIconEnumMap[instance.avatarIcon],
      'avatarPhoto': instance.avatarPhoto,
      'coverKind': _$CoverKindEnumMap[instance.coverKind]!,
      'coverPhoto': instance.coverPhoto,
      'creatorId': instance.creatorId,
      'creatorName': instance.creatorName,
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

const _$CoverKindEnumMap = {
  CoverKind.generated: 'generated',
  CoverKind.photo: 'photo',
  CoverKind.unknownDefaultOpenApi: 'unknown_default_open_api',
};
