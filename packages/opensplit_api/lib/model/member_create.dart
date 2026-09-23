//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//
// @dart=2.18

// ignore_for_file: unused_element, unused_import
// ignore_for_file: always_put_required_named_parameters_first
// ignore_for_file: constant_identifier_names
// ignore_for_file: lines_longer_than_80_chars

part of openapi.api;

class MemberCreate {
  /// Returns a new [MemberCreate] instance.
  MemberCreate({
    required this.id,
    required this.displayName,
    this.upiVpa,
  });

  String id;

  String displayName;

  String? upiVpa;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MemberCreate &&
          other.id == id &&
          other.displayName == displayName &&
          other.upiVpa == upiVpa;

  @override
  int get hashCode =>
      // ignore: unnecessary_parenthesis
      (id.hashCode) +
      (displayName.hashCode) +
      (upiVpa == null ? 0 : upiVpa!.hashCode);

  @override
  String toString() =>
      'MemberCreate[id=$id, displayName=$displayName, upiVpa=$upiVpa]';

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{};
    json[r'id'] = this.id;
    json[r'displayName'] = this.displayName;
    if (this.upiVpa != null) {
      json[r'upiVpa'] = this.upiVpa;
    } else {
      json[r'upiVpa'] = null;
    }
    return json;
  }

  /// Returns a new [MemberCreate] instance and imports its values from
  /// [value] if it's a [Map], null otherwise.
  // ignore: prefer_constructors_over_static_methods
  static MemberCreate? fromJson(dynamic value) {
    if (value is Map) {
      final json = value.cast<String, dynamic>();

      // Ensure that the map contains the required keys.
      // Note 1: the values aren't checked for validity beyond being non-null.
      // Note 2: this code is stripped in release mode!
      assert(() {
        assert(json.containsKey(r'id'),
            'Required key "MemberCreate[id]" is missing from JSON.');
        assert(json[r'id'] != null,
            'Required key "MemberCreate[id]" has a null value in JSON.');
        assert(json.containsKey(r'displayName'),
            'Required key "MemberCreate[displayName]" is missing from JSON.');
        assert(json[r'displayName'] != null,
            'Required key "MemberCreate[displayName]" has a null value in JSON.');
        return true;
      }());

      return MemberCreate(
        id: mapValueOfType<String>(json, r'id')!,
        displayName: mapValueOfType<String>(json, r'displayName')!,
        upiVpa: mapValueOfType<String>(json, r'upiVpa'),
      );
    }
    return null;
  }

  static List<MemberCreate> listFromJson(
    dynamic json, {
    bool growable = false,
  }) {
    final result = <MemberCreate>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = MemberCreate.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }

  static Map<String, MemberCreate> mapFromJson(dynamic json) {
    final map = <String, MemberCreate>{};
    if (json is Map && json.isNotEmpty) {
      json = json.cast<String, dynamic>(); // ignore: parameter_assignments
      for (final entry in json.entries) {
        final value = MemberCreate.fromJson(entry.value);
        if (value != null) {
          map[entry.key] = value;
        }
      }
    }
    return map;
  }

  // maps a json object with a list of MemberCreate-objects as value to a dart map
  static Map<String, List<MemberCreate>> mapListFromJson(
    dynamic json, {
    bool growable = false,
  }) {
    final map = <String, List<MemberCreate>>{};
    if (json is Map && json.isNotEmpty) {
      // ignore: parameter_assignments
      json = json.cast<String, dynamic>();
      for (final entry in json.entries) {
        map[entry.key] = MemberCreate.listFromJson(
          entry.value,
          growable: growable,
        );
      }
    }
    return map;
  }

  /// The list of required keys that must be present in a JSON.
  static const requiredKeys = <String>{
    'id',
    'displayName',
  };
}
