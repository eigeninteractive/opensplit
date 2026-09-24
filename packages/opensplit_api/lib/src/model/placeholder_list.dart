//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:opensplit_api/src/model/placeholder.dart';
import 'package:json_annotation/json_annotation.dart';

part 'placeholder_list.g.dart';

@JsonSerializable(
  checked: true,
  createToJson: true,
  disallowUnrecognizedKeys: false,
  explicitToJson: true,
)
class PlaceholderList {
  /// Returns a new [PlaceholderList] instance.
  PlaceholderList({required this.placeholders});

  @JsonKey(name: r'placeholders', required: true, includeIfNull: false)
  final List<Placeholder> placeholders;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PlaceholderList && other.placeholders == placeholders;

  @override
  int get hashCode => placeholders.hashCode;

  factory PlaceholderList.fromJson(Map<String, dynamic> json) =>
      _$PlaceholderListFromJson(json);

  Map<String, dynamic> toJson() => _$PlaceholderListToJson(this);

  @override
  String toString() {
    return toJson().toString();
  }
}
