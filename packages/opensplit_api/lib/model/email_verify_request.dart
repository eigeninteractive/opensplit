//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//
// @dart=2.18

// ignore_for_file: unused_element, unused_import
// ignore_for_file: always_put_required_named_parameters_first
// ignore_for_file: constant_identifier_names
// ignore_for_file: lines_longer_than_80_chars

part of openapi.api;

class EmailVerifyRequest {
  /// Returns a new [EmailVerifyRequest] instance.
  EmailVerifyRequest({
    required this.email,
    required this.code,
    required this.flow,
  });

  String email;

  String code;

  EmailFlow flow;

  @override
  bool operator ==(Object other) => identical(this, other) || other is EmailVerifyRequest &&
    other.email == email &&
    other.code == code &&
    other.flow == flow;

  @override
  int get hashCode =>
    // ignore: unnecessary_parenthesis
    (email.hashCode) +
    (code.hashCode) +
    (flow.hashCode);

  @override
  String toString() => 'EmailVerifyRequest[email=$email, code=$code, flow=$flow]';

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{};
      json[r'email'] = this.email;
      json[r'code'] = this.code;
      json[r'flow'] = this.flow;
    return json;
  }

  /// Returns a new [EmailVerifyRequest] instance and imports its values from
  /// [value] if it's a [Map], null otherwise.
  // ignore: prefer_constructors_over_static_methods
  static EmailVerifyRequest? fromJson(dynamic value) {
    if (value is Map) {
      final json = value.cast<String, dynamic>();

      // Ensure that the map contains the required keys.
      // Note 1: the values aren't checked for validity beyond being non-null.
      // Note 2: this code is stripped in release mode!
      assert(() {
        assert(json.containsKey(r'email'), 'Required key "EmailVerifyRequest[email]" is missing from JSON.');
        assert(json[r'email'] != null, 'Required key "EmailVerifyRequest[email]" has a null value in JSON.');
        assert(json.containsKey(r'code'), 'Required key "EmailVerifyRequest[code]" is missing from JSON.');
        assert(json[r'code'] != null, 'Required key "EmailVerifyRequest[code]" has a null value in JSON.');
        assert(json.containsKey(r'flow'), 'Required key "EmailVerifyRequest[flow]" is missing from JSON.');
        assert(json[r'flow'] != null, 'Required key "EmailVerifyRequest[flow]" has a null value in JSON.');
        return true;
      }());

      return EmailVerifyRequest(
        email: mapValueOfType<String>(json, r'email')!,
        code: mapValueOfType<String>(json, r'code')!,
        flow: EmailFlow.fromJson(json[r'flow'])!,
      );
    }
    return null;
  }

  static List<EmailVerifyRequest> listFromJson(dynamic json, {bool growable = false,}) {
    final result = <EmailVerifyRequest>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = EmailVerifyRequest.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }

  static Map<String, EmailVerifyRequest> mapFromJson(dynamic json) {
    final map = <String, EmailVerifyRequest>{};
    if (json is Map && json.isNotEmpty) {
      json = json.cast<String, dynamic>(); // ignore: parameter_assignments
      for (final entry in json.entries) {
        final value = EmailVerifyRequest.fromJson(entry.value);
        if (value != null) {
          map[entry.key] = value;
        }
      }
    }
    return map;
  }

  // maps a json object with a list of EmailVerifyRequest-objects as value to a dart map
  static Map<String, List<EmailVerifyRequest>> mapListFromJson(dynamic json, {bool growable = false,}) {
    final map = <String, List<EmailVerifyRequest>>{};
    if (json is Map && json.isNotEmpty) {
      // ignore: parameter_assignments
      json = json.cast<String, dynamic>();
      for (final entry in json.entries) {
        map[entry.key] = EmailVerifyRequest.listFromJson(entry.value, growable: growable,);
      }
    }
    return map;
  }

  /// The list of required keys that must be present in a JSON.
  static const requiredKeys = <String>{
    'email',
    'code',
    'flow',
  };
}

