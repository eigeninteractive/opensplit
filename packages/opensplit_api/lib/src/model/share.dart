//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:json_annotation/json_annotation.dart';

part 'share.g.dart';

@JsonSerializable(
  checked: true,
  createToJson: true,
  disallowUnrecognizedKeys: false,
  explicitToJson: true,
)
class Share {
  /// Returns a new [Share] instance.
  Share({required this.memberId, required this.amountMinor, this.weightMicros});

  @JsonKey(name: r'memberId', required: true, includeIfNull: false)
  final String memberId;

  // minimum: 0
  @JsonKey(name: r'amountMinor', required: true, includeIfNull: false)
  final int amountMinor;

  @JsonKey(name: r'weightMicros', required: false, includeIfNull: false)
  final int? weightMicros;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Share &&
          other.memberId == memberId &&
          other.amountMinor == amountMinor &&
          other.weightMicros == weightMicros;

  @override
  int get hashCode =>
      memberId.hashCode +
      amountMinor.hashCode +
      (weightMicros == null ? 0 : weightMicros.hashCode);

  factory Share.fromJson(Map<String, dynamic> json) => _$ShareFromJson(json);

  Map<String, dynamic> toJson() => _$ShareToJson(this);

  @override
  String toString() {
    return toJson().toString();
  }
}
