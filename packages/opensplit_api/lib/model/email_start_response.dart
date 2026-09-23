//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//
// @dart=2.18

// ignore_for_file: unused_element, unused_import
// ignore_for_file: always_put_required_named_parameters_first
// ignore_for_file: constant_identifier_names
// ignore_for_file: lines_longer_than_80_chars

part of openapi.api;

class EmailStartResponse {
  /// Returns a new [EmailStartResponse] instance.
  EmailStartResponse({
    required this.flow,
  });

  EmailFlow flow;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is EmailStartResponse && other.flow == flow;

  @override
  int get hashCode =>
      // ignore: unnecessary_parenthesis
      (flow.hashCode);

  @override
  String toString() => 'EmailStartResponse[flow=$flow]';

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{};
    json[r'flow'] = this.flow;
    return json;
  }

  /// Returns a new [EmailStartResponse] instance and imports its values from
  /// [value] if it's a [Map], null otherwise.
  // ignore: prefer_constructors_over_static_methods
  static EmailStartResponse? fromJson(dynamic value) {
    if (value is Map) {
      final json = value.cast<String, dynamic>();

      // Ensure that the map contains the required keys.
      // Note 1: the values aren't checked for validity beyond being non-null.
      // Note 2: this code is stripped in release mode!
      assert(() {
        assert(json.containsKey(r'flow'),
            'Required key "EmailStartResponse[flow]" is missing from JSON.');
        assert(json[r'flow'] != null,
            'Required key "EmailStartResponse[flow]" has a null value in JSON.');
        return true;
      }());

      return EmailStartResponse(
        flow: EmailFlow.fromJson(json[r'flow'])!,
      );
    }
    return null;
  }

  static List<EmailStartResponse> listFromJson(
    dynamic json, {
    bool growable = false,
  }) {
    final result = <EmailStartResponse>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = EmailStartResponse.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }

  static Map<String, EmailStartResponse> mapFromJson(dynamic json) {
    final map = <String, EmailStartResponse>{};
    if (json is Map && json.isNotEmpty) {
      json = json.cast<String, dynamic>(); // ignore: parameter_assignments
      for (final entry in json.entries) {
        final value = EmailStartResponse.fromJson(entry.value);
        if (value != null) {
          map[entry.key] = value;
        }
      }
    }
    return map;
  }

  // maps a json object with a list of EmailStartResponse-objects as value to a dart map
  static Map<String, List<EmailStartResponse>> mapListFromJson(
    dynamic json, {
    bool growable = false,
  }) {
    final map = <String, List<EmailStartResponse>>{};
    if (json is Map && json.isNotEmpty) {
      // ignore: parameter_assignments
      json = json.cast<String, dynamic>();
      for (final entry in json.entries) {
        map[entry.key] = EmailStartResponse.listFromJson(
          entry.value,
          growable: growable,
        );
      }
    }
    return map;
  }

  /// The list of required keys that must be present in a JSON.
  static const requiredKeys = <String>{
    'flow',
  };
}
