// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'group.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

Group _$GroupFromJson(
  Map<String, dynamic> json,
) => $checkedCreate('Group', json, ($checkedConvert) {
  $checkKeys(
    json,
    requiredKeys: const [
      'id',
      'name',
      'defaultCurrency',
      'isDirect',
      'simplifyDebts',
      'avatarKind',
      'avatarColor',
      'avatarEmoji',
      'avatarIcon',
      'avatarPhoto',
      'coverKind',
      'coverPhoto',
      'createdBy',
      'createdAt',
      'lastActivityAt',
      'archivedAt',
      'updatedAt',
      'seq',
    ],
  );
  final val = Group(
    id: $checkedConvert('id', (v) => v as String),
    name: $checkedConvert('name', (v) => v as String),
    defaultCurrency: $checkedConvert('defaultCurrency', (v) => v as String),
    isDirect: $checkedConvert('isDirect', (v) => v as bool),
    simplifyDebts: $checkedConvert('simplifyDebts', (v) => v as bool),
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
    createdBy: $checkedConvert('createdBy', (v) => v as String),
    createdAt: $checkedConvert('createdAt', (v) => DateTime.parse(v as String)),
    lastActivityAt: $checkedConvert(
      'lastActivityAt',
      (v) => (v as num).toInt(),
    ),
    archivedAt: $checkedConvert(
      'archivedAt',
      (v) => v == null ? null : DateTime.parse(v as String),
    ),
    updatedAt: $checkedConvert('updatedAt', (v) => DateTime.parse(v as String)),
    seq: $checkedConvert('seq', (v) => (v as num).toInt()),
  );
  return val;
});

Map<String, dynamic> _$GroupToJson(Group instance) => <String, dynamic>{
  'id': instance.id,
  'name': instance.name,
  'defaultCurrency': instance.defaultCurrency,
  'isDirect': instance.isDirect,
  'simplifyDebts': instance.simplifyDebts,
  'avatarKind': _$AvatarKindEnumMap[instance.avatarKind]!,
  'avatarColor': _$AvatarColorEnumMap[instance.avatarColor],
  'avatarEmoji': instance.avatarEmoji,
  'avatarIcon': _$AvatarIconEnumMap[instance.avatarIcon],
  'avatarPhoto': instance.avatarPhoto,
  'coverKind': _$CoverKindEnumMap[instance.coverKind]!,
  'coverPhoto': instance.coverPhoto,
  'createdBy': instance.createdBy,
  'createdAt': instance.createdAt.toIso8601String(),
  'lastActivityAt': instance.lastActivityAt,
  'archivedAt': instance.archivedAt?.toIso8601String(),
  'updatedAt': instance.updatedAt.toIso8601String(),
  'seq': instance.seq,
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
