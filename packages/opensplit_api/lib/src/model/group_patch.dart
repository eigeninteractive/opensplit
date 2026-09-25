//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:json_annotation/json_annotation.dart';

part 'group_patch.g.dart';

@JsonSerializable(
  checked: true,
  createToJson: true,
  disallowUnrecognizedKeys: false,
  explicitToJson: true,
)
class GroupPatch {
  /// Returns a new [GroupPatch] instance.
  GroupPatch({this.name, this.simplifyDebts, required this.archivedAt});

  @JsonKey(name: r'name', required: false, includeIfNull: false)
  final String? name;

  @JsonKey(name: r'simplifyDebts', required: false, includeIfNull: false)
  final bool? simplifyDebts;

  @JsonKey(name: r'archivedAt', required: true, includeIfNull: true)
  final DateTime? archivedAt;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is GroupPatch &&
          other.name == name &&
          other.simplifyDebts == simplifyDebts &&
          other.archivedAt == archivedAt;

  @override
  int get hashCode =>
      name.hashCode +
      simplifyDebts.hashCode +
      (archivedAt == null ? 0 : archivedAt.hashCode);

  factory GroupPatch.fromJson(Map<String, dynamic> json) =>
      _$GroupPatchFromJson(json);

  Map<String, dynamic> toJson() => _$GroupPatchToJson(this);

  @override
  String toString() {
    return toJson().toString();
  }
}
