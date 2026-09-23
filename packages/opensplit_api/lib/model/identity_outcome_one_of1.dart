//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//
// @dart=2.18

// ignore_for_file: unused_element, unused_import
// ignore_for_file: always_put_required_named_parameters_first
// ignore_for_file: constant_identifier_names
// ignore_for_file: lines_longer_than_80_chars

part of openapi.api;

class IdentityOutcomeOneOf1 {
  /// Returns a new [IdentityOutcomeOneOf1] instance.
  IdentityOutcomeOneOf1({
    required this.outcome,
    required this.account,
    required this.token,
    required this.strandedUserId,
  });

  IdentityOutcomeOneOf1OutcomeEnum outcome;

  Account account;

  String? token;

  String strandedUserId;

  @override
  bool operator ==(Object other) => identical(this, other) || other is IdentityOutcomeOneOf1 &&
    other.outcome == outcome &&
    other.account == account &&
    other.token == token &&
    other.strandedUserId == strandedUserId;

  @override
  int get hashCode =>
    // ignore: unnecessary_parenthesis
    (outcome.hashCode) +
    (account.hashCode) +
    (token == null ? 0 : token!.hashCode) +
    (strandedUserId.hashCode);

  @override
  String toString() => 'IdentityOutcomeOneOf1[outcome=$outcome, account=$account, token=$token, strandedUserId=$strandedUserId]';

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{};
      json[r'outcome'] = this.outcome;
      json[r'account'] = this.account;
    if (this.token != null) {
      json[r'token'] = this.token;
    } else {
      json[r'token'] = null;
    }
      json[r'strandedUserId'] = this.strandedUserId;
    return json;
  }

  /// Returns a new [IdentityOutcomeOneOf1] instance and imports its values from
  /// [value] if it's a [Map], null otherwise.
  // ignore: prefer_constructors_over_static_methods
  static IdentityOutcomeOneOf1? fromJson(dynamic value) {
    if (value is Map) {
      final json = value.cast<String, dynamic>();

      // Ensure that the map contains the required keys.
      // Note 1: the values aren't checked for validity beyond being non-null.
      // Note 2: this code is stripped in release mode!
      assert(() {
        assert(json.containsKey(r'outcome'), 'Required key "IdentityOutcomeOneOf1[outcome]" is missing from JSON.');
        assert(json[r'outcome'] != null, 'Required key "IdentityOutcomeOneOf1[outcome]" has a null value in JSON.');
        assert(json.containsKey(r'account'), 'Required key "IdentityOutcomeOneOf1[account]" is missing from JSON.');
        assert(json[r'account'] != null, 'Required key "IdentityOutcomeOneOf1[account]" has a null value in JSON.');
        assert(json.containsKey(r'token'), 'Required key "IdentityOutcomeOneOf1[token]" is missing from JSON.');
        assert(json.containsKey(r'strandedUserId'), 'Required key "IdentityOutcomeOneOf1[strandedUserId]" is missing from JSON.');
        assert(json[r'strandedUserId'] != null, 'Required key "IdentityOutcomeOneOf1[strandedUserId]" has a null value in JSON.');
        return true;
      }());

      return IdentityOutcomeOneOf1(
        outcome: IdentityOutcomeOneOf1OutcomeEnum.fromJson(json[r'outcome'])!,
        account: Account.fromJson(json[r'account'])!,
        token: mapValueOfType<String>(json, r'token'),
        strandedUserId: mapValueOfType<String>(json, r'strandedUserId')!,
      );
    }
    return null;
  }

  static List<IdentityOutcomeOneOf1> listFromJson(dynamic json, {bool growable = false,}) {
    final result = <IdentityOutcomeOneOf1>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = IdentityOutcomeOneOf1.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }

  static Map<String, IdentityOutcomeOneOf1> mapFromJson(dynamic json) {
    final map = <String, IdentityOutcomeOneOf1>{};
    if (json is Map && json.isNotEmpty) {
      json = json.cast<String, dynamic>(); // ignore: parameter_assignments
      for (final entry in json.entries) {
        final value = IdentityOutcomeOneOf1.fromJson(entry.value);
        if (value != null) {
          map[entry.key] = value;
        }
      }
    }
    return map;
  }

  // maps a json object with a list of IdentityOutcomeOneOf1-objects as value to a dart map
  static Map<String, List<IdentityOutcomeOneOf1>> mapListFromJson(dynamic json, {bool growable = false,}) {
    final map = <String, List<IdentityOutcomeOneOf1>>{};
    if (json is Map && json.isNotEmpty) {
      // ignore: parameter_assignments
      json = json.cast<String, dynamic>();
      for (final entry in json.entries) {
        map[entry.key] = IdentityOutcomeOneOf1.listFromJson(entry.value, growable: growable,);
      }
    }
    return map;
  }

  /// The list of required keys that must be present in a JSON.
  static const requiredKeys = <String>{
    'outcome',
    'account',
    'token',
    'strandedUserId',
  };
}


