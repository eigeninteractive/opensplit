//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:opensplit_api/src/model/group_link.dart';
import 'package:json_annotation/json_annotation.dart';

part 'live_link.g.dart';

@JsonSerializable(
  checked: true,
  createToJson: true,
  disallowUnrecognizedKeys: false,
  explicitToJson: true,
)
class LiveLink {
  /// Returns a new [LiveLink] instance.
  LiveLink({required this.link});

  @JsonKey(name: r'link', required: true, includeIfNull: true)
  final GroupLink? link;

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is LiveLink && other.link == link;

  @override
  int get hashCode => (link == null ? 0 : link.hashCode);

  factory LiveLink.fromJson(Map<String, dynamic> json) =>
      _$LiveLinkFromJson(json);

  Map<String, dynamic> toJson() => _$LiveLinkToJson(this);

  @override
  String toString() {
    return toJson().toString();
  }
}
