//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:json_annotation/json_annotation.dart';

part 'account_deletion.g.dart';

@JsonSerializable(
  checked: true,
  createToJson: true,
  disallowUnrecognizedKeys: false,
  explicitToJson: true,
)
class AccountDeletion {
  /// Returns a new [AccountDeletion] instance.
  AccountDeletion({required this.forgotten, required this.purged});

  // minimum: 0
  @JsonKey(name: r'forgotten', required: true, includeIfNull: false)
  final int forgotten;

  // minimum: 0
  @JsonKey(name: r'purged', required: true, includeIfNull: false)
  final int purged;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AccountDeletion &&
          other.forgotten == forgotten &&
          other.purged == purged;

  @override
  int get hashCode => forgotten.hashCode + purged.hashCode;

  factory AccountDeletion.fromJson(Map<String, dynamic> json) =>
      _$AccountDeletionFromJson(json);

  Map<String, dynamic> toJson() => _$AccountDeletionToJson(this);

  @override
  String toString() {
    return toJson().toString();
  }
}
