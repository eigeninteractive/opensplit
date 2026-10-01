//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:json_annotation/json_annotation.dart';

part 'google_redirect.g.dart';

@JsonSerializable(
  checked: true,
  createToJson: true,
  disallowUnrecognizedKeys: false,
  explicitToJson: true,
)
class GoogleRedirect {
  /// Returns a new [GoogleRedirect] instance.
  GoogleRedirect({required this.url});

  @JsonKey(name: r'url', required: true, includeIfNull: false)
  final String url;

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is GoogleRedirect && other.url == url;

  @override
  int get hashCode => url.hashCode;

  factory GoogleRedirect.fromJson(Map<String, dynamic> json) =>
      _$GoogleRedirectFromJson(json);

  Map<String, dynamic> toJson() => _$GoogleRedirectToJson(this);

  @override
  String toString() {
    return toJson().toString();
  }
}
