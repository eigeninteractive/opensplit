//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//
// @dart=2.18

// ignore_for_file: unused_element, unused_import
// ignore_for_file: always_put_required_named_parameters_first
// ignore_for_file: constant_identifier_names
// ignore_for_file: lines_longer_than_80_chars

part of openapi.api;

class Health {
  /// Returns a new [Health] instance.
  Health({
    required this.ok,
    required this.service,
    required this.now,
  });

  bool ok;

  HealthServiceEnum service;

  DateTime now;

  @override
  bool operator ==(Object other) => identical(this, other) || other is Health &&
    other.ok == ok &&
    other.service == service &&
    other.now == now;

  @override
  int get hashCode =>
    // ignore: unnecessary_parenthesis
    (ok.hashCode) +
    (service.hashCode) +
    (now.hashCode);

  @override
  String toString() => 'Health[ok=$ok, service=$service, now=$now]';

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{};
      json[r'ok'] = this.ok;
      json[r'service'] = this.service;
      json[r'now'] = this.now.toUtc().toIso8601String();
    return json;
  }

  /// Returns a new [Health] instance and imports its values from
  /// [value] if it's a [Map], null otherwise.
  // ignore: prefer_constructors_over_static_methods
  static Health? fromJson(dynamic value) {
    if (value is Map) {
      final json = value.cast<String, dynamic>();

      // Ensure that the map contains the required keys.
      // Note 1: the values aren't checked for validity beyond being non-null.
      // Note 2: this code is stripped in release mode!
      assert(() {
        assert(json.containsKey(r'ok'), 'Required key "Health[ok]" is missing from JSON.');
        assert(json[r'ok'] != null, 'Required key "Health[ok]" has a null value in JSON.');
        assert(json.containsKey(r'service'), 'Required key "Health[service]" is missing from JSON.');
        assert(json[r'service'] != null, 'Required key "Health[service]" has a null value in JSON.');
        assert(json.containsKey(r'now'), 'Required key "Health[now]" is missing from JSON.');
        assert(json[r'now'] != null, 'Required key "Health[now]" has a null value in JSON.');
        return true;
      }());

      return Health(
        ok: mapValueOfType<bool>(json, r'ok')!,
        service: HealthServiceEnum.fromJson(json[r'service'])!,
        now: mapDateTime(json, r'now', r'')!,
      );
    }
    return null;
  }

  static List<Health> listFromJson(dynamic json, {bool growable = false,}) {
    final result = <Health>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = Health.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }

  static Map<String, Health> mapFromJson(dynamic json) {
    final map = <String, Health>{};
    if (json is Map && json.isNotEmpty) {
      json = json.cast<String, dynamic>(); // ignore: parameter_assignments
      for (final entry in json.entries) {
        final value = Health.fromJson(entry.value);
        if (value != null) {
          map[entry.key] = value;
        }
      }
    }
    return map;
  }

  // maps a json object with a list of Health-objects as value to a dart map
  static Map<String, List<Health>> mapListFromJson(dynamic json, {bool growable = false,}) {
    final map = <String, List<Health>>{};
    if (json is Map && json.isNotEmpty) {
      // ignore: parameter_assignments
      json = json.cast<String, dynamic>();
      for (final entry in json.entries) {
        map[entry.key] = Health.listFromJson(entry.value, growable: growable,);
      }
    }
    return map;
  }

  /// The list of required keys that must be present in a JSON.
  static const requiredKeys = <String>{
    'ok',
    'service',
    'now',
  };
}


enum HealthServiceEnum {
  opensplit._(r'opensplit'),
  ;

  /// Instantiate a new enum with the provided value.
  const HealthServiceEnum._(this._value);

  /// The underlying value of this enum member.
  final String _value;

  @override
  String toString() => _value;

  /// Encodes this enum as a value suitable for JSON.
  String toJson() => _value;

  /// Returns the instance of [HealthServiceEnum] that was successfully decoded
  /// from the passed [value] on success, null otherwise.
  static HealthServiceEnum? fromJson(dynamic value) => HealthServiceEnumTypeTransformer().decode(value);

  /// Returns a [List] containing instances of [HealthServiceEnum]
  /// that were successfully decoded from the passed [JSON][json].
  static List<HealthServiceEnum> listFromJson(dynamic json, {bool growable = false,}) {
    final result = <HealthServiceEnum>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = HealthServiceEnum.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }
}

/// Transformation class that can [encode] an instance of [HealthServiceEnum] to String,
/// and [decode] dynamic data back to [HealthServiceEnum].
class HealthServiceEnumTypeTransformer {
  factory HealthServiceEnumTypeTransformer() => _instance ??= const HealthServiceEnumTypeTransformer._();

  const HealthServiceEnumTypeTransformer._();

  String encode(HealthServiceEnum data) => data._value;

  /// Returns the instance of [HealthServiceEnum] that was successfully decoded
  /// from the passed [data] value on success, null otherwise.
  ///
  /// If [allowNull] is true and the [dynamic value][data] cannot be decoded successfully,
  /// then null is returned. However, if [allowNull] is false and the [dynamic value][data]
  /// cannot be decoded successfully, then an [UnimplementedError] is thrown.
  ///
  /// The [allowNull] is very handy when an API changes and a new enum value is added or removed,
  /// and users are still using an old app with the old code.
  HealthServiceEnum? decode(dynamic data, {bool allowNull = true}) {
    if (data is HealthServiceEnum) {
      return data;
    }
    if (data != null) {
      switch (data) {
        case r'opensplit': return HealthServiceEnum.opensplit;
        default:
          if (!allowNull) {
            throw ArgumentError('Unknown enum value to decode: $data');
          }
      }
    }
    return null;
  }

  /// The singleton instance of this transformer.
  static HealthServiceEnumTypeTransformer? _instance;
}


