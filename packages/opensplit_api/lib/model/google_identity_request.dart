//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//
// @dart=2.18

// ignore_for_file: unused_element, unused_import
// ignore_for_file: always_put_required_named_parameters_first
// ignore_for_file: constant_identifier_names
// ignore_for_file: lines_longer_than_80_chars

part of openapi.api;

class GoogleIdentityRequest {
  /// Returns a new [GoogleIdentityRequest] instance.
  GoogleIdentityRequest({
    required this.idToken,
    this.nonce,
    this.allowSignIn = false,
  });

  String idToken;

  ///
  /// Please note: This property should have been non-nullable! Since the specification file
  /// does not include a default value (using the "default:" property), however, the generated
  /// source code must fall back to having a nullable type.
  /// Consider adding a "default:" property in the specification file to hide this note.
  ///
  String? nonce;

  bool allowSignIn;

  @override
  bool operator ==(Object other) => identical(this, other) || other is GoogleIdentityRequest &&
    other.idToken == idToken &&
    other.nonce == nonce &&
    other.allowSignIn == allowSignIn;

  @override
  int get hashCode =>
    // ignore: unnecessary_parenthesis
    (idToken.hashCode) +
    (nonce == null ? 0 : nonce!.hashCode) +
    (allowSignIn.hashCode);

  @override
  String toString() => 'GoogleIdentityRequest[idToken=$idToken, nonce=$nonce, allowSignIn=$allowSignIn]';

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{};
      json[r'idToken'] = this.idToken;
    if (this.nonce != null) {
      json[r'nonce'] = this.nonce;
    } else {
      json[r'nonce'] = null;
    }
      json[r'allowSignIn'] = this.allowSignIn;
    return json;
  }

  /// Returns a new [GoogleIdentityRequest] instance and imports its values from
  /// [value] if it's a [Map], null otherwise.
  // ignore: prefer_constructors_over_static_methods
  static GoogleIdentityRequest? fromJson(dynamic value) {
    if (value is Map) {
      final json = value.cast<String, dynamic>();

      // Ensure that the map contains the required keys.
      // Note 1: the values aren't checked for validity beyond being non-null.
      // Note 2: this code is stripped in release mode!
      assert(() {
        assert(json.containsKey(r'idToken'), 'Required key "GoogleIdentityRequest[idToken]" is missing from JSON.');
        assert(json[r'idToken'] != null, 'Required key "GoogleIdentityRequest[idToken]" has a null value in JSON.');
        return true;
      }());

      return GoogleIdentityRequest(
        idToken: mapValueOfType<String>(json, r'idToken')!,
        nonce: mapValueOfType<String>(json, r'nonce'),
        allowSignIn: mapValueOfType<bool>(json, r'allowSignIn') ?? false,
      );
    }
    return null;
  }

  static List<GoogleIdentityRequest> listFromJson(dynamic json, {bool growable = false,}) {
    final result = <GoogleIdentityRequest>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = GoogleIdentityRequest.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }

  static Map<String, GoogleIdentityRequest> mapFromJson(dynamic json) {
    final map = <String, GoogleIdentityRequest>{};
    if (json is Map && json.isNotEmpty) {
      json = json.cast<String, dynamic>(); // ignore: parameter_assignments
      for (final entry in json.entries) {
        final value = GoogleIdentityRequest.fromJson(entry.value);
        if (value != null) {
          map[entry.key] = value;
        }
      }
    }
    return map;
  }

  // maps a json object with a list of GoogleIdentityRequest-objects as value to a dart map
  static Map<String, List<GoogleIdentityRequest>> mapListFromJson(dynamic json, {bool growable = false,}) {
    final map = <String, List<GoogleIdentityRequest>>{};
    if (json is Map && json.isNotEmpty) {
      // ignore: parameter_assignments
      json = json.cast<String, dynamic>();
      for (final entry in json.entries) {
        map[entry.key] = GoogleIdentityRequest.listFromJson(entry.value, growable: growable,);
      }
    }
    return map;
  }

  /// The list of required keys that must be present in a JSON.
  static const requiredKeys = <String>{
    'idToken',
  };
}

