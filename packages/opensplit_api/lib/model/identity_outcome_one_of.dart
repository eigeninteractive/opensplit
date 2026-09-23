//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//
// @dart=2.18

// ignore_for_file: unused_element, unused_import
// ignore_for_file: always_put_required_named_parameters_first
// ignore_for_file: constant_identifier_names
// ignore_for_file: lines_longer_than_80_chars

part of openapi.api;

class IdentityOutcomeOneOf {
  /// Returns a new [IdentityOutcomeOneOf] instance.
  IdentityOutcomeOneOf({
    required this.outcome,
    required this.account,
    required this.token,
  });

  IdentityOutcomeOneOfOutcomeEnum outcome;

  Account account;

  String? token;

  @override
  bool operator ==(Object other) => identical(this, other) || other is IdentityOutcomeOneOf &&
    other.outcome == outcome &&
    other.account == account &&
    other.token == token;

  @override
  int get hashCode =>
    // ignore: unnecessary_parenthesis
    (outcome.hashCode) +
    (account.hashCode) +
    (token == null ? 0 : token!.hashCode);

  @override
  String toString() => 'IdentityOutcomeOneOf[outcome=$outcome, account=$account, token=$token]';

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{};
      json[r'outcome'] = this.outcome;
      json[r'account'] = this.account;
    if (this.token != null) {
      json[r'token'] = this.token;
    } else {
      json[r'token'] = null;
    }
    return json;
  }

  /// Returns a new [IdentityOutcomeOneOf] instance and imports its values from
  /// [value] if it's a [Map], null otherwise.
  // ignore: prefer_constructors_over_static_methods
  static IdentityOutcomeOneOf? fromJson(dynamic value) {
    if (value is Map) {
      final json = value.cast<String, dynamic>();

      // Ensure that the map contains the required keys.
      // Note 1: the values aren't checked for validity beyond being non-null.
      // Note 2: this code is stripped in release mode!
      assert(() {
        assert(json.containsKey(r'outcome'), 'Required key "IdentityOutcomeOneOf[outcome]" is missing from JSON.');
        assert(json[r'outcome'] != null, 'Required key "IdentityOutcomeOneOf[outcome]" has a null value in JSON.');
        assert(json.containsKey(r'account'), 'Required key "IdentityOutcomeOneOf[account]" is missing from JSON.');
        assert(json[r'account'] != null, 'Required key "IdentityOutcomeOneOf[account]" has a null value in JSON.');
        assert(json.containsKey(r'token'), 'Required key "IdentityOutcomeOneOf[token]" is missing from JSON.');
        return true;
      }());

      return IdentityOutcomeOneOf(
        outcome: IdentityOutcomeOneOfOutcomeEnum.fromJson(json[r'outcome'])!,
        account: Account.fromJson(json[r'account'])!,
        token: mapValueOfType<String>(json, r'token'),
      );
    }
    return null;
  }

  static List<IdentityOutcomeOneOf> listFromJson(dynamic json, {bool growable = false,}) {
    final result = <IdentityOutcomeOneOf>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = IdentityOutcomeOneOf.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }

  static Map<String, IdentityOutcomeOneOf> mapFromJson(dynamic json) {
    final map = <String, IdentityOutcomeOneOf>{};
    if (json is Map && json.isNotEmpty) {
      json = json.cast<String, dynamic>(); // ignore: parameter_assignments
      for (final entry in json.entries) {
        final value = IdentityOutcomeOneOf.fromJson(entry.value);
        if (value != null) {
          map[entry.key] = value;
        }
      }
    }
    return map;
  }

  // maps a json object with a list of IdentityOutcomeOneOf-objects as value to a dart map
  static Map<String, List<IdentityOutcomeOneOf>> mapListFromJson(dynamic json, {bool growable = false,}) {
    final map = <String, List<IdentityOutcomeOneOf>>{};
    if (json is Map && json.isNotEmpty) {
      // ignore: parameter_assignments
      json = json.cast<String, dynamic>();
      for (final entry in json.entries) {
        map[entry.key] = IdentityOutcomeOneOf.listFromJson(entry.value, growable: growable,);
      }
    }
    return map;
  }

  /// The list of required keys that must be present in a JSON.
  static const requiredKeys = <String>{
    'outcome',
    'account',
    'token',
  };
}


enum IdentityOutcomeOneOfOutcomeEnum {
  kept._(r'kept'),
  ;

  /// Instantiate a new enum with the provided value.
  const IdentityOutcomeOneOfOutcomeEnum._(this._value);

  /// The underlying value of this enum member.
  final String _value;

  @override
  String toString() => _value;

  /// Encodes this enum as a value suitable for JSON.
  String toJson() => _value;

  /// Returns the instance of [IdentityOutcomeOneOfOutcomeEnum] that was successfully decoded
  /// from the passed [value] on success, null otherwise.
  static IdentityOutcomeOneOfOutcomeEnum? fromJson(dynamic value) => IdentityOutcomeOneOfOutcomeEnumTypeTransformer().decode(value);

  /// Returns a [List] containing instances of [IdentityOutcomeOneOfOutcomeEnum]
  /// that were successfully decoded from the passed [JSON][json].
  static List<IdentityOutcomeOneOfOutcomeEnum> listFromJson(dynamic json, {bool growable = false,}) {
    final result = <IdentityOutcomeOneOfOutcomeEnum>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = IdentityOutcomeOneOfOutcomeEnum.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }
}

/// Transformation class that can [encode] an instance of [IdentityOutcomeOneOfOutcomeEnum] to String,
/// and [decode] dynamic data back to [IdentityOutcomeOneOfOutcomeEnum].
class IdentityOutcomeOneOfOutcomeEnumTypeTransformer {
  factory IdentityOutcomeOneOfOutcomeEnumTypeTransformer() => _instance ??= const IdentityOutcomeOneOfOutcomeEnumTypeTransformer._();

  const IdentityOutcomeOneOfOutcomeEnumTypeTransformer._();

  String encode(IdentityOutcomeOneOfOutcomeEnum data) => data._value;

  /// Returns the instance of [IdentityOutcomeOneOfOutcomeEnum] that was successfully decoded
  /// from the passed [data] value on success, null otherwise.
  ///
  /// If [allowNull] is true and the [dynamic value][data] cannot be decoded successfully,
  /// then null is returned. However, if [allowNull] is false and the [dynamic value][data]
  /// cannot be decoded successfully, then an [UnimplementedError] is thrown.
  ///
  /// The [allowNull] is very handy when an API changes and a new enum value is added or removed,
  /// and users are still using an old app with the old code.
  IdentityOutcomeOneOfOutcomeEnum? decode(dynamic data, {bool allowNull = true}) {
    if (data is IdentityOutcomeOneOfOutcomeEnum) {
      return data;
    }
    if (data != null) {
      switch (data) {
        case r'kept': return IdentityOutcomeOneOfOutcomeEnum.kept;
        default:
          if (!allowNull) {
            throw ArgumentError('Unknown enum value to decode: $data');
          }
      }
    }
    return null;
  }

  /// The singleton instance of this transformer.
  static IdentityOutcomeOneOfOutcomeEnumTypeTransformer? _instance;
}


