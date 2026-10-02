import 'package:characters/characters.dart';
import 'package:freezed_annotation/freezed_annotation.dart' show immutable;
import 'package:opensplit_api/opensplit_api.dart'
    show AvatarColor, AvatarIcon, AvatarKind;

/// What stands for a person or a group wherever there is no room for a name.
///
/// One of four kinds, each carrying only what it shows. [color] is the hue
/// behind initials, an emoji or an icon; null until somebody picks one, and
/// then [hueFor] derives one from the owner's id so it never moves by itself.
@immutable
sealed class Avatar {
  const Avatar({this.color});

  final AvatarColor? color;

  /// The same avatar on another hue.
  Avatar withColor(AvatarColor? color);

  /// The row's columns, the inverse of [Avatar.fromColumns].
  AvatarColumns get columns => switch (this) {
    InitialsAvatar() => (
      kind: AvatarKind.initials,
      color: color,
      emoji: null,
      icon: null,
      photo: null,
    ),
    EmojiAvatar(:final emoji) => (
      kind: AvatarKind.emoji,
      color: color,
      emoji: emoji,
      icon: null,
      photo: null,
    ),
    IconAvatar(:final icon) => (
      kind: AvatarKind.icon,
      color: color,
      emoji: null,
      icon: icon,
      photo: null,
    ),
    PhotoAvatar(:final key) => (
      kind: AvatarKind.photo,
      color: color,
      emoji: null,
      icon: null,
      photo: key,
    ),
  };

  /// Reads the columns a profile or a group stores. A kind whose field is
  /// missing, or one this build does not know, shows as initials.
  factory Avatar.fromColumns(AvatarColumns columns) {
    final AvatarColumns(:kind, :color, :emoji, :icon, :photo) = columns;
    return switch (kind) {
      AvatarKind.emoji when emoji != null => EmojiAvatar(emoji, color: color),
      AvatarKind.icon
          when icon != null && icon != AvatarIcon.unknownDefaultOpenApi =>
        IconAvatar(icon, color: color),
      AvatarKind.photo when photo != null => PhotoAvatar(photo, color: color),
      _ => InitialsAvatar(color: color),
    };
  }

  @override
  bool operator ==(Object other) => other is Avatar && other.columns == columns;

  @override
  int get hashCode => columns.hashCode;
}

/// The avatar columns, as both a profile and a group store them.
typedef AvatarColumns = ({
  AvatarKind kind,
  AvatarColor? color,
  String? emoji,
  AvatarIcon? icon,
  String? photo,
});

final class InitialsAvatar extends Avatar {
  const InitialsAvatar({super.color});

  @override
  InitialsAvatar withColor(AvatarColor? color) => InitialsAvatar(color: color);
}

final class EmojiAvatar extends Avatar {
  const EmojiAvatar(this.emoji, {super.color});

  final String emoji;

  @override
  EmojiAvatar withColor(AvatarColor? color) => EmojiAvatar(emoji, color: color);
}

final class IconAvatar extends Avatar {
  const IconAvatar(this.icon, {super.color});

  final AvatarIcon icon;

  @override
  IconAvatar withColor(AvatarColor? color) => IconAvatar(icon, color: color);
}

/// An uploaded picture, by its key in the media store. Nothing can upload one
/// yet; the shape is here so that turning uploads on changes no row.
final class PhotoAvatar extends Avatar {
  const PhotoAvatar(this.key, {super.color});

  final String key;

  @override
  PhotoAvatar withColor(AvatarColor? color) => PhotoAvatar(key, color: color);
}

/// The hues a person can pick, in the order they are offered.
final List<AvatarColor> avatarHues = [
  for (final color in AvatarColor.values)
    if (color != AvatarColor.unknownDefaultOpenApi) color,
];

/// The hue an avatar has before anybody picks one.
AvatarColor hueFor(String id) => avatarHues[stableHash(id) % avatarHues.length];

/// A hash of [text] that is the same on every device and every run, which
/// `String.hashCode` does not promise. 32-bit FNV-1a.
int stableHash(String text) {
  var hash = 0x811c9dc5;
  for (final unit in text.codeUnits) {
    hash = ((hash ^ unit) * 0x01000193) & 0xffffffff;
  }
  return hash;
}

/// Up to two letters for [name]: the first letters of its first and last
/// words, so "Ana Maria da Silva" is "AS".
String initialsOf(String name) {
  final words = name.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
  if (words.isEmpty) return '';
  // By what a reader sees as one letter, so a mark that combines with the
  // letter before it stays with it.
  final first = words.first.characters.first;
  final last = words.length > 1 ? words.last.characters.first : '';
  return (first + last).toUpperCase();
}
