//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//
// @dart=2.18

// ignore_for_file: unused_element, unused_import
// ignore_for_file: always_put_required_named_parameters_first
// ignore_for_file: constant_identifier_names
// ignore_for_file: lines_longer_than_80_chars

part of openapi.api;

class EntryInput {
  /// Returns a new [EntryInput] instance.
  EntryInput({
    required this.id,
    this.kind,
    this.description = '',
    this.categoryId,
    required this.currency,
    required this.amountMinor,
    required this.entryDate,
    this.splitKind,
    this.fxRate,
    this.fxSource,
    this.notes,
    this.clientKey,
    this.payers = const [],
    this.shares = const [],
    this.baseSeq,
  });

  String id;

  ///
  /// Please note: This property should have been non-nullable! Since the specification file
  /// does not include a default value (using the "default:" property), however, the generated
  /// source code must fall back to having a nullable type.
  /// Consider adding a "default:" property in the specification file to hide this note.
  ///
  EntryKind? kind;

  String description;

  String? categoryId;

  String currency;

  /// Minimum value: 0
  int amountMinor;

  String entryDate;

  ///
  /// Please note: This property should have been non-nullable! Since the specification file
  /// does not include a default value (using the "default:" property), however, the generated
  /// source code must fall back to having a nullable type.
  /// Consider adding a "default:" property in the specification file to hide this note.
  ///
  SplitKind? splitKind;

  /// Minimum value: 0
  num? fxRate;

  String? fxSource;

  String? notes;

  String? clientKey;

  List<Payer> payers;

  List<Share> shares;

  /// Minimum value: 0
  int? baseSeq;

  @override
  bool operator ==(Object other) => identical(this, other) || other is EntryInput &&
    other.id == id &&
    other.kind == kind &&
    other.description == description &&
    other.categoryId == categoryId &&
    other.currency == currency &&
    other.amountMinor == amountMinor &&
    other.entryDate == entryDate &&
    other.splitKind == splitKind &&
    other.fxRate == fxRate &&
    other.fxSource == fxSource &&
    other.notes == notes &&
    other.clientKey == clientKey &&
    _deepEquality.equals(other.payers, payers) &&
    _deepEquality.equals(other.shares, shares) &&
    other.baseSeq == baseSeq;

  @override
  int get hashCode =>
    // ignore: unnecessary_parenthesis
    (id.hashCode) +
    (kind == null ? 0 : kind!.hashCode) +
    (description.hashCode) +
    (categoryId == null ? 0 : categoryId!.hashCode) +
    (currency.hashCode) +
    (amountMinor.hashCode) +
    (entryDate.hashCode) +
    (splitKind == null ? 0 : splitKind!.hashCode) +
    (fxRate == null ? 0 : fxRate!.hashCode) +
    (fxSource == null ? 0 : fxSource!.hashCode) +
    (notes == null ? 0 : notes!.hashCode) +
    (clientKey == null ? 0 : clientKey!.hashCode) +
    (payers.hashCode) +
    (shares.hashCode) +
    (baseSeq == null ? 0 : baseSeq!.hashCode);

