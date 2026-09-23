//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//
// @dart=2.18

// ignore_for_file: unused_element, unused_import
// ignore_for_file: always_put_required_named_parameters_first
// ignore_for_file: constant_identifier_names
// ignore_for_file: lines_longer_than_80_chars

part of openapi.api;

class GroupCreate {
  /// Returns a new [GroupCreate] instance.
  GroupCreate({
    required this.id,
    required this.name,
    required this.defaultCurrency,
    this.isDirect = false,
    this.simplifyDebts = true,
    required this.memberId,
    required this.displayName,
  });

  String id;

  String name;

  String defaultCurrency;

  bool isDirect;

  bool simplifyDebts;

  String memberId;

  String displayName;

  @override
  bool operator ==(Object other) => identical(this, other) || other is GroupCreate &&
    other.id == id &&
    other.name == name &&
    other.defaultCurrency == defaultCurrency &&
    other.isDirect == isDirect &&
    other.simplifyDebts == simplifyDebts &&
    other.memberId == memberId &&
    other.displayName == displayName;

  @override
  int get hashCode =>
    // ignore: unnecessary_parenthesis
    (id.hashCode) +
    (name.hashCode) +
    (defaultCurrency.hashCode) +
    (isDirect.hashCode) +
    (simplifyDebts.hashCode) +
    (memberId.hashCode) +
    (displayName.hashCode);

  @override
  String toString() => 'GroupCreate[id=$id, name=$name, defaultCurrency=$defaultCurrency, isDirect=$isDirect, simplifyDebts=$simplifyDebts, memberId=$memberId, displayName=$displayName]';

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{};
      json[r'id'] = this.id;
      json[r'name'] = this.name;
      json[r'defaultCurrency'] = this.defaultCurrency;
      json[r'isDirect'] = this.isDirect;
      json[r'simplifyDebts'] = this.simplifyDebts;
      json[r'memberId'] = this.memberId;
      json[r'displayName'] = this.displayName;
    return json;
  }

  /// Returns a new [GroupCreate] instance and imports its values from
  /// [value] if it's a [Map], null otherwise.
  // ignore: prefer_constructors_over_static_methods
  static GroupCreate? fromJson(dynamic value) {
    if (value is Map) {
      final json = value.cast<String, dynamic>();

      // Ensure that the map contains the required keys.
      // Note 1: the values aren't checked for validity beyond being non-null.
      // Note 2: this code is stripped in release mode!
      assert(() {
        assert(json.containsKey(r'id'), 'Required key "GroupCreate[id]" is missing from JSON.');
        assert(json[r'id'] != null, 'Required key "GroupCreate[id]" has a null value in JSON.');
        assert(json.containsKey(r'name'), 'Required key "GroupCreate[name]" is missing from JSON.');
        assert(json[r'name'] != null, 'Required key "GroupCreate[name]" has a null value in JSON.');
        assert(json.containsKey(r'defaultCurrency'), 'Required key "GroupCreate[defaultCurrency]" is missing from JSON.');
        assert(json[r'defaultCurrency'] != null, 'Required key "GroupCreate[defaultCurrency]" has a null value in JSON.');
        assert(json.containsKey(r'memberId'), 'Required key "GroupCreate[memberId]" is missing from JSON.');
        assert(json[r'memberId'] != null, 'Required key "GroupCreate[memberId]" has a null value in JSON.');
        assert(json.containsKey(r'displayName'), 'Required key "GroupCreate[displayName]" is missing from JSON.');
        assert(json[r'displayName'] != null, 'Required key "GroupCreate[displayName]" has a null value in JSON.');
        return true;
      }());

      return GroupCreate(
        id: mapValueOfType<String>(json, r'id')!,
        name: mapValueOfType<String>(json, r'name')!,
        defaultCurrency: mapValueOfType<String>(json, r'defaultCurrency')!,
        isDirect: mapValueOfType<bool>(json, r'isDirect') ?? false,
        simplifyDebts: mapValueOfType<bool>(json, r'simplifyDebts') ?? true,
        memberId: mapValueOfType<String>(json, r'memberId')!,
        displayName: mapValueOfType<String>(json, r'displayName')!,
      );
    }
    return null;
  }

  static List<GroupCreate> listFromJson(dynamic json, {bool growable = false,}) {
    final result = <GroupCreate>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = GroupCreate.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }

  static Map<String, GroupCreate> mapFromJson(dynamic json) {
    final map = <String, GroupCreate>{};
    if (json is Map && json.isNotEmpty) {
      json = json.cast<String, dynamic>(); // ignore: parameter_assignments
      for (final entry in json.entries) {
        final value = GroupCreate.fromJson(entry.value);
        if (value != null) {
          map[entry.key] = value;
        }
      }
    }
    return map;
  }

  // maps a json object with a list of GroupCreate-objects as value to a dart map
  static Map<String, List<GroupCreate>> mapListFromJson(dynamic json, {bool growable = false,}) {
    final map = <String, List<GroupCreate>>{};
    if (json is Map && json.isNotEmpty) {
      // ignore: parameter_assignments
      json = json.cast<String, dynamic>();
      for (final entry in json.entries) {
        map[entry.key] = GroupCreate.listFromJson(entry.value, growable: growable,);
      }
    }
    return map;
  }

  /// The list of required keys that must be present in a JSON.
  static const requiredKeys = <String>{
    'id',
    'name',
    'defaultCurrency',
    'memberId',
    'displayName',
  };
}

