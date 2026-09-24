//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:opensplit_api/src/model/profile.dart';
import 'package:json_annotation/json_annotation.dart';

part 'profile_page.g.dart';

@JsonSerializable(
  checked: true,
  createToJson: true,
  disallowUnrecognizedKeys: false,
  explicitToJson: true,
)
class ProfilePage {
  /// Returns a new [ProfilePage] instance.
  ProfilePage({
    required this.profiles,

    required this.cursor,

    required this.cursorId,

    required this.hasMore,
  });

  @JsonKey(name: r'profiles', required: true, includeIfNull: false)
  final List<Profile> profiles;

  @JsonKey(name: r'cursor', required: true, includeIfNull: true)
  final DateTime? cursor;

  @JsonKey(name: r'cursorId', required: true, includeIfNull: true)
  final String? cursorId;

  @JsonKey(name: r'hasMore', required: true, includeIfNull: false)
  final bool hasMore;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ProfilePage &&
          other.profiles == profiles &&
          other.cursor == cursor &&
          other.cursorId == cursorId &&
          other.hasMore == hasMore;

  @override
  int get hashCode =>
      profiles.hashCode +
      (cursor == null ? 0 : cursor.hashCode) +
      (cursorId == null ? 0 : cursorId.hashCode) +
      hasMore.hashCode;

  factory ProfilePage.fromJson(Map<String, dynamic> json) =>
      _$ProfilePageFromJson(json);

  Map<String, dynamic> toJson() => _$ProfilePageToJson(this);

  @override
  String toString() {
    return toJson().toString();
  }
}
