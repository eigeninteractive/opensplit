//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//
// @dart=2.18

// ignore_for_file: unused_element, unused_import
// ignore_for_file: always_put_required_named_parameters_first
// ignore_for_file: constant_identifier_names
// ignore_for_file: lines_longer_than_80_chars

part of openapi.api;

class Account {
  /// Returns a new [Account] instance.
  Account({
    required this.id,
    required this.isAnonymous,
    required this.email,
    required this.displayName,
  });

  String id;

  bool isAnonymous;

  String? email;

  String? displayName;

  @override
  bool operator ==(Object other) => identical(this, other) || other is Account &&
    other.id == id &&
    other.isAnonymous == isAnonymous &&
    other.email == email &&
    other.displayName == displayName;

  @override
  int get hashCode =>
    // ignore: unnecessary_parenthesis
    (id.hashCode) +
    (isAnonymous.hashCode) +
    (email == null ? 0 : email!.hashCode) +
    (displayName == null ? 0 : displayName!.hashCode);

  @override
  String toString() => 'Account[id=$id, isAnonymous=$isAnonymous, email=$email, displayName=$displayName]';

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{};
      json[r'id'] = this.id;
      json[r'isAnonymous'] = this.isAnonymous;
    if (this.email != null) {
      json[r'email'] = this.email;
    } else {
      json[r'email'] = null;
    }
    if (this.displayName != null) {
      json[r'displayName'] = this.displayName;
    } else {
      json[r'displayName'] = null;
    }
    return json;
  }

  /// Returns a new [Account] instance and imports its values from
  /// [value] if it's a [Map], null otherwise.
  // ignore: prefer_constructors_over_static_methods
  static Account? fromJson(dynamic value) {
    if (value is Map) {
      final json = value.cast<String, dynamic>();

      // Ensure that the map contains the required keys.
      // Note 1: the values aren't checked for validity beyond being non-null.
      // Note 2: this code is stripped in release mode!
      assert(() {
        assert(json.containsKey(r'id'), 'Required key "Account[id]" is missing from JSON.');
        assert(json[r'id'] != null, 'Required key "Account[id]" has a null value in JSON.');
        assert(json.containsKey(r'isAnonymous'), 'Required key "Account[isAnonymous]" is missing from JSON.');
        assert(json[r'isAnonymous'] != null, 'Required key "Account[isAnonymous]" has a null value in JSON.');
        assert(json.containsKey(r'email'), 'Required key "Account[email]" is missing from JSON.');
        assert(json.containsKey(r'displayName'), 'Required key "Account[displayName]" is missing from JSON.');
        return true;
      }());

      return Account(
        id: mapValueOfType<String>(json, r'id')!,
        isAnonymous: mapValueOfType<bool>(json, r'isAnonymous')!,
        email: mapValueOfType<String>(json, r'email'),
        displayName: mapValueOfType<String>(json, r'displayName'),
      );
    }
    return null;
  }

  static List<Account> listFromJson(dynamic json, {bool growable = false,}) {
    final result = <Account>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = Account.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }

  static Map<String, Account> mapFromJson(dynamic json) {
    final map = <String, Account>{};
    if (json is Map && json.isNotEmpty) {
      json = json.cast<String, dynamic>(); // ignore: parameter_assignments
      for (final entry in json.entries) {
        final value = Account.fromJson(entry.value);
        if (value != null) {
          map[entry.key] = value;
        }
      }
    }
    return map;
  }

  // maps a json object with a list of Account-objects as value to a dart map
  static Map<String, List<Account>> mapListFromJson(dynamic json, {bool growable = false,}) {
    final map = <String, List<Account>>{};
    if (json is Map && json.isNotEmpty) {
      // ignore: parameter_assignments
      json = json.cast<String, dynamic>();
      for (final entry in json.entries) {
        map[entry.key] = Account.listFromJson(entry.value, growable: growable,);
      }
    }
    return map;
  }

  /// The list of required keys that must be present in a JSON.
  static const requiredKeys = <String>{
    'id',
    'isAnonymous',
    'email',
    'displayName',
  };
}

