//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:opensplit_api/src/model/group_cursor.dart';
import 'package:json_annotation/json_annotation.dart';

part 'pull_request.g.dart';

@JsonSerializable(
  checked: true,
  createToJson: true,
  disallowUnrecognizedKeys: false,
  explicitToJson: true,
)
class PullRequest {
  /// Returns a new [PullRequest] instance.
  PullRequest({required this.groups, required this.limit});

  @JsonKey(name: r'groups', required: true, includeIfNull: false)
  final List<GroupCursor> groups;

  // minimum: 1
  // maximum: 500
  @JsonKey(name: r'limit', required: true, includeIfNull: false)
  final int limit;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PullRequest && other.groups == groups && other.limit == limit;

  @override
  int get hashCode => groups.hashCode + limit.hashCode;

  factory PullRequest.fromJson(Map<String, dynamic> json) =>
      _$PullRequestFromJson(json);

  Map<String, dynamic> toJson() => _$PullRequestToJson(this);

  @override
  String toString() {
    return toJson().toString();
  }
}