enum IdentityOutcomeOneOf1OutcomeEnum {
  replaced._(r'replaced'),
  ;

  /// Instantiate a new enum with the provided value.
  const IdentityOutcomeOneOf1OutcomeEnum._(this._value);

  /// The underlying value of this enum member.
  final String _value;

  @override
  String toString() => _value;

  /// Encodes this enum as a value suitable for JSON.
  String toJson() => _value;

  /// Returns the instance of [IdentityOutcomeOneOf1OutcomeEnum] that was successfully decoded
  /// from the passed [value] on success, null otherwise.
  static IdentityOutcomeOneOf1OutcomeEnum? fromJson(dynamic value) => IdentityOutcomeOneOf1OutcomeEnumTypeTransformer().decode(value);

  /// Returns a [List] containing instances of [IdentityOutcomeOneOf1OutcomeEnum]
  /// that were successfully decoded from the passed [JSON][json].
  static List<IdentityOutcomeOneOf1OutcomeEnum> listFromJson(dynamic json, {bool growable = false,}) {
    final result = <IdentityOutcomeOneOf1OutcomeEnum>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = IdentityOutcomeOneOf1OutcomeEnum.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }
}

/// Transformation class that can [encode] an instance of [IdentityOutcomeOneOf1OutcomeEnum] to String,
/// and [decode] dynamic data back to [IdentityOutcomeOneOf1OutcomeEnum].
class IdentityOutcomeOneOf1OutcomeEnumTypeTransformer {
  factory IdentityOutcomeOneOf1OutcomeEnumTypeTransformer() => _instance ??= const IdentityOutcomeOneOf1OutcomeEnumTypeTransformer._();

  const IdentityOutcomeOneOf1OutcomeEnumTypeTransformer._();

  String encode(IdentityOutcomeOneOf1OutcomeEnum data) => data._value;

  /// Returns the instance of [IdentityOutcomeOneOf1OutcomeEnum] that was successfully decoded
  /// from the passed [data] value on success, null otherwise.
  ///
  /// If [allowNull] is true and the [dynamic value][data] cannot be decoded successfully,
  /// then null is returned. However, if [allowNull] is false and the [dynamic value][data]
  /// cannot be decoded successfully, then an [UnimplementedError] is thrown.
  ///
  /// The [allowNull] is very handy when an API changes and a new enum value is added or removed,
  /// and users are still using an old app with the old code.
  IdentityOutcomeOneOf1OutcomeEnum? decode(dynamic data, {bool allowNull = true}) {
    if (data is IdentityOutcomeOneOf1OutcomeEnum) {
      return data;
    }
    if (data != null) {
      switch (data) {
        case r'replaced': return IdentityOutcomeOneOf1OutcomeEnum.replaced;
        default:
          if (!allowNull) {
            throw ArgumentError('Unknown enum value to decode: $data');
          }
      }
    }
    return null;
  }

  /// The singleton instance of this transformer.
  static IdentityOutcomeOneOf1OutcomeEnumTypeTransformer? _instance;
}


