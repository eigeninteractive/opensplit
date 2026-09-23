//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//
// @dart=2.18

// ignore_for_file: unused_element, unused_import
// ignore_for_file: always_put_required_named_parameters_first
// ignore_for_file: constant_identifier_names
// ignore_for_file: lines_longer_than_80_chars

part of openapi.api;


enum SplitKind {
  equal._(r'equal'),
  exact._(r'exact'),
  shares._(r'shares'),
  percent._(r'percent'),
  ;

  /// Instantiate a new enum with the provided value.
  const SplitKind._(this._value);

  /// The underlying value of this enum member.
  final String _value;

  @override
  String toString() => _value;

  /// Encodes this enum as a value suitable for JSON.
  String toJson() => _value;

  /// Returns the instance of [SplitKind] that was successfully decoded
  /// from the passed [value] on success, null otherwise.
  static SplitKind? fromJson(dynamic value) => SplitKindTypeTransformer().decode(value);

  /// Returns a [List] containing instances of [SplitKind]
  /// that were successfully decoded from the passed [JSON][json].
  static List<SplitKind> listFromJson(dynamic json, {bool growable = false,}) {
    final result = <SplitKind>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = SplitKind.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }
}

/// Transformation class that can [encode] an instance of [SplitKind] to String,
/// and [decode] dynamic data back to [SplitKind].
class SplitKindTypeTransformer {
  factory SplitKindTypeTransformer() => _instance ??= const SplitKindTypeTransformer._();

  const SplitKindTypeTransformer._();

  /// Encodes this enum as a value suitable for JSON.
  String encode(SplitKind data) => data._value;

  /// Returns the instance of [SplitKind] that was successfully decoded
  /// from the passed [data] value on success, null otherwise.
  ///
  /// If [allowNull] is true and the [dynamic value][data] cannot be decoded successfully,
  /// then null is returned. However, if [allowNull] is false and the [dynamic value][data]
  /// cannot be decoded successfully, then an [UnimplementedError] is thrown.
  ///
  /// The [allowNull] is very handy when an API changes and a new enum value is added or removed,
  /// and users are still using an old app with the old code.
  SplitKind? decode(dynamic data, {bool allowNull = true}) {
    if (data is SplitKind) {
      return data;
    }
    if (data != null) {
      switch (data) {
        case r'equal': return SplitKind.equal;
        case r'exact': return SplitKind.exact;
        case r'shares': return SplitKind.shares;
        case r'percent': return SplitKind.percent;
        default:
          if (!allowNull) {
            throw ArgumentError('Unknown enum value to decode: $data');
          }
      }
    }
    return null;
  }

  /// The singleton instance of this transformer.
  static SplitKindTypeTransformer? _instance;
}

