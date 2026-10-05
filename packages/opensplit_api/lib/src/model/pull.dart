//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:opensplit_api/src/model/group_refusal.dart';
import 'package:opensplit_api/src/model/change_page.dart';
import 'package:json_annotation/json_annotation.dart';

part 'pull.g.dart';

@JsonSerializable(
  checked: true,
  createToJson: true,
  disallowUnrecognizedKeys: false,
  explicitToJson: true,
)
class Pull {
  /// Returns a new [Pull] instance.
  Pull({required this.groupIds, required this.pages, required this.refusals});

  @JsonKey(name: r'groupIds', required: true, includeIfNull: false)
  final List<String> groupIds;

  @JsonKey(name: r'pages', required: true, includeIfNull: false)
  final List<ChangePage> pages;

  @JsonKey(name: r'refusals', required: true, includeIfNull: false)
  final List<GroupRefusal> refusals;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Pull &&
          other.groupIds == groupIds &&
          other.pages == pages &&
          other.refusals == refusals;

  @override
  int get hashCode => groupIds.hashCode + pages.hashCode + refusals.hashCode;

  factory Pull.fromJson(Map<String, dynamic> json) => _$PullFromJson(json);

  Map<String, dynamic> toJson() => _$PullToJson(this);

  @override
  String toString() {
    return toJson().toString();
  }
}
