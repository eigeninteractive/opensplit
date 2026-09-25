//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:json_annotation/json_annotation.dart';

part 'group_update.g.dart';

@JsonSerializable(
  checked: true,
  createToJson: true,
  disallowUnrecognizedKeys: false,
  explicitToJson: true,
)
class GroupUpdate {
  /// Returns a new [GroupUpdate] instance.
  GroupUpdate({
    required this.name,

    required this.simplifyDebts,

    required this.archivedAt,
  });

  @JsonKey(name: r'name', required: true, includeIfNull: false)
  final String name;

  @JsonKey(name: r'simplifyDebts', required: true, includeIfNull: false)
  final bool simplifyDebts;

  @JsonKey(name: r'archivedAt', required: true, includeIfNull: true)
  final DateTime? archivedAt;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is GroupUpdate &&
          other.name == name &&
          other.simplifyDebts == simplifyDebts &&
          other.archivedAt == archivedAt;

  @override
  int get hashCode =>
      name.hashCode +
      simplifyDebts.hashCode +
      (archivedAt == null ? 0 : archivedAt.hashCode);

  factory GroupUpdate.fromJson(Map<String, dynamic> json) =>
      _$GroupUpdateFromJson(json);

  Map<String, dynamic> toJson() => _$GroupUpdateToJson(this);

  @override
  String toString() {
    return toJson().toString();
  }
}
