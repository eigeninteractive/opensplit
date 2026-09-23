//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//
// @dart=2.18

// ignore_for_file: unused_element, unused_import
// ignore_for_file: always_put_required_named_parameters_first
// ignore_for_file: constant_identifier_names
// ignore_for_file: lines_longer_than_80_chars

part of openapi.api;

/// stale: re-read, re-compose and send again. permanent: this will be refused identically forever; do not retry. transient: back off and try the same request again.
enum Retry {
  stale._(r'stale'),
  permanent._(r'permanent'),
  transient._(r'transient'),
  ;

  /// Instantiate a new enum with the provided value.
  const Retry._(this._value);

  /// The underlying value of this enum member.
  final String _value;

  @override
  String toString() => _value;

  /// Encodes this enum as a value suitable for JSON.
  String toJson() => _value;

  /// Returns the instance of [Retry] that was successfully decoded
  /// from the passed [value] on success, null otherwise.
  static Retry? fromJson(dynamic value) => RetryTypeTransformer().decode(value);

  /// Returns a [List] containing instances of [Retry]
  /// that were successfully decoded from the passed [JSON][json].
  static List<Retry> listFromJson(
    dynamic json, {
    bool growable = false,
  }) {
    final result = <Retry>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = Retry.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }
}

/// Transformation class that can [encode] an instance of [Retry] to String,
/// and [decode] dynamic data back to [Retry].
class RetryTypeTransformer {
  factory RetryTypeTransformer() =>
      _instance ??= const RetryTypeTransformer._();

  const RetryTypeTransformer._();

  /// Encodes this enum as a value suitable for JSON.
  String encode(Retry data) => data._value;

  /// Returns the instance of [Retry] that was successfully decoded
  /// from the passed [data] value on success, null otherwise.
  ///
  /// If [allowNull] is true and the [dynamic value][data] cannot be decoded successfully,
  /// then null is returned. However, if [allowNull] is false and the [dynamic value][data]
  /// cannot be decoded successfully, then an [UnimplementedError] is thrown.
  ///
  /// The [allowNull] is very handy when an API changes and a new enum value is added or removed,
  /// and users are still using an old app with the old code.
  Retry? decode(dynamic data, {bool allowNull = true}) {
    if (data is Retry) {
      return data;
    }
    if (data != null) {
      switch (data) {
        case r'stale':
          return Retry.stale;
        case r'permanent':
          return Retry.permanent;
        case r'transient':
          return Retry.transient;
        default:
          if (!allowNull) {
            throw ArgumentError('Unknown enum value to decode: $data');
          }
      }
    }
    return null;
  }

  /// The singleton instance of this transformer.
  static RetryTypeTransformer? _instance;
}
