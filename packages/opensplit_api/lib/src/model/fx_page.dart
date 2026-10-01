//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:opensplit_api/src/model/fx_rate.dart';
import 'package:json_annotation/json_annotation.dart';

part 'fx_page.g.dart';

@JsonSerializable(
  checked: true,
  createToJson: true,
  disallowUnrecognizedKeys: false,
  explicitToJson: true,
)
class FxPage {
  /// Returns a new [FxPage] instance.
  FxPage({required this.rates, required this.hasMore});

  @JsonKey(name: r'rates', required: true, includeIfNull: false)
  final List<FxRate> rates;

  @JsonKey(name: r'hasMore', required: true, includeIfNull: false)
  final bool hasMore;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FxPage && other.rates == rates && other.hasMore == hasMore;

  @override
  int get hashCode => rates.hashCode + hasMore.hashCode;

  factory FxPage.fromJson(Map<String, dynamic> json) => _$FxPageFromJson(json);

  Map<String, dynamic> toJson() => _$FxPageToJson(this);

  @override
  String toString() {
    return toJson().toString();
  }
}
