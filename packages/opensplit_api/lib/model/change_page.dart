//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//
// @dart=2.18

// ignore_for_file: unused_element, unused_import
// ignore_for_file: always_put_required_named_parameters_first
// ignore_for_file: constant_identifier_names
// ignore_for_file: lines_longer_than_80_chars

part of openapi.api;

class ChangePage {
  /// Returns a new [ChangePage] instance.
  ChangePage({
    required this.seq,
    required this.hasMore,
    required this.group,
    this.members = const [],
    this.entries = const [],
    this.events = const [],
    required this.purgedAt,
  });

  /// Minimum value: 0
  int seq;

  bool hasMore;

  Group? group;

  List<Member> members;

  List<Entry> entries;

  List<Event> events;

  DateTime? purgedAt;

  @override
  bool operator ==(Object other) => identical(this, other) || other is ChangePage &&
    other.seq == seq &&
    other.hasMore == hasMore &&
    other.group == group &&
    _deepEquality.equals(other.members, members) &&
    _deepEquality.equals(other.entries, entries) &&
    _deepEquality.equals(other.events, events) &&
    other.purgedAt == purgedAt;

  @override
  int get hashCode =>
    // ignore: unnecessary_parenthesis
    (seq.hashCode) +
    (hasMore.hashCode) +
    (group == null ? 0 : group!.hashCode) +
    (members.hashCode) +
    (entries.hashCode) +
    (events.hashCode) +
    (purgedAt == null ? 0 : purgedAt!.hashCode);

  @override
  String toString() => 'ChangePage[seq=$seq, hasMore=$hasMore, group=$group, members=$members, entries=$entries, events=$events, purgedAt=$purgedAt]';

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{};
      json[r'seq'] = this.seq;
      json[r'hasMore'] = this.hasMore;
    if (this.group != null) {
      json[r'group'] = this.group;
    } else {
      json[r'group'] = null;
    }
      json[r'members'] = this.members;
      json[r'entries'] = this.entries;
      json[r'events'] = this.events;
    if (this.purgedAt != null) {
      json[r'purgedAt'] = this.purgedAt!.toUtc().toIso8601String();
    } else {
      json[r'purgedAt'] = null;
    }
    return json;
  }

  /// Returns a new [ChangePage] instance and imports its values from
  /// [value] if it's a [Map], null otherwise.
  // ignore: prefer_constructors_over_static_methods
  static ChangePage? fromJson(dynamic value) {
    if (value is Map) {
      final json = value.cast<String, dynamic>();

      // Ensure that the map contains the required keys.
      // Note 1: the values aren't checked for validity beyond being non-null.
      // Note 2: this code is stripped in release mode!
      assert(() {
        assert(json.containsKey(r'seq'), 'Required key "ChangePage[seq]" is missing from JSON.');
        assert(json[r'seq'] != null, 'Required key "ChangePage[seq]" has a null value in JSON.');
        assert(json.containsKey(r'hasMore'), 'Required key "ChangePage[hasMore]" is missing from JSON.');
        assert(json[r'hasMore'] != null, 'Required key "ChangePage[hasMore]" has a null value in JSON.');
        assert(json.containsKey(r'group'), 'Required key "ChangePage[group]" is missing from JSON.');
        assert(json.containsKey(r'members'), 'Required key "ChangePage[members]" is missing from JSON.');
        assert(json[r'members'] != null, 'Required key "ChangePage[members]" has a null value in JSON.');
        assert(json.containsKey(r'entries'), 'Required key "ChangePage[entries]" is missing from JSON.');
        assert(json[r'entries'] != null, 'Required key "ChangePage[entries]" has a null value in JSON.');
        assert(json.containsKey(r'events'), 'Required key "ChangePage[events]" is missing from JSON.');
        assert(json[r'events'] != null, 'Required key "ChangePage[events]" has a null value in JSON.');
        assert(json.containsKey(r'purgedAt'), 'Required key "ChangePage[purgedAt]" is missing from JSON.');
        return true;
      }());

      return ChangePage(
        seq: mapValueOfType<int>(json, r'seq')!,
        hasMore: mapValueOfType<bool>(json, r'hasMore')!,
        group: Group.fromJson(json[r'group']),
        members: Member.listFromJson(json[r'members']),
        entries: Entry.listFromJson(json[r'entries']),
        events: Event.listFromJson(json[r'events']),
        purgedAt: mapDateTime(json, r'purgedAt', r''),
      );
    }
    return null;
  }

  static List<ChangePage> listFromJson(dynamic json, {bool growable = false,}) {
    final result = <ChangePage>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = ChangePage.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }

  static Map<String, ChangePage> mapFromJson(dynamic json) {
    final map = <String, ChangePage>{};
    if (json is Map && json.isNotEmpty) {
      json = json.cast<String, dynamic>(); // ignore: parameter_assignments
      for (final entry in json.entries) {
        final value = ChangePage.fromJson(entry.value);
        if (value != null) {
          map[entry.key] = value;
        }
      }
    }
    return map;
  }

  // maps a json object with a list of ChangePage-objects as value to a dart map
  static Map<String, List<ChangePage>> mapListFromJson(dynamic json, {bool growable = false,}) {
    final map = <String, List<ChangePage>>{};
    if (json is Map && json.isNotEmpty) {
      // ignore: parameter_assignments
      json = json.cast<String, dynamic>();
      for (final entry in json.entries) {
        map[entry.key] = ChangePage.listFromJson(entry.value, growable: growable,);
      }
    }
    return map;
  }

  /// The list of required keys that must be present in a JSON.
  static const requiredKeys = <String>{
    'seq',
    'hasMore',
    'group',
    'members',
    'entries',
    'events',
    'purgedAt',
  };
}

