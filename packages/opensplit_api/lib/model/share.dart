//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//
// @dart=2.18

// ignore_for_file: unused_element, unused_import
// ignore_for_file: always_put_required_named_parameters_first
// ignore_for_file: constant_identifier_names
// ignore_for_file: lines_longer_than_80_chars

part of openapi.api;

class Share {
  /// Returns a new [Share] instance.
  Share({
    required this.memberId,
    required this.amountMinor,
    this.weightMicros,
  });

  String memberId;

  /// Minimum value: 0
  int amountMinor;

  int? weightMicros;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Share &&
          other.memberId == memberId &&
          other.amountMinor == amountMinor &&
          other.weightMicros == weightMicros;

  @override
  int get hashCode =>
      // ignore: unnecessary_parenthesis
      (memberId.hashCode) +
      (amountMinor.hashCode) +
      (weightMicros == null ? 0 : weightMicros!.hashCode);

  @override
  String toString() =>
      'Share[memberId=$memberId, amountMinor=$amountMinor, weightMicros=$weightMicros]';

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{};
    json[r'memberId'] = this.memberId;
    json[r'amountMinor'] = this.amountMinor;
    if (this.weightMicros != null) {
      json[r'weightMicros'] = this.weightMicros;
    } else {
      json[r'weightMicros'] = null;
    }
    return json;
  }

  /// Returns a new [Share] instance and imports its values from
  /// [value] if it's a [Map], null otherwise.
  // ignore: prefer_constructors_over_static_methods
  static Share? fromJson(dynamic value) {
    if (value is Map) {
      final json = value.cast<String, dynamic>();

      // Ensure that the map contains the required keys.
      // Note 1: the values aren't checked for validity beyond being non-null.
      // Note 2: this code is stripped in release mode!
      assert(() {
        assert(json.containsKey(r'memberId'),
            'Required key "Share[memberId]" is missing from JSON.');
        assert(json[r'memberId'] != null,
            'Required key "Share[memberId]" has a null value in JSON.');
        assert(json.containsKey(r'amountMinor'),
            'Required key "Share[amountMinor]" is missing from JSON.');
        assert(json[r'amountMinor'] != null,
            'Required key "Share[amountMinor]" has a null value in JSON.');
        return true;
      }());

      return Share(
        memberId: mapValueOfType<String>(json, r'memberId')!,
        amountMinor: mapValueOfType<int>(json, r'amountMinor')!,
        weightMicros: mapValueOfType<int>(json, r'weightMicros'),
      );
    }
    return null;
  }

  static List<Share> listFromJson(
    dynamic json, {
    bool growable = false,
  }) {
    final result = <Share>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = Share.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }

  static Map<String, Share> mapFromJson(dynamic json) {
    final map = <String, Share>{};
    if (json is Map && json.isNotEmpty) {
      json = json.cast<String, dynamic>(); // ignore: parameter_assignments
      for (final entry in json.entries) {
        final value = Share.fromJson(entry.value);
        if (value != null) {
          map[entry.key] = value;
        }
      }
    }
    return map;
  }

  // maps a json object with a list of Share-objects as value to a dart map
  static Map<String, List<Share>> mapListFromJson(
    dynamic json, {
    bool growable = false,
  }) {
    final map = <String, List<Share>>{};
    if (json is Map && json.isNotEmpty) {
      // ignore: parameter_assignments
      json = json.cast<String, dynamic>();
      for (final entry in json.entries) {
        map[entry.key] = Share.listFromJson(
          entry.value,
          growable: growable,
        );
      }
    }
    return map;
  }

  /// The list of required keys that must be present in a JSON.
  static const requiredKeys = <String>{
    'memberId',
    'amountMinor',
  };
}