  @override
  String toString() => 'EntryInput[id=$id, kind=$kind, description=$description, categoryId=$categoryId, currency=$currency, amountMinor=$amountMinor, entryDate=$entryDate, splitKind=$splitKind, fxRate=$fxRate, fxSource=$fxSource, notes=$notes, clientKey=$clientKey, payers=$payers, shares=$shares, baseSeq=$baseSeq]';

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{};
      json[r'id'] = this.id;
    if (this.kind != null) {
      json[r'kind'] = this.kind;
    } else {
      json[r'kind'] = null;
    }
      json[r'description'] = this.description;
    if (this.categoryId != null) {
      json[r'categoryId'] = this.categoryId;
    } else {
      json[r'categoryId'] = null;
    }
      json[r'currency'] = this.currency;
      json[r'amountMinor'] = this.amountMinor;
      json[r'entryDate'] = this.entryDate;
    if (this.splitKind != null) {
      json[r'splitKind'] = this.splitKind;
    } else {
      json[r'splitKind'] = null;
    }
    if (this.fxRate != null) {
      json[r'fxRate'] = this.fxRate;
    } else {
      json[r'fxRate'] = null;
    }
    if (this.fxSource != null) {
      json[r'fxSource'] = this.fxSource;
    } else {
      json[r'fxSource'] = null;
    }
    if (this.notes != null) {
      json[r'notes'] = this.notes;
    } else {
      json[r'notes'] = null;
    }
    if (this.clientKey != null) {
      json[r'clientKey'] = this.clientKey;
    } else {
      json[r'clientKey'] = null;
    }
      json[r'payers'] = this.payers;
      json[r'shares'] = this.shares;
    if (this.baseSeq != null) {
      json[r'baseSeq'] = this.baseSeq;
    } else {
      json[r'baseSeq'] = null;
    }
    return json;
  }

  /// Returns a new [EntryInput] instance and imports its values from
  /// [value] if it's a [Map], null otherwise.
  // ignore: prefer_constructors_over_static_methods
  static EntryInput? fromJson(dynamic value) {
    if (value is Map) {
      final json = value.cast<String, dynamic>();

      // Ensure that the map contains the required keys.
      // Note 1: the values aren't checked for validity beyond being non-null.
      // Note 2: this code is stripped in release mode!
      assert(() {
        assert(json.containsKey(r'id'), 'Required key "EntryInput[id]" is missing from JSON.');
        assert(json[r'id'] != null, 'Required key "EntryInput[id]" has a null value in JSON.');
        assert(json.containsKey(r'currency'), 'Required key "EntryInput[currency]" is missing from JSON.');
        assert(json[r'currency'] != null, 'Required key "EntryInput[currency]" has a null value in JSON.');
        assert(json.containsKey(r'amountMinor'), 'Required key "EntryInput[amountMinor]" is missing from JSON.');
        assert(json[r'amountMinor'] != null, 'Required key "EntryInput[amountMinor]" has a null value in JSON.');
        assert(json.containsKey(r'entryDate'), 'Required key "EntryInput[entryDate]" is missing from JSON.');
        assert(json[r'entryDate'] != null, 'Required key "EntryInput[entryDate]" has a null value in JSON.');
        assert(json.containsKey(r'payers'), 'Required key "EntryInput[payers]" is missing from JSON.');
        assert(json[r'payers'] != null, 'Required key "EntryInput[payers]" has a null value in JSON.');
        assert(json.containsKey(r'shares'), 'Required key "EntryInput[shares]" is missing from JSON.');
        assert(json[r'shares'] != null, 'Required key "EntryInput[shares]" has a null value in JSON.');
        return true;
      }());

      return EntryInput(
        id: mapValueOfType<String>(json, r'id')!,
        kind: EntryKind.fromJson(json[r'kind']),
        description: mapValueOfType<String>(json, r'description') ?? '',
        categoryId: mapValueOfType<String>(json, r'categoryId'),
        currency: mapValueOfType<String>(json, r'currency')!,
        amountMinor: mapValueOfType<int>(json, r'amountMinor')!,
        entryDate: mapValueOfType<String>(json, r'entryDate')!,
        splitKind: SplitKind.fromJson(json[r'splitKind']),
        fxRate: json[r'fxRate'] == null
            ? null
            : num.parse('${json[r'fxRate']}'),
        fxSource: mapValueOfType<String>(json, r'fxSource'),
        notes: mapValueOfType<String>(json, r'notes'),
        clientKey: mapValueOfType<String>(json, r'clientKey'),
        payers: Payer.listFromJson(json[r'payers']),
        shares: Share.listFromJson(json[r'shares']),
        baseSeq: mapValueOfType<int>(json, r'baseSeq'),
      );
    }
    return null;
  }

  static List<EntryInput> listFromJson(dynamic json, {bool growable = false,}) {
    final result = <EntryInput>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = EntryInput.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }

  static Map<String, EntryInput> mapFromJson(dynamic json) {
    final map = <String, EntryInput>{};
    if (json is Map && json.isNotEmpty) {
      json = json.cast<String, dynamic>(); // ignore: parameter_assignments
      for (final entry in json.entries) {
        final value = EntryInput.fromJson(entry.value);
        if (value != null) {
          map[entry.key] = value;
        }
      }
    }
    return map;
  }

  // maps a json object with a list of EntryInput-objects as value to a dart map
  static Map<String, List<EntryInput>> mapListFromJson(dynamic json, {bool growable = false,}) {
    final map = <String, List<EntryInput>>{};
    if (json is Map && json.isNotEmpty) {
      // ignore: parameter_assignments
      json = json.cast<String, dynamic>();
      for (final entry in json.entries) {
        map[entry.key] = EntryInput.listFromJson(entry.value, growable: growable,);
      }
    }
    return map;
  }

  /// The list of required keys that must be present in a JSON.
  static const requiredKeys = <String>{
    'id',
    'currency',
    'amountMinor',
    'entryDate',
    'payers',
    'shares',
  };
}

