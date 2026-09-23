//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//
// @dart=2.18

// ignore_for_file: unused_element, unused_import
// ignore_for_file: always_put_required_named_parameters_first
// ignore_for_file: constant_identifier_names
// ignore_for_file: lines_longer_than_80_chars

part of openapi.api;


enum EventKind {
  entry._(r'entry'),
  memberAdded._(r'member_added'),
  memberJoined._(r'member_joined'),
  memberLeft._(r'member_left'),
  memberRenamed._(r'member_renamed'),
  groupRenamed._(r'group_renamed'),
  groupArchived._(r'group_archived'),
  groupRestored._(r'group_restored'),
  linkCreated._(r'link_created'),
  linkRevoked._(r'link_revoked'),
  ;

  /// Instantiate a new enum with the provided value.
  const EventKind._(this._value);

  /// The underlying value of this enum member.
  final String _value;

  @override
  String toString() => _value;

  /// Encodes this enum as a value suitable for JSON.
  String toJson() => _value;

  /// Returns the instance of [EventKind] that was successfully decoded
  /// from the passed [value] on success, null otherwise.
  static EventKind? fromJson(dynamic value) => EventKindTypeTransformer().decode(value);

  /// Returns a [List] containing instances of [EventKind]
  /// that were successfully decoded from the passed [JSON][json].
  static List<EventKind> listFromJson(dynamic json, {bool growable = false,}) {
    final result = <EventKind>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = EventKind.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }
}

/// Transformation class that can [encode] an instance of [EventKind] to String,
/// and [decode] dynamic data back to [EventKind].
class EventKindTypeTransformer {
  factory EventKindTypeTransformer() => _instance ??= const EventKindTypeTransformer._();

  const EventKindTypeTransformer._();

  /// Encodes this enum as a value suitable for JSON.
  String encode(EventKind data) => data._value;

  /// Returns the instance of [EventKind] that was successfully decoded
  /// from the passed [data] value on success, null otherwise.
  ///
  /// If [allowNull] is true and the [dynamic value][data] cannot be decoded successfully,
  /// then null is returned. However, if [allowNull] is false and the [dynamic value][data]
  /// cannot be decoded successfully, then an [UnimplementedError] is thrown.
  ///
  /// The [allowNull] is very handy when an API changes and a new enum value is added or removed,
  /// and users are still using an old app with the old code.
  EventKind? decode(dynamic data, {bool allowNull = true}) {
    if (data is EventKind) {
      return data;
    }
    if (data != null) {
      switch (data) {
        case r'entry': return EventKind.entry;
        case r'member_added': return EventKind.memberAdded;
        case r'member_joined': return EventKind.memberJoined;
        case r'member_left': return EventKind.memberLeft;
        case r'member_renamed': return EventKind.memberRenamed;
        case r'group_renamed': return EventKind.groupRenamed;
        case r'group_archived': return EventKind.groupArchived;
        case r'group_restored': return EventKind.groupRestored;
        case r'link_created': return EventKind.linkCreated;
        case r'link_revoked': return EventKind.linkRevoked;
        default:
          if (!allowNull) {
            throw ArgumentError('Unknown enum value to decode: $data');
          }
      }
    }
    return null;
  }

  /// The singleton instance of this transformer.
  static EventKindTypeTransformer? _instance;
}

