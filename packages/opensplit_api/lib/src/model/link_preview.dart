//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:json_annotation/json_annotation.dart';

part 'link_preview.g.dart';

@JsonSerializable(
  checked: true,
  createToJson: true,
  disallowUnrecognizedKeys: false,
  explicitToJson: true,
)
class LinkPreview {
  /// Returns a new [LinkPreview] instance.
  LinkPreview({
    required this.kind,

    required this.groupId,

    required this.groupName,

    required this.inviterName,

    required this.memberCount,

    required this.memberName,

    required this.isRedeemed,

    required this.isExpired,

    required this.isRevoked,

    required this.isMember,
  });

  @JsonKey(
    name: r'kind',
    required: true,
    includeIfNull: false,
    unknownEnumValue: LinkPreviewKindEnum.unknownDefaultOpenApi,
  )
  final LinkPreviewKindEnum kind;

  @JsonKey(name: r'groupId', required: true, includeIfNull: false)
  final String groupId;

  @JsonKey(name: r'groupName', required: true, includeIfNull: false)
  final String groupName;

  @JsonKey(name: r'inviterName', required: true, includeIfNull: true)
  final String? inviterName;

  // minimum: 0
  @JsonKey(name: r'memberCount', required: true, includeIfNull: false)
  final int memberCount;

  @JsonKey(name: r'memberName', required: true, includeIfNull: true)
  final String? memberName;

  @JsonKey(name: r'isRedeemed', required: true, includeIfNull: false)
  final bool isRedeemed;

  @JsonKey(name: r'isExpired', required: true, includeIfNull: false)
  final bool isExpired;

  @JsonKey(name: r'isRevoked', required: true, includeIfNull: false)
  final bool isRevoked;

  @JsonKey(name: r'isMember', required: true, includeIfNull: false)
  final bool isMember;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LinkPreview &&
          other.kind == kind &&
          other.groupId == groupId &&
          other.groupName == groupName &&
          other.inviterName == inviterName &&
          other.memberCount == memberCount &&
          other.memberName == memberName &&
          other.isRedeemed == isRedeemed &&
          other.isExpired == isExpired &&
          other.isRevoked == isRevoked &&
          other.isMember == isMember;

  @override
  int get hashCode =>
      kind.hashCode +
      groupId.hashCode +
      groupName.hashCode +
      (inviterName == null ? 0 : inviterName.hashCode) +
      memberCount.hashCode +
      (memberName == null ? 0 : memberName.hashCode) +
      isRedeemed.hashCode +
      isExpired.hashCode +
      isRevoked.hashCode +
      isMember.hashCode;

  factory LinkPreview.fromJson(Map<String, dynamic> json) =>
      _$LinkPreviewFromJson(json);

  Map<String, dynamic> toJson() => _$LinkPreviewToJson(this);

  @override
  String toString() {
    return toJson().toString();
  }
}

enum LinkPreviewKindEnum {
  @JsonValue(r'invite')
  invite(r'invite'),
  @JsonValue(r'group_link')
  groupLink(r'group_link'),
  @JsonValue(r'unknown_default_open_api')
  unknownDefaultOpenApi(r'unknown_default_open_api');

  const LinkPreviewKindEnum(this.value);

  final String value;

  @override
  String toString() => value;
}
