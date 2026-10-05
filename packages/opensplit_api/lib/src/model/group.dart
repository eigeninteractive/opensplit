//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:opensplit_api/src/model/avatar_color.dart';
import 'package:opensplit_api/src/model/avatar_kind.dart';
import 'package:opensplit_api/src/model/cover_kind.dart';
import 'package:opensplit_api/src/model/avatar_icon.dart';
import 'package:json_annotation/json_annotation.dart';

part 'group.g.dart';

@JsonSerializable(
  checked: true,
  createToJson: true,
  disallowUnrecognizedKeys: false,
  explicitToJson: true,
)
class Group {
  /// Returns a new [Group] instance.
  Group({
    required this.id,

    required this.name,

    required this.defaultCurrency,

    required this.isDirect,

    required this.simplifyDebts,

    required this.avatarKind,

    required this.avatarColor,

    required this.avatarEmoji,

    required this.avatarIcon,

    required this.avatarPhoto,

    required this.coverKind,

    required this.coverPhoto,

    required this.createdBy,

    required this.createdAt,

    required this.lastActivityAt,

    required this.archivedAt,

    required this.updatedAt,

    required this.seq,
  });

  @JsonKey(name: r'id', required: true, includeIfNull: false)
  final String id;

  @JsonKey(name: r'name', required: true, includeIfNull: false)
  final String name;

  @JsonKey(name: r'defaultCurrency', required: true, includeIfNull: false)
  final String defaultCurrency;

  @JsonKey(name: r'isDirect', required: true, includeIfNull: false)
  final bool isDirect;

  @JsonKey(name: r'simplifyDebts', required: true, includeIfNull: false)
  final bool simplifyDebts;

  @JsonKey(
    name: r'avatarKind',
    required: true,
    includeIfNull: false,
    unknownEnumValue: AvatarKind.unknownDefaultOpenApi,
  )
  final AvatarKind avatarKind;

  @JsonKey(
    name: r'avatarColor',
    required: true,
    includeIfNull: true,
    unknownEnumValue: AvatarColor.unknownDefaultOpenApi,
  )
  final AvatarColor? avatarColor;

  @JsonKey(name: r'avatarEmoji', required: true, includeIfNull: true)
  final String? avatarEmoji;

  @JsonKey(
    name: r'avatarIcon',
    required: true,
    includeIfNull: true,
    unknownEnumValue: AvatarIcon.unknownDefaultOpenApi,
  )
  final AvatarIcon? avatarIcon;

  @JsonKey(name: r'avatarPhoto', required: true, includeIfNull: true)
  final String? avatarPhoto;

  @JsonKey(
    name: r'coverKind',
    required: true,
    includeIfNull: false,
    unknownEnumValue: CoverKind.unknownDefaultOpenApi,
  )
  final CoverKind coverKind;

  @JsonKey(name: r'coverPhoto', required: true, includeIfNull: true)
  final String? coverPhoto;

  @JsonKey(name: r'createdBy', required: true, includeIfNull: false)
  final String createdBy;

  @JsonKey(name: r'createdAt', required: true, includeIfNull: false)
  final DateTime createdAt;

  // minimum: -9007199254740991
  // maximum: 9007199254740991
  @JsonKey(name: r'lastActivityAt', required: true, includeIfNull: false)
  final int lastActivityAt;

  @JsonKey(name: r'archivedAt', required: true, includeIfNull: true)
  final DateTime? archivedAt;

  @JsonKey(name: r'updatedAt', required: true, includeIfNull: false)
  final DateTime updatedAt;

  // minimum: 0
  @JsonKey(name: r'seq', required: true, includeIfNull: false)
  final int seq;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Group &&
          other.id == id &&
          other.name == name &&
          other.defaultCurrency == defaultCurrency &&
          other.isDirect == isDirect &&
          other.simplifyDebts == simplifyDebts &&
          other.avatarKind == avatarKind &&
          other.avatarColor == avatarColor &&
          other.avatarEmoji == avatarEmoji &&
          other.avatarIcon == avatarIcon &&
          other.avatarPhoto == avatarPhoto &&
          other.coverKind == coverKind &&
          other.coverPhoto == coverPhoto &&
          other.createdBy == createdBy &&
          other.createdAt == createdAt &&
          other.lastActivityAt == lastActivityAt &&
          other.archivedAt == archivedAt &&
          other.updatedAt == updatedAt &&
          other.seq == seq;

  @override
  int get hashCode =>
      id.hashCode +
      name.hashCode +
      defaultCurrency.hashCode +
      isDirect.hashCode +
      simplifyDebts.hashCode +
      avatarKind.hashCode +
      (avatarColor == null ? 0 : avatarColor.hashCode) +
      (avatarEmoji == null ? 0 : avatarEmoji.hashCode) +
      (avatarIcon == null ? 0 : avatarIcon.hashCode) +
      (avatarPhoto == null ? 0 : avatarPhoto.hashCode) +
      coverKind.hashCode +
      (coverPhoto == null ? 0 : coverPhoto.hashCode) +
      createdBy.hashCode +
      createdAt.hashCode +
      lastActivityAt.hashCode +
      (archivedAt == null ? 0 : archivedAt.hashCode) +
      updatedAt.hashCode +
      seq.hashCode;

  factory Group.fromJson(Map<String, dynamic> json) => _$GroupFromJson(json);

  Map<String, dynamic> toJson() => _$GroupToJson(this);

  @override
  String toString() {
    return toJson().toString();
  }
}
