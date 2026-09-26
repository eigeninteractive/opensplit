//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:json_annotation/json_annotation.dart';

part 'placeholder.g.dart';

@JsonSerializable(
  checked: true,
  createToJson: true,
  disallowUnrecognizedKeys: false,
  explicitToJson: true,
)
class Placeholder {
  /// Returns a new [Placeholder] instance.
  Placeholder({required this.id, required this.displayName});

  @JsonKey(name: r'id', required: true, includeIfNull: false)
  final String id;

  @JsonKey(name: r'displayName', required: true, includeIfNull: false)
  final String displayName;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Placeholder &&
          other.id == id &&
          other.displayName == displayName;

  @override
  int get hashCode => id.hashCode + displayName.hashCode;

  factory Placeholder.fromJson(Map<String, dynamic> json) =>
      _$PlaceholderFromJson(json);

  Map<String, dynamic> toJson() => _$PlaceholderToJson(this);

  @override
  String toString() {
    return toJson().toString();
  }
}
