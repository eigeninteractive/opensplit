//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:opensplit_api/src/model/profile.dart';
import 'package:json_annotation/json_annotation.dart';

part 'profile_list.g.dart';

@JsonSerializable(
  checked: true,
  createToJson: true,
  disallowUnrecognizedKeys: false,
  explicitToJson: true,
)
class ProfileList {
  /// Returns a new [ProfileList] instance.
  ProfileList({required this.profiles});

  @JsonKey(name: r'profiles', required: true, includeIfNull: false)
  final List<Profile> profiles;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ProfileList && other.profiles == profiles;

  @override
  int get hashCode => profiles.hashCode;

  factory ProfileList.fromJson(Map<String, dynamic> json) =>
      _$ProfileListFromJson(json);

  Map<String, dynamic> toJson() => _$ProfileListToJson(this);

  @override
  String toString() {
    return toJson().toString();
  }
}
