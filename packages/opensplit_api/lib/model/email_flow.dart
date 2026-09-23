//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//
// @dart=2.18

// ignore_for_file: unused_element, unused_import
// ignore_for_file: always_put_required_named_parameters_first
// ignore_for_file: constant_identifier_names
// ignore_for_file: lines_longer_than_80_chars

part of openapi.api;

/// linkPending: verifying keeps the current account id, so every group on this device still belongs to it. signInPending: the address already had an account, so verifying REPLACES the session, and anything recorded as a guest stays with the guest account.
enum EmailFlow {
  linkPending._(r'linkPending'),
  signInPending._(r'signInPending'),
  ;

  /// Instantiate a new enum with the provided value.
  const EmailFlow._(this._value);

  /// The underlying value of this enum member.
  final String _value;

  @override
  String toString() => _value;

  /// Encodes this enum as a value suitable for JSON.
  String toJson() => _value;

  /// Returns the instance of [EmailFlow] that was successfully decoded
  /// from the passed [value] on success, null otherwise.
  static EmailFlow? fromJson(dynamic value) =>
      EmailFlowTypeTransformer().decode(value);

  /// Returns a [List] containing instances of [EmailFlow]
  /// that were successfully decoded from the passed [JSON][json].
  static List<EmailFlow> listFromJson(
    dynamic json, {
    bool growable = false,
  }) {
    final result = <EmailFlow>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = EmailFlow.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }
}

/// Transformation class that can [encode] an instance of [EmailFlow] to String,
/// and [decode] dynamic data back to [EmailFlow].
class EmailFlowTypeTransformer {
  factory EmailFlowTypeTransformer() =>
      _instance ??= const EmailFlowTypeTransformer._();

  const EmailFlowTypeTransformer._();

  /// Encodes this enum as a value suitable for JSON.
  String encode(EmailFlow data) => data._value;

  /// Returns the instance of [EmailFlow] that was successfully decoded
  /// from the passed [data] value on success, null otherwise.
  ///
  /// If [allowNull] is true and the [dynamic value][data] cannot be decoded successfully,
  /// then null is returned. However, if [allowNull] is false and the [dynamic value][data]
  /// cannot be decoded successfully, then an [UnimplementedError] is thrown.
  ///
  /// The [allowNull] is very handy when an API changes and a new enum value is added or removed,
  /// and users are still using an old app with the old code.
  EmailFlow? decode(dynamic data, {bool allowNull = true}) {
    if (data is EmailFlow) {
      return data;
    }
    if (data != null) {
      switch (data) {
        case r'linkPending':
          return EmailFlow.linkPending;
        case r'signInPending':
          return EmailFlow.signInPending;
        default:
          if (!allowNull) {
            throw ArgumentError('Unknown enum value to decode: $data');
          }
      }
    }
    return null;
  }

  /// The singleton instance of this transformer.
  static EmailFlowTypeTransformer? _instance;
}
