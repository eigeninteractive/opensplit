//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//
// @dart=2.18

// ignore_for_file: unused_element, unused_import
// ignore_for_file: always_put_required_named_parameters_first
// ignore_for_file: constant_identifier_names
// ignore_for_file: lines_longer_than_80_chars

part of openapi.api;

class EmailStartRequest {
  /// Returns a new [EmailStartRequest] instance.
  EmailStartRequest({
    required this.email,
  });

  String email;

  @override
  bool operator ==(Object other) => identical(this, other) || other is EmailStartRequest &&
    other.email == email;

  @override
  int get hashCode =>
    // ignore: unnecessary_parenthesis
    (email.hashCode);

  @override
  String toString() => 'EmailStartRequest[email=$email]';

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{};
      json[r'email'] = this.email;
    return json;
  }

  /// Returns a new [EmailStartRequest] instance and imports its values from
  /// [value] if it's a [Map], null otherwise.
  // ignore: prefer_constructors_over_static_methods
  static EmailStartRequest? fromJson(dynamic value) {
    if (value is Map) {
      final json = value.cast<String, dynamic>();

      // Ensure that the map contains the required keys.
      // Note 1: the values aren't checked for validity beyond being non-null.
      // Note 2: this code is stripped in release mode!
      assert(() {
        assert(json.containsKey(r'email'), 'Required key "EmailStartRequest[email]" is missing from JSON.');
        assert(json[r'email'] != null, 'Required key "EmailStartRequest[email]" has a null value in JSON.');
        return true;
      }());

      return EmailStartRequest(
        email: mapValueOfType<String>(json, r'email')!,
      );
    }
    return null;
  }

  static List<EmailStartRequest> listFromJson(dynamic json, {bool growable = false,}) {
    final result = <EmailStartRequest>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = EmailStartRequest.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }

  static Map<String, EmailStartRequest> mapFromJson(dynamic json) {
    final map = <String, EmailStartRequest>{};
    if (json is Map && json.isNotEmpty) {
      json = json.cast<String, dynamic>(); // ignore: parameter_assignments
      for (final entry in json.entries) {
        final value = EmailStartRequest.fromJson(entry.value);
        if (value != null) {
          map[entry.key] = value;
        }
      }
    }
    return map;
  }

  // maps a json object with a list of EmailStartRequest-objects as value to a dart map
  static Map<String, List<EmailStartRequest>> mapListFromJson(dynamic json, {bool growable = false,}) {
    final map = <String, List<EmailStartRequest>>{};
    if (json is Map && json.isNotEmpty) {
      // ignore: parameter_assignments
      json = json.cast<String, dynamic>();
      for (final entry in json.entries) {
        map[entry.key] = EmailStartRequest.listFromJson(entry.value, growable: growable,);
      }
    }
    return map;
  }

  /// The list of required keys that must be present in a JSON.
  static const requiredKeys = <String>{
    'email',
  };
}

