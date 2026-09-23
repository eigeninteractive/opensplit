//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//
// @dart=2.18

// ignore_for_file: unused_element, unused_import
// ignore_for_file: always_put_required_named_parameters_first
// ignore_for_file: constant_identifier_names
// ignore_for_file: lines_longer_than_80_chars

part of openapi.api;

class Event {
  /// Returns a new [Event] instance.
  Event({
    required this.id,
    required this.actorId,
    required this.createdAt,
    required this.kind,
    required this.subjectId,
    this.payload = const {},
    required this.seq,
  });

  String id;

  String? actorId;

  DateTime createdAt;

  EventKind kind;

  String? subjectId;

  /// The after-image, in whatever shape `kind` calls for: EntrySnapshot, MemberEventPayload, GroupEventPayload or LinkEventPayload.
  Map<String, Object?> payload;

  /// Minimum value: 0
  int seq;

  @override
  bool operator ==(Object other) => identical(this, other) || other is Event &&
    other.id == id &&
    other.actorId == actorId &&
    other.createdAt == createdAt &&
    other.kind == kind &&
    other.subjectId == subjectId &&
    _deepEquality.equals(other.payload, payload) &&
    other.seq == seq;

  @override
  int get hashCode =>
    // ignore: unnecessary_parenthesis
    (id.hashCode) +
    (actorId == null ? 0 : actorId!.hashCode) +
    (createdAt.hashCode) +
    (kind.hashCode) +
    (subjectId == null ? 0 : subjectId!.hashCode) +
    (payload.hashCode) +
    (seq.hashCode);

  @override
  String toString() => 'Event[id=$id, actorId=$actorId, createdAt=$createdAt, kind=$kind, subjectId=$subjectId, payload=$payload, seq=$seq]';

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{};
      json[r'id'] = this.id;
    if (this.actorId != null) {
      json[r'actorId'] = this.actorId;
    } else {
      json[r'actorId'] = null;
    }
      json[r'createdAt'] = this.createdAt.toUtc().toIso8601String();
      json[r'kind'] = this.kind;
    if (this.subjectId != null) {
      json[r'subjectId'] = this.subjectId;
    } else {
      json[r'subjectId'] = null;
    }
      json[r'payload'] = this.payload;
      json[r'seq'] = this.seq;
    return json;
  }

  /// Returns a new [Event] instance and imports its values from
  /// [value] if it's a [Map], null otherwise.
  // ignore: prefer_constructors_over_static_methods
  static Event? fromJson(dynamic value) {
    if (value is Map) {
      final json = value.cast<String, dynamic>();

      // Ensure that the map contains the required keys.
      // Note 1: the values aren't checked for validity beyond being non-null.
      // Note 2: this code is stripped in release mode!
      assert(() {
        assert(json.containsKey(r'id'), 'Required key "Event[id]" is missing from JSON.');
        assert(json[r'id'] != null, 'Required key "Event[id]" has a null value in JSON.');
        assert(json.containsKey(r'actorId'), 'Required key "Event[actorId]" is missing from JSON.');
        assert(json.containsKey(r'createdAt'), 'Required key "Event[createdAt]" is missing from JSON.');
        assert(json[r'createdAt'] != null, 'Required key "Event[createdAt]" has a null value in JSON.');
        assert(json.containsKey(r'kind'), 'Required key "Event[kind]" is missing from JSON.');
        assert(json[r'kind'] != null, 'Required key "Event[kind]" has a null value in JSON.');
        assert(json.containsKey(r'subjectId'), 'Required key "Event[subjectId]" is missing from JSON.');
        assert(json.containsKey(r'seq'), 'Required key "Event[seq]" is missing from JSON.');
        assert(json[r'seq'] != null, 'Required key "Event[seq]" has a null value in JSON.');
        return true;
      }());

      return Event(
        id: mapValueOfType<String>(json, r'id')!,
        actorId: mapValueOfType<String>(json, r'actorId'),
        createdAt: mapDateTime(json, r'createdAt', r'')!,
        kind: EventKind.fromJson(json[r'kind'])!,
        subjectId: mapValueOfType<String>(json, r'subjectId'),
        payload: mapCastOfType<String, Object>(json, r'payload') ?? const {},
        seq: mapValueOfType<int>(json, r'seq')!,
      );
    }
    return null;
  }

  static List<Event> listFromJson(dynamic json, {bool growable = false,}) {
    final result = <Event>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = Event.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }

  static Map<String, Event> mapFromJson(dynamic json) {
    final map = <String, Event>{};
    if (json is Map && json.isNotEmpty) {
      json = json.cast<String, dynamic>(); // ignore: parameter_assignments
      for (final entry in json.entries) {
        final value = Event.fromJson(entry.value);
        if (value != null) {
          map[entry.key] = value;
        }
      }
    }
    return map;
  }

  // maps a json object with a list of Event-objects as value to a dart map
  static Map<String, List<Event>> mapListFromJson(dynamic json, {bool growable = false,}) {
    final map = <String, List<Event>>{};
    if (json is Map && json.isNotEmpty) {
      // ignore: parameter_assignments
      json = json.cast<String, dynamic>();
      for (final entry in json.entries) {
        map[entry.key] = Event.listFromJson(entry.value, growable: growable,);
      }
    }
    return map;
  }

  /// The list of required keys that must be present in a JSON.
  static const requiredKeys = <String>{
    'id',
    'actorId',
    'createdAt',
    'kind',
    'subjectId',
    'seq',
  };
}

