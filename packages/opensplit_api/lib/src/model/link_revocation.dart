//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:json_annotation/json_annotation.dart';

part 'link_revocation.g.dart';

@JsonSerializable(
  checked: true,
  createToJson: true,
  disallowUnrecognizedKeys: false,
  explicitToJson: true,
)
class LinkRevocation {
  /// Returns a new [LinkRevocation] instance.
  LinkRevocation({required this.revoked});

  @JsonKey(name: r'revoked', required: true, includeIfNull: true)
  final String? revoked;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LinkRevocation && other.revoked == revoked;

  @override
  int get hashCode => (revoked == null ? 0 : revoked.hashCode);

  factory LinkRevocation.fromJson(Map<String, dynamic> json) =>
      _$LinkRevocationFromJson(json);

  Map<String, dynamic> toJson() => _$LinkRevocationToJson(this);

  @override
  String toString() {
    return toJson().toString();
  }
}
