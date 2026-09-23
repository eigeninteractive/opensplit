//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//
// @dart=2.18

// ignore_for_file: unused_element, unused_import
// ignore_for_file: always_put_required_named_parameters_first
// ignore_for_file: constant_identifier_names
// ignore_for_file: lines_longer_than_80_chars

part of openapi.api;

class Member {
  /// Returns a new [Member] instance.
  Member({
    required this.id,
    required this.profileId,
    required this.displayName,
    required this.upiVpa,
    required this.joinedAt,
    required this.leftAt,
    required this.updatedAt,
    required this.seq,
  });

  String id;

  String? profileId;

  String displayName;

  String? upiVpa;

  DateTime joinedAt;

  DateTime? leftAt;

  DateTime updatedAt;

  /// Minimum value: 0
  int seq;

  @override
  bool operator ==(Object other) => identical(this, other) || other is Member &&
    other.id == id &&
    other.profileId == profileId &&
    other.displayName == displayName &&
    other.upiVpa == upiVpa &&
    other.joinedAt == joinedAt &&
    other.leftAt == leftAt &&
    other.updatedAt == updatedAt &&
    other.seq == seq;

  @override
  int get hashCode =>
    // ignore: unnecessary_parenthesis
    (id.hashCode) +
    (profileId == null ? 0 : profileId!.hashCode) +
    (displayName.hashCode) +
    (upiVpa == null ? 0 : upiVpa!.hashCode) +
    (joinedAt.hashCode) +
    (leftAt == null ? 0 : leftAt!.hashCode) +
    (updatedAt.hashCode) +
    (seq.hashCode);

  @override
  String toString() => 'Member[id=$id, profileId=$profileId, displayName=$displayName, upiVpa=$upiVpa, joinedAt=$joinedAt, leftAt=$leftAt, updatedAt=$updatedAt, seq=$seq]';

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{};
      json[r'id'] = this.id;
    if (this.profileId != null) {
      json[r'profileId'] = this.profileId;
    } else {
      json[r'profileId'] = null;
    }
      json[r'displayName'] = this.displayName;
    if (this.upiVpa != null) {
      json[r'upiVpa'] = this.upiVpa;
    } else {
      json[r'upiVpa'] = null;
    }
      json[r'joinedAt'] = this.joinedAt.toUtc().toIso8601String();
    if (this.leftAt != null) {
      json[r'leftAt'] = this.leftAt!.toUtc().toIso8601String();
    } else {
      json[r'leftAt'] = null;
    }
      json[r'updatedAt'] = this.updatedAt.toUtc().toIso8601String();
      json[r'seq'] = this.seq;
    return json;
  }

  /// Returns a new [Member] instance and imports its values from
  /// [value] if it's a [Map], null otherwise.
  // ignore: prefer_constructors_over_static_methods
  static Member? fromJson(dynamic value) {
    if (value is Map) {
      final json = value.cast<String, dynamic>();

      // Ensure that the map contains the required keys.
      // Note 1: the values aren't checked for validity beyond being non-null.
      // Note 2: this code is stripped in release mode!
      assert(() {
        assert(json.containsKey(r'id'), 'Required key "Member[id]" is missing from JSON.');
        assert(json[r'id'] != null, 'Required key "Member[id]" has a null value in JSON.');
        assert(json.containsKey(r'profileId'), 'Required key "Member[profileId]" is missing from JSON.');
        assert(json.containsKey(r'displayName'), 'Required key "Member[displayName]" is missing from JSON.');
        assert(json[r'displayName'] != null, 'Required key "Member[displayName]" has a null value in JSON.');
        assert(json.containsKey(r'upiVpa'), 'Required key "Member[upiVpa]" is missing from JSON.');
        assert(json.containsKey(r'joinedAt'), 'Required key "Member[joinedAt]" is missing from JSON.');
        assert(json[r'joinedAt'] != null, 'Required key "Member[joinedAt]" has a null value in JSON.');
        assert(json.containsKey(r'leftAt'), 'Required key "Member[leftAt]" is missing from JSON.');
        assert(json.containsKey(r'updatedAt'), 'Required key "Member[updatedAt]" is missing from JSON.');
        assert(json[r'updatedAt'] != null, 'Required key "Member[updatedAt]" has a null value in JSON.');
        assert(json.containsKey(r'seq'), 'Required key "Member[seq]" is missing from JSON.');
        assert(json[r'seq'] != null, 'Required key "Member[seq]" has a null value in JSON.');
        return true;
      }());

      return Member(
        id: mapValueOfType<String>(json, r'id')!,
        profileId: mapValueOfType<String>(json, r'profileId'),
        displayName: mapValueOfType<String>(json, r'displayName')!,
        upiVpa: mapValueOfType<String>(json, r'upiVpa'),
        joinedAt: mapDateTime(json, r'joinedAt', r'')!,
        leftAt: mapDateTime(json, r'leftAt', r''),
        updatedAt: mapDateTime(json, r'updatedAt', r'')!,
        seq: mapValueOfType<int>(json, r'seq')!,
      );
    }
    return null;
  }

  static List<Member> listFromJson(dynamic json, {bool growable = false,}) {
    final result = <Member>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = Member.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }

  static Map<String, Member> mapFromJson(dynamic json) {
    final map = <String, Member>{};
    if (json is Map && json.isNotEmpty) {
      json = json.cast<String, dynamic>(); // ignore: parameter_assignments
      for (final entry in json.entries) {
        final value = Member.fromJson(entry.value);
        if (value != null) {
          map[entry.key] = value;
        }
      }
    }
    return map;
  }

  // maps a json object with a list of Member-objects as value to a dart map
  static Map<String, List<Member>> mapListFromJson(dynamic json, {bool growable = false,}) {
    final map = <String, List<Member>>{};
    if (json is Map && json.isNotEmpty) {
      // ignore: parameter_assignments
      json = json.cast<String, dynamic>();
      for (final entry in json.entries) {
        map[entry.key] = Member.listFromJson(entry.value, growable: growable,);
      }
    }
    return map;
  }

  /// The list of required keys that must be present in a JSON.
  static const requiredKeys = <String>{
    'id',
    'profileId',
    'displayName',
    'upiVpa',
    'joinedAt',
    'leftAt',
    'updatedAt',
    'seq',
  };
}

