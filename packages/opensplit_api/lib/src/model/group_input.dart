//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
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
          other.creatorId == creatorId &&
          other.creatorName == creatorName;

  @override
  int get hashCode =>
      name.hashCode +
      defaultCurrency.hashCode +
      isDirect.hashCode +
      simplifyDebts.hashCode +
      (archivedAt == null ? 0 : archivedAt.hashCode) +
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
