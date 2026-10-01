//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:json_annotation/json_annotation.dart';

part 'group.g.dart';

@JsonSerializable(
  checked: true,
  createToJson: true,
  disallowUnrecognizedKeys: false,
  explicitToJson: true,
)
class Group {
  /// Returns a new [Group] instance.
  Group({
    required this.id,

    required this.name,

    required this.defaultCurrency,

    required this.isDirect,

    required this.simplifyDebts,

    required this.createdBy,

    required this.createdAt,

    required this.archivedAt,

    required this.updatedAt,

    required this.seq,
  });

  @JsonKey(name: r'id', required: true, includeIfNull: false)
  final String id;

  @JsonKey(name: r'name', required: true, includeIfNull: false)
  final String name;

  @JsonKey(name: r'defaultCurrency', required: true, includeIfNull: false)
  final String defaultCurrency;

  @JsonKey(name: r'isDirect', required: true, includeIfNull: false)
  final bool isDirect;

  @JsonKey(name: r'simplifyDebts', required: true, includeIfNull: false)
  final bool simplifyDebts;

  @JsonKey(name: r'createdBy', required: true, includeIfNull: false)
  final String createdBy;

  @JsonKey(name: r'createdAt', required: true, includeIfNull: false)
  final DateTime createdAt;

  @JsonKey(name: r'archivedAt', required: true, includeIfNull: true)
  final DateTime? archivedAt;

  @JsonKey(name: r'updatedAt', required: true, includeIfNull: false)
  final DateTime updatedAt;

  // minimum: 0
  @JsonKey(name: r'seq', required: true, includeIfNull: false)
  final int seq;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Group &&
          other.id == id &&
          other.name == name &&
          other.defaultCurrency == defaultCurrency &&
          other.isDirect == isDirect &&
          other.simplifyDebts == simplifyDebts &&
          other.createdBy == createdBy &&
          other.createdAt == createdAt &&
          other.archivedAt == archivedAt &&
          other.updatedAt == updatedAt &&
          other.seq == seq;

  @override
  int get hashCode =>
      id.hashCode +
      name.hashCode +
      defaultCurrency.hashCode +
      isDirect.hashCode +
      simplifyDebts.hashCode +
      createdBy.hashCode +
      createdAt.hashCode +
      (archivedAt == null ? 0 : archivedAt.hashCode) +
      updatedAt.hashCode +
      seq.hashCode;

  factory Group.fromJson(Map<String, dynamic> json) => _$GroupFromJson(json);

  Map<String, dynamic> toJson() => _$GroupToJson(this);

  @override
  String toString() {
    return toJson().toString();
  }
}
