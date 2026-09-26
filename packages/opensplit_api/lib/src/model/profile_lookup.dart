//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:json_annotation/json_annotation.dart';

part 'profile_lookup.g.dart';

@JsonSerializable(
  checked: true,
  createToJson: true,
  disallowUnrecognizedKeys: false,
  explicitToJson: true,
)
class ProfileLookup {
  /// Returns a new [ProfileLookup] instance.
  ProfileLookup({required this.ids});

  @JsonKey(name: r'ids', required: true, includeIfNull: false)
  final List<String> ids;

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is ProfileLookup && other.ids == ids;

  @override
  int get hashCode => ids.hashCode;

  factory ProfileLookup.fromJson(Map<String, dynamic> json) =>
      _$ProfileLookupFromJson(json);

  Map<String, dynamic> toJson() => _$ProfileLookupToJson(this);

  @override
  String toString() {
    return toJson().toString();
  }
}
