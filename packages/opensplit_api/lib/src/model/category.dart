//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:json_annotation/json_annotation.dart';

part 'category.g.dart';

@JsonSerializable(
  checked: true,
  createToJson: true,
  disallowUnrecognizedKeys: false,
  explicitToJson: true,
)
class Category {
  /// Returns a new [Category] instance.
  Category({required this.id, required this.name, required this.icon});

  @JsonKey(name: r'id', required: true, includeIfNull: false)
  final String id;

  @JsonKey(name: r'name', required: true, includeIfNull: false)
  final String name;

  @JsonKey(name: r'icon', required: true, includeIfNull: false)
  final String icon;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Category &&
          other.id == id &&
          other.name == name &&
          other.icon == icon;

  @override
  int get hashCode => id.hashCode + name.hashCode + icon.hashCode;

  factory Category.fromJson(Map<String, dynamic> json) =>
      _$CategoryFromJson(json);

  Map<String, dynamic> toJson() => _$CategoryToJson(this);

  @override
  String toString() {
    return toJson().toString();
  }
}
