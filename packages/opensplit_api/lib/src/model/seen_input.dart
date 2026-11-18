//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:json_annotation/json_annotation.dart';

part 'seen_input.g.dart';

@JsonSerializable(
  checked: true,
  createToJson: true,
  disallowUnrecognizedKeys: false,
  explicitToJson: true,
)
class SeenInput {
  /// Returns a new [SeenInput] instance.
  SeenInput({required this.seenAt});

  @JsonKey(name: r'seenAt', required: true, includeIfNull: false)
  final DateTime seenAt;

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is SeenInput && other.seenAt == seenAt;

  @override
  int get hashCode => seenAt.hashCode;

  factory SeenInput.fromJson(Map<String, dynamic> json) =>
      _$SeenInputFromJson(json);

  Map<String, dynamic> toJson() => _$SeenInputToJson(this);

  @override
  String toString() {
    return toJson().toString();
  }
}
