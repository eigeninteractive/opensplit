//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:opensplit_api/src/model/category.dart';
import 'package:opensplit_api/src/model/currency.dart';
import 'package:json_annotation/json_annotation.dart';

part 'reference.g.dart';

@JsonSerializable(
  checked: true,
  createToJson: true,
  disallowUnrecognizedKeys: false,
  explicitToJson: true,
)
class Reference {
  /// Returns a new [Reference] instance.
  Reference({required this.currencies, required this.categories});

  @JsonKey(name: r'currencies', required: true, includeIfNull: false)
  final List<Currency> currencies;

  @JsonKey(name: r'categories', required: true, includeIfNull: false)
  final List<Category> categories;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Reference &&
          other.currencies == currencies &&
          other.categories == categories;

  @override
  int get hashCode => currencies.hashCode + categories.hashCode;

  factory Reference.fromJson(Map<String, dynamic> json) =>
      _$ReferenceFromJson(json);

  Map<String, dynamic> toJson() => _$ReferenceToJson(this);

  @override
  String toString() {
    return toJson().toString();
  }
}
