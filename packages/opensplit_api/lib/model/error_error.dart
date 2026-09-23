//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//
// @dart=2.18

// ignore_for_file: unused_element, unused_import
// ignore_for_file: always_put_required_named_parameters_first
// ignore_for_file: constant_identifier_names
// ignore_for_file: lines_longer_than_80_chars

part of openapi.api;

class ErrorError {
  /// Returns a new [ErrorError] instance.
  ErrorError({
    required this.code,
    required this.message,
    required this.retry,
  });

  String code;

  String message;

  Retry retry;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ErrorError &&
          other.code == code &&
          other.message == message &&
          other.retry == retry;

  @override
  int get hashCode =>
      // ignore: unnecessary_parenthesis
      (code.hashCode) + (message.hashCode) + (retry.hashCode);

  @override
  String toString() => 'ErrorError[code=$code, message=$message, retry=$retry]';

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{};
    json[r'code'] = this.code;
    json[r'message'] = this.message;
    json[r'retry'] = this.retry;
    return json;
  }

  /// Returns a new [ErrorError] instance and imports its values from
  /// [value] if it's a [Map], null otherwise.
  // ignore: prefer_constructors_over_static_methods
  static ErrorError? fromJson(dynamic value) {
    if (value is Map) {
      final json = value.cast<String, dynamic>();

      // Ensure that the map contains the required keys.
      // Note 1: the values aren't checked for validity beyond being non-null.
      // Note 2: this code is stripped in release mode!
      assert(() {
        assert(json.containsKey(r'code'),
            'Required key "ErrorError[code]" is missing from JSON.');
        assert(json[r'code'] != null,
            'Required key "ErrorError[code]" has a null value in JSON.');
        assert(json.containsKey(r'message'),
            'Required key "ErrorError[message]" is missing from JSON.');
        assert(json[r'message'] != null,
            'Required key "ErrorError[message]" has a null value in JSON.');
        assert(json.containsKey(r'retry'),
            'Required key "ErrorError[retry]" is missing from JSON.');
        assert(json[r'retry'] != null,
            'Required key "ErrorError[retry]" has a null value in JSON.');
        return true;
      }());

      return ErrorError(
        code: mapValueOfType<String>(json, r'code')!,
        message: mapValueOfType<String>(json, r'message')!,
        retry: Retry.fromJson(json[r'retry'])!,
      );
    }
    return null;
  }

  static List<ErrorError> listFromJson(
    dynamic json, {
    bool growable = false,
  }) {
    final result = <ErrorError>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = ErrorError.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }

  static Map<String, ErrorError> mapFromJson(dynamic json) {
    final map = <String, ErrorError>{};
    if (json is Map && json.isNotEmpty) {
      json = json.cast<String, dynamic>(); // ignore: parameter_assignments
      for (final entry in json.entries) {
        final value = ErrorError.fromJson(entry.value);
        if (value != null) {
          map[entry.key] = value;
        }
      }
    }
    return map;
  }

  // maps a json object with a list of ErrorError-objects as value to a dart map
  static Map<String, List<ErrorError>> mapListFromJson(
    dynamic json, {
    bool growable = false,
  }) {
    final map = <String, List<ErrorError>>{};
    if (json is Map && json.isNotEmpty) {
      // ignore: parameter_assignments
      json = json.cast<String, dynamic>();
      for (final entry in json.entries) {
        map[entry.key] = ErrorError.listFromJson(
          entry.value,
          growable: growable,
        );
      }
    }
    return map;
  }

  /// The list of required keys that must be present in a JSON.
  static const requiredKeys = <String>{
    'code',
    'message',
    'retry',
  };
}
