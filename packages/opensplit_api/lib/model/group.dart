//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//
// @dart=2.18

// ignore_for_file: unused_element, unused_import
// ignore_for_file: always_put_required_named_parameters_first
// ignore_for_file: constant_identifier_names
// ignore_for_file: lines_longer_than_80_chars

part of openapi.api;

class Group {
  /// Returns a new [Group] instance.
  Group({
    required this.id,
    required this.name,
    required this.defaultCurrency,
    required this.isDirect,
    required this.simplifyDebts,
    required this.createdBy,
    required this.createdAt,
    required this.archivedAt,
    required this.updatedAt,
    required this.seq,
  });

  String id;

  String name;

  String defaultCurrency;

  bool isDirect;

  bool simplifyDebts;

  String createdBy;

  DateTime createdAt;

  DateTime? archivedAt;

  DateTime updatedAt;

  /// Minimum value: 0
  int seq;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Group &&
          other.id == id &&
          other.name == name &&
          other.defaultCurrency == defaultCurrency &&
          other.isDirect == isDirect &&
          other.simplifyDebts == simplifyDebts &&
          other.createdBy == createdBy &&
          other.createdAt == createdAt &&
          other.archivedAt == archivedAt &&
          other.updatedAt == updatedAt &&
          other.seq == seq;

  @override
  int get hashCode =>
      // ignore: unnecessary_parenthesis
      (id.hashCode) +
      (name.hashCode) +
      (defaultCurrency.hashCode) +
      (isDirect.hashCode) +
      (simplifyDebts.hashCode) +
      (createdBy.hashCode) +
      (createdAt.hashCode) +
      (archivedAt == null ? 0 : archivedAt!.hashCode) +
      (updatedAt.hashCode) +
      (seq.hashCode);

  @override
  String toString() =>
      'Group[id=$id, name=$name, defaultCurrency=$defaultCurrency, isDirect=$isDirect, simplifyDebts=$simplifyDebts, createdBy=$createdBy, createdAt=$createdAt, archivedAt=$archivedAt, updatedAt=$updatedAt, seq=$seq]';

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{};
    json[r'id'] = this.id;
    json[r'name'] = this.name;
    json[r'defaultCurrency'] = this.defaultCurrency;
    json[r'isDirect'] = this.isDirect;
    json[r'simplifyDebts'] = this.simplifyDebts;
    json[r'createdBy'] = this.createdBy;
    json[r'createdAt'] = this.createdAt.toUtc().toIso8601String();
    if (this.archivedAt != null) {
      json[r'archivedAt'] = this.archivedAt!.toUtc().toIso8601String();
    } else {
      json[r'archivedAt'] = null;
    }
    json[r'updatedAt'] = this.updatedAt.toUtc().toIso8601String();
    json[r'seq'] = this.seq;
    return json;
  }

  /// Returns a new [Group] instance and imports its values from
  /// [value] if it's a [Map], null otherwise.
  // ignore: prefer_constructors_over_static_methods
  static Group? fromJson(dynamic value) {
    if (value is Map) {
      final json = value.cast<String, dynamic>();

      // Ensure that the map contains the required keys.
      // Note 1: the values aren't checked for validity beyond being non-null.
      // Note 2: this code is stripped in release mode!
      assert(() {
        assert(json.containsKey(r'id'),
            'Required key "Group[id]" is missing from JSON.');
        assert(json[r'id'] != null,
            'Required key "Group[id]" has a null value in JSON.');
        assert(json.containsKey(r'name'),
            'Required key "Group[name]" is missing from JSON.');
        assert(json[r'name'] != null,
            'Required key "Group[name]" has a null value in JSON.');
        assert(json.containsKey(r'defaultCurrency'),
            'Required key "Group[defaultCurrency]" is missing from JSON.');
        assert(json[r'defaultCurrency'] != null,
            'Required key "Group[defaultCurrency]" has a null value in JSON.');
        assert(json.containsKey(r'isDirect'),
            'Required key "Group[isDirect]" is missing from JSON.');
        assert(json[r'isDirect'] != null,
            'Required key "Group[isDirect]" has a null value in JSON.');
        assert(json.containsKey(r'simplifyDebts'),
            'Required key "Group[simplifyDebts]" is missing from JSON.');
        assert(json[r'simplifyDebts'] != null,
            'Required key "Group[simplifyDebts]" has a null value in JSON.');
        assert(json.containsKey(r'createdBy'),
            'Required key "Group[createdBy]" is missing from JSON.');
        assert(json[r'createdBy'] != null,
            'Required key "Group[createdBy]" has a null value in JSON.');
        assert(json.containsKey(r'createdAt'),
            'Required key "Group[createdAt]" is missing from JSON.');
        assert(json[r'createdAt'] != null,
            'Required key "Group[createdAt]" has a null value in JSON.');
        assert(json.containsKey(r'archivedAt'),
            'Required key "Group[archivedAt]" is missing from JSON.');
        assert(json.containsKey(r'updatedAt'),
            'Required key "Group[updatedAt]" is missing from JSON.');
        assert(json[r'updatedAt'] != null,
            'Required key "Group[updatedAt]" has a null value in JSON.');
        assert(json.containsKey(r'seq'),
            'Required key "Group[seq]" is missing from JSON.');
        assert(json[r'seq'] != null,
            'Required key "Group[seq]" has a null value in JSON.');
        return true;
      }());

      return Group(
        id: mapValueOfType<String>(json, r'id')!,
        name: mapValueOfType<String>(json, r'name')!,
        defaultCurrency: mapValueOfType<String>(json, r'defaultCurrency')!,
        isDirect: mapValueOfType<bool>(json, r'isDirect')!,
        simplifyDebts: mapValueOfType<bool>(json, r'simplifyDebts')!,
        createdBy: mapValueOfType<String>(json, r'createdBy')!,
        createdAt: mapDateTime(json, r'createdAt', r'')!,
        archivedAt: mapDateTime(json, r'archivedAt', r''),
        updatedAt: mapDateTime(json, r'updatedAt', r'')!,
        seq: mapValueOfType<int>(json, r'seq')!,
      );
    }
    return null;
  }

  static List<Group> listFromJson(
    dynamic json, {
    bool growable = false,
  }) {
    final result = <Group>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = Group.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }

  static Map<String, Group> mapFromJson(dynamic json) {
    final map = <String, Group>{};
    if (json is Map && json.isNotEmpty) {
      json = json.cast<String, dynamic>(); // ignore: parameter_assignments
      for (final entry in json.entries) {
        final value = Group.fromJson(entry.value);
        if (value != null) {
          map[entry.key] = value;
        }
      }
    }
    return map;
  }

  // maps a json object with a list of Group-objects as value to a dart map
  static Map<String, List<Group>> mapListFromJson(
    dynamic json, {
    bool growable = false,
  }) {
    final map = <String, List<Group>>{};
    if (json is Map && json.isNotEmpty) {
      // ignore: parameter_assignments
      json = json.cast<String, dynamic>();
      for (final entry in json.entries) {
        map[entry.key] = Group.listFromJson(
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
    'name',
    'defaultCurrency',
    'isDirect',
    'simplifyDebts',
    'createdBy',
    'createdAt',
    'archivedAt',
    'updatedAt',
    'seq',
  };
}
