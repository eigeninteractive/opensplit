//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:opensplit_api/src/model/avatar_color.dart';
import 'package:opensplit_api/src/model/avatar_kind.dart';
import 'package:opensplit_api/src/model/cover_kind.dart';
import 'package:opensplit_api/src/model/avatar_icon.dart';
import 'package:json_annotation/json_annotation.dart';

part 'group_input.g.dart';

@JsonSerializable(
  checked: true,
  createToJson: true,
  disallowUnrecognizedKeys: false,
  explicitToJson: true,
)
class GroupInput {
  /// Returns a new [GroupInput] instance.
  GroupInput({
    required this.name,

    required this.defaultCurrency,

    required this.isDirect,

    required this.simplifyDebts,

    required this.archivedAt,

    required this.avatarKind,

    required this.avatarColor,

    required this.avatarEmoji,

    required this.avatarIcon,

    required this.avatarPhoto,

    required this.coverKind,

    required this.coverPhoto,

    required this.creatorId,

    required this.creatorName,
  });

  @JsonKey(name: r'name', required: true, includeIfNull: false)
  final String name;

  @JsonKey(name: r'defaultCurrency', required: true, includeIfNull: false)
  final String defaultCurrency;

  @JsonKey(name: r'isDirect', required: true, includeIfNull: false)
  final bool isDirect;

  @JsonKey(name: r'simplifyDebts', required: true, includeIfNull: false)
  final bool simplifyDebts;

  @JsonKey(name: r'archivedAt', required: true, includeIfNull: true)
  final DateTime? archivedAt;

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

  @JsonKey(name: r'creatorId', required: true, includeIfNull: false)
  final String creatorId;

  @JsonKey(name: r'creatorName', required: true, includeIfNull: false)
  final String creatorName;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is GroupInput &&
          other.name == name &&
          other.defaultCurrency == defaultCurrency &&
          other.isDirect == isDirect &&
          other.simplifyDebts == simplifyDebts &&
          other.archivedAt == archivedAt &&
          other.avatarKind == avatarKind &&
          other.avatarColor == avatarColor &&
          other.avatarEmoji == avatarEmoji &&
          other.avatarIcon == avatarIcon &&
          other.avatarPhoto == avatarPhoto &&
          other.coverKind == coverKind &&
          other.coverPhoto == coverPhoto &&
          other.creatorId == creatorId &&
          other.creatorName == creatorName;

  @override
  int get hashCode =>
      name.hashCode +
      defaultCurrency.hashCode +
      isDirect.hashCode +
      simplifyDebts.hashCode +
      (archivedAt == null ? 0 : archivedAt.hashCode) +
      avatarKind.hashCode +
      (avatarColor == null ? 0 : avatarColor.hashCode) +
      (avatarEmoji == null ? 0 : avatarEmoji.hashCode) +
      (avatarIcon == null ? 0 : avatarIcon.hashCode) +
      (avatarPhoto == null ? 0 : avatarPhoto.hashCode) +
      coverKind.hashCode +
      (coverPhoto == null ? 0 : coverPhoto.hashCode) +
      creatorId.hashCode +
      creatorName.hashCode;

  factory GroupInput.fromJson(Map<String, dynamic> json) =>
      _$GroupInputFromJson(json);

  Map<String, dynamic> toJson() => _$GroupInputToJson(this);

  @override
  String toString() {
    return toJson().toString();
  }
}
