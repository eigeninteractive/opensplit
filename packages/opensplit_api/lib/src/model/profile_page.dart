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

    required this.seq,

    required this.hasMore,
  });

  @JsonKey(name: r'profiles', required: true, includeIfNull: false)
  final List<Profile> profiles;

  // minimum: 0
  @JsonKey(name: r'seq', required: true, includeIfNull: false)
  final int seq;

  @JsonKey(name: r'hasMore', required: true, includeIfNull: false)
  final bool hasMore;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ProfilePage &&
          other.profiles == profiles &&
          other.seq == seq &&
          other.hasMore == hasMore;

  @override
  int get hashCode => profiles.hashCode + seq.hashCode + hasMore.hashCode;

  factory ProfilePage.fromJson(Map<String, dynamic> json) =>
      _$ProfilePageFromJson(json);

  Map<String, dynamic> toJson() => _$ProfilePageToJson(this);

  @override
  String toString() {
    return toJson().toString();
  }
}
