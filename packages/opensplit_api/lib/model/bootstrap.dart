//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//
// @dart=2.18

// ignore_for_file: unused_element, unused_import
// ignore_for_file: always_put_required_named_parameters_first
// ignore_for_file: constant_identifier_names
// ignore_for_file: lines_longer_than_80_chars

part of openapi.api;

class Bootstrap {
  /// Returns a new [Bootstrap] instance.
  Bootstrap({
    required this.profileId,
    required this.displayName,
    required this.upiVpa,
    required this.isAnonymous,
    this.groupIds = const [],
  });

  String profileId;

  String? displayName;

  String? upiVpa;

  bool isAnonymous;

  List<String> groupIds;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Bootstrap &&
          other.profileId == profileId &&
          other.displayName == displayName &&
          other.upiVpa == upiVpa &&
          other.isAnonymous == isAnonymous &&
          _deepEquality.equals(other.groupIds, groupIds);

  @override
  int get hashCode =>
      // ignore: unnecessary_parenthesis
      (profileId.hashCode) +
      (displayName == null ? 0 : displayName!.hashCode) +
      (upiVpa == null ? 0 : upiVpa!.hashCode) +
      (isAnonymous.hashCode) +
      (groupIds.hashCode);

  @override
  String toString() =>
      'Bootstrap[profileId=$profileId, displayName=$displayName, upiVpa=$upiVpa, isAnonymous=$isAnonymous, groupIds=$groupIds]';

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{};
    json[r'profileId'] = this.profileId;
    if (this.displayName != null) {
      json[r'displayName'] = this.displayName;
    } else {
      json[r'displayName'] = null;
    }
    if (this.upiVpa != null) {
      json[r'upiVpa'] = this.upiVpa;
    } else {
      json[r'upiVpa'] = null;
    }
    json[r'isAnonymous'] = this.isAnonymous;
    json[r'groupIds'] = this.groupIds;
    return json;
  }

  /// Returns a new [Bootstrap] instance and imports its values from
  /// [value] if it's a [Map], null otherwise.
  // ignore: prefer_constructors_over_static_methods
  static Bootstrap? fromJson(dynamic value) {
    if (value is Map) {
      final json = value.cast<String, dynamic>();

      // Ensure that the map contains the required keys.
      // Note 1: the values aren't checked for validity beyond being non-null.
      // Note 2: this code is stripped in release mode!
      assert(() {
        assert(json.containsKey(r'profileId'),
            'Required key "Bootstrap[profileId]" is missing from JSON.');
        assert(json[r'profileId'] != null,
            'Required key "Bootstrap[profileId]" has a null value in JSON.');
        assert(json.containsKey(r'displayName'),
            'Required key "Bootstrap[displayName]" is missing from JSON.');
        assert(json.containsKey(r'upiVpa'),
            'Required key "Bootstrap[upiVpa]" is missing from JSON.');
        assert(json.containsKey(r'isAnonymous'),
            'Required key "Bootstrap[isAnonymous]" is missing from JSON.');
        assert(json[r'isAnonymous'] != null,
            'Required key "Bootstrap[isAnonymous]" has a null value in JSON.');
        assert(json.containsKey(r'groupIds'),
            'Required key "Bootstrap[groupIds]" is missing from JSON.');
        assert(json[r'groupIds'] != null,
            'Required key "Bootstrap[groupIds]" has a null value in JSON.');
        return true;
      }());

      return Bootstrap(
        profileId: mapValueOfType<String>(json, r'profileId')!,
        displayName: mapValueOfType<String>(json, r'displayName'),
        upiVpa: mapValueOfType<String>(json, r'upiVpa'),
        isAnonymous: mapValueOfType<bool>(json, r'isAnonymous')!,
        groupIds: json[r'groupIds'] is Iterable
            ? (json[r'groupIds'] as Iterable)
                .cast<String>()
                .toList(growable: false)
            : const [],
      );
    }
    return null;
  }

  static List<Bootstrap> listFromJson(
    dynamic json, {
    bool growable = false,
  }) {
    final result = <Bootstrap>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = Bootstrap.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }

  static Map<String, Bootstrap> mapFromJson(dynamic json) {
    final map = <String, Bootstrap>{};
    if (json is Map && json.isNotEmpty) {
      json = json.cast<String, dynamic>(); // ignore: parameter_assignments
      for (final entry in json.entries) {
        final value = Bootstrap.fromJson(entry.value);
        if (value != null) {
          map[entry.key] = value;
        }
      }
    }
    return map;
  }

  // maps a json object with a list of Bootstrap-objects as value to a dart map
  static Map<String, List<Bootstrap>> mapListFromJson(
    dynamic json, {
    bool growable = false,
  }) {
    final map = <String, List<Bootstrap>>{};
    if (json is Map && json.isNotEmpty) {
      // ignore: parameter_assignments
      json = json.cast<String, dynamic>();
      for (final entry in json.entries) {
        map[entry.key] = Bootstrap.listFromJson(
          entry.value,
          growable: growable,
        );
      }
    }
    return map;
  }

  /// The list of required keys that must be present in a JSON.
  static const requiredKeys = <String>{
    'profileId',
    'displayName',
    'upiVpa',
    'isAnonymous',
    'groupIds',
  };
}
