//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:json_annotation/json_annotation.dart';

part 'group_create.g.dart';

@JsonSerializable(
  checked: true,
  createToJson: true,
  disallowUnrecognizedKeys: false,
  explicitToJson: true,
)
class GroupCreate {
  /// Returns a new [GroupCreate] instance.
  GroupCreate({
    required this.id,

    required this.name,

    required this.defaultCurrency,

    this.isDirect = false,

    this.simplifyDebts = true,

    required this.memberId,

    required this.displayName,
  });

  @JsonKey(name: r'id', required: true, includeIfNull: false)
  final String id;

  @JsonKey(name: r'name', required: true, includeIfNull: false)
  final String name;

  @JsonKey(name: r'defaultCurrency', required: true, includeIfNull: false)
  final String defaultCurrency;

  @JsonKey(
    defaultValue: false,
    name: r'isDirect',
    required: false,
    includeIfNull: false,
  )
  final bool? isDirect;

  @JsonKey(
    defaultValue: true,
    name: r'simplifyDebts',
    required: false,
    includeIfNull: false,
  )
  final bool? simplifyDebts;

  @JsonKey(name: r'memberId', required: true, includeIfNull: false)
  final String memberId;

  @JsonKey(name: r'displayName', required: true, includeIfNull: false)
  final String displayName;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is GroupCreate &&
          other.id == id &&
          other.name == name &&
          other.defaultCurrency == defaultCurrency &&
          other.isDirect == isDirect &&
          other.simplifyDebts == simplifyDebts &&
          other.memberId == memberId &&
          other.displayName == displayName;

  @override
  int get hashCode =>
      id.hashCode +
      name.hashCode +
      defaultCurrency.hashCode +
      isDirect.hashCode +
      simplifyDebts.hashCode +
      memberId.hashCode +
      displayName.hashCode;

  factory GroupCreate.fromJson(Map<String, dynamic> json) =>
      _$GroupCreateFromJson(json);

  Map<String, dynamic> toJson() => _$GroupCreateToJson(this);

  @override
  String toString() {
    return toJson().toString();
  }
}
