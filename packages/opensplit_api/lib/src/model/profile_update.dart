//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:opensplit_api/src/model/avatar_color.dart';
import 'package:opensplit_api/src/model/avatar_kind.dart';
import 'package:opensplit_api/src/model/avatar_icon.dart';
import 'package:json_annotation/json_annotation.dart';

part 'profile_update.g.dart';

@JsonSerializable(
  checked: true,
  createToJson: true,
  disallowUnrecognizedKeys: false,
  explicitToJson: true,
)
class ProfileUpdate {
  /// Returns a new [ProfileUpdate] instance.
  ProfileUpdate({
    required this.displayName,

    required this.upiVpa,

    required this.avatarKind,

    required this.avatarColor,

    required this.avatarEmoji,

    required this.avatarIcon,

    required this.avatarPhoto,
  });

  @JsonKey(name: r'displayName', required: true, includeIfNull: true)
  final String? displayName;

  @JsonKey(name: r'upiVpa', required: true, includeIfNull: true)
  final String? upiVpa;

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

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ProfileUpdate &&
          other.displayName == displayName &&
          other.upiVpa == upiVpa &&
          other.avatarKind == avatarKind &&
          other.avatarColor == avatarColor &&
          other.avatarEmoji == avatarEmoji &&
          other.avatarIcon == avatarIcon &&
          other.avatarPhoto == avatarPhoto;

  @override
  int get hashCode =>
      (displayName == null ? 0 : displayName.hashCode) +
      (upiVpa == null ? 0 : upiVpa.hashCode) +
      avatarKind.hashCode +
      (avatarColor == null ? 0 : avatarColor.hashCode) +
      (avatarEmoji == null ? 0 : avatarEmoji.hashCode) +
      (avatarIcon == null ? 0 : avatarIcon.hashCode) +
      (avatarPhoto == null ? 0 : avatarPhoto.hashCode);

  factory ProfileUpdate.fromJson(Map<String, dynamic> json) =>
      _$ProfileUpdateFromJson(json);

  Map<String, dynamic> toJson() => _$ProfileUpdateToJson(this);

  @override
  String toString() {
    return toJson().toString();
  }
}
