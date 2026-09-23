//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//
// @dart=2.18

// ignore_for_file: unused_element, unused_import
// ignore_for_file: always_put_required_named_parameters_first
// ignore_for_file: constant_identifier_names
// ignore_for_file: lines_longer_than_80_chars

part of openapi.api;

class IdentityOutcome {
  /// Returns a new [IdentityOutcome] instance.
  IdentityOutcome({
    required this.outcome,
    required this.account,
    required this.token,
    required this.strandedUserId,
  });

  IdentityOutcomeOutcomeEnum outcome;

  Account account;

  String? token;

  String strandedUserId;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is IdentityOutcome &&
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
  String toString() =>
      'IdentityOutcome[outcome=$outcome, account=$account, token=$token, strandedUserId=$strandedUserId]';

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

  /// Returns a new [IdentityOutcome] instance and imports its values from
  /// [value] if it's a [Map], null otherwise.
  // ignore: prefer_constructors_over_static_methods
  static IdentityOutcome? fromJson(dynamic value) {
    if (value is Map) {
      final json = value.cast<String, dynamic>();

      // Ensure that the map contains the required keys.
      // Note 1: the values aren't checked for validity beyond being non-null.
      // Note 2: this code is stripped in release mode!
      assert(() {
        assert(json.containsKey(r'outcome'),
            'Required key "IdentityOutcome[outcome]" is missing from JSON.');
        assert(json[r'outcome'] != null,
            'Required key "IdentityOutcome[outcome]" has a null value in JSON.');
        assert(json.containsKey(r'account'),
            'Required key "IdentityOutcome[account]" is missing from JSON.');
        assert(json[r'account'] != null,
            'Required key "IdentityOutcome[account]" has a null value in JSON.');
        assert(json.containsKey(r'token'),
            'Required key "IdentityOutcome[token]" is missing from JSON.');
        assert(json.containsKey(r'strandedUserId'),
            'Required key "IdentityOutcome[strandedUserId]" is missing from JSON.');
        assert(json[r'strandedUserId'] != null,
            'Required key "IdentityOutcome[strandedUserId]" has a null value in JSON.');
        return true;
      }());

      return IdentityOutcome(
        outcome: IdentityOutcomeOutcomeEnum.fromJson(json[r'outcome'])!,
        account: Account.fromJson(json[r'account'])!,
        token: mapValueOfType<String>(json, r'token'),
        strandedUserId: mapValueOfType<String>(json, r'strandedUserId')!,
      );
    }
    return null;
  }

  static List<IdentityOutcome> listFromJson(
    dynamic json, {
    bool growable = false,
  }) {
    final result = <IdentityOutcome>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = IdentityOutcome.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }

  static Map<String, IdentityOutcome> mapFromJson(dynamic json) {
    final map = <String, IdentityOutcome>{};
    if (json is Map && json.isNotEmpty) {
      json = json.cast<String, dynamic>(); // ignore: parameter_assignments
      for (final entry in json.entries) {
        final value = IdentityOutcome.fromJson(entry.value);
        if (value != null) {
          map[entry.key] = value;
        }
      }
    }
    return map;
  }

  // maps a json object with a list of IdentityOutcome-objects as value to a dart map
  static Map<String, List<IdentityOutcome>> mapListFromJson(
    dynamic json, {
    bool growable = false,
  }) {
    final map = <String, List<IdentityOutcome>>{};
    if (json is Map && json.isNotEmpty) {
      // ignore: parameter_assignments
      json = json.cast<String, dynamic>();
      for (final entry in json.entries) {
        map[entry.key] = IdentityOutcome.listFromJson(
          entry.value,
          growable: growable,
        );
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

enum IdentityOutcomeOutcomeEnum {
  replaced._(r'replaced'),
  ;

  /// Instantiate a new enum with the provided value.
  const IdentityOutcomeOutcomeEnum._(this._value);

  /// The underlying value of this enum member.
  final String _value;

  @override
  String toString() => _value;

  /// Encodes this enum as a value suitable for JSON.
  String toJson() => _value;

  /// Returns the instance of [IdentityOutcomeOutcomeEnum] that was successfully decoded
  /// from the passed [value] on success, null otherwise.
  static IdentityOutcomeOutcomeEnum? fromJson(dynamic value) =>
      IdentityOutcomeOutcomeEnumTypeTransformer().decode(value);

  /// Returns a [List] containing instances of [IdentityOutcomeOutcomeEnum]
  /// that were successfully decoded from the passed [JSON][json].
  static List<IdentityOutcomeOutcomeEnum> listFromJson(
    dynamic json, {
    bool growable = false,
  }) {
    final result = <IdentityOutcomeOutcomeEnum>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = IdentityOutcomeOutcomeEnum.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }
}

/// Transformation class that can [encode] an instance of [IdentityOutcomeOutcomeEnum] to String,
/// and [decode] dynamic data back to [IdentityOutcomeOutcomeEnum].
class IdentityOutcomeOutcomeEnumTypeTransformer {
  factory IdentityOutcomeOutcomeEnumTypeTransformer() =>
      _instance ??= const IdentityOutcomeOutcomeEnumTypeTransformer._();

  const IdentityOutcomeOutcomeEnumTypeTransformer._();

  String encode(IdentityOutcomeOutcomeEnum data) => data._value;

  /// Returns the instance of [IdentityOutcomeOutcomeEnum] that was successfully decoded
  /// from the passed [data] value on success, null otherwise.
  ///
  /// If [allowNull] is true and the [dynamic value][data] cannot be decoded successfully,
  /// then null is returned. However, if [allowNull] is false and the [dynamic value][data]
  /// cannot be decoded successfully, then an [UnimplementedError] is thrown.
  ///
  /// The [allowNull] is very handy when an API changes and a new enum value is added or removed,
  /// and users are still using an old app with the old code.
  IdentityOutcomeOutcomeEnum? decode(dynamic data, {bool allowNull = true}) {
    if (data is IdentityOutcomeOutcomeEnum) {
      return data;
    }
    if (data != null) {
      switch (data) {
        case r'replaced':
          return IdentityOutcomeOutcomeEnum.replaced;
        default:
          if (!allowNull) {
            throw ArgumentError('Unknown enum value to decode: $data');
          }
      }
    }
    return null;
  }

  /// The singleton instance of this transformer.
  static IdentityOutcomeOutcomeEnumTypeTransformer? _instance;
}
