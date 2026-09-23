//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//
// @dart=2.18

// ignore_for_file: unused_element, unused_import
// ignore_for_file: always_put_required_named_parameters_first
// ignore_for_file: constant_identifier_names
// ignore_for_file: lines_longer_than_80_chars

part of openapi.api;

class Entry {
  /// Returns a new [Entry] instance.
  Entry({
    required this.id,
    required this.kind,
    required this.description,
    required this.categoryId,
    required this.currency,
    required this.amountMinor,
    required this.entryDate,
    required this.splitKind,
    required this.fxRate,
    required this.fxSource,
    required this.fxAt,
    required this.notes,
    required this.createdBy,
    required this.clientKey,
    required this.createdAt,
    required this.updatedAt,
    required this.deletedAt,
    this.payers = const [],
    this.shares = const [],
    required this.seq,
  });

  String id;

  EntryKind kind;

  String description;

  String? categoryId;

  String currency;

  /// Minimum value: 0
  int amountMinor;

  String entryDate;

  SplitKind splitKind;

  /// Minimum value: 0
  num? fxRate;

  String? fxSource;

  DateTime? fxAt;

  String? notes;

  String createdBy;

  String? clientKey;

  DateTime createdAt;

  DateTime updatedAt;

  DateTime? deletedAt;

  List<Payer> payers;

  List<Share> shares;

  /// Minimum value: 0
  int seq;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Entry &&
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
          other.fxAt == fxAt &&
          other.notes == notes &&
          other.createdBy == createdBy &&
          other.clientKey == clientKey &&
          other.createdAt == createdAt &&
          other.updatedAt == updatedAt &&
          other.deletedAt == deletedAt &&
          _deepEquality.equals(other.payers, payers) &&
          _deepEquality.equals(other.shares, shares) &&
          other.seq == seq;

  @override
  int get hashCode =>
      // ignore: unnecessary_parenthesis
      (id.hashCode) +
      (kind.hashCode) +
      (description.hashCode) +
      (categoryId == null ? 0 : categoryId!.hashCode) +
      (currency.hashCode) +
      (amountMinor.hashCode) +
      (entryDate.hashCode) +
      (splitKind.hashCode) +
      (fxRate == null ? 0 : fxRate!.hashCode) +
      (fxSource == null ? 0 : fxSource!.hashCode) +
      (fxAt == null ? 0 : fxAt!.hashCode) +
      (notes == null ? 0 : notes!.hashCode) +
      (createdBy.hashCode) +
      (clientKey == null ? 0 : clientKey!.hashCode) +
      (createdAt.hashCode) +
      (updatedAt.hashCode) +
      (deletedAt == null ? 0 : deletedAt!.hashCode) +
      (payers.hashCode) +
      (shares.hashCode) +
      (seq.hashCode);

  @override
  String toString() =>
      'Entry[id=$id, kind=$kind, description=$description, categoryId=$categoryId, currency=$currency, amountMinor=$amountMinor, entryDate=$entryDate, splitKind=$splitKind, fxRate=$fxRate, fxSource=$fxSource, fxAt=$fxAt, notes=$notes, createdBy=$createdBy, clientKey=$clientKey, createdAt=$createdAt, updatedAt=$updatedAt, deletedAt=$deletedAt, payers=$payers, shares=$shares, seq=$seq]';

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{};
    json[r'id'] = this.id;
    json[r'kind'] = this.kind;
    json[r'description'] = this.description;
    if (this.categoryId != null) {
      json[r'categoryId'] = this.categoryId;
    } else {
      json[r'categoryId'] = null;
    }
    json[r'currency'] = this.currency;
    json[r'amountMinor'] = this.amountMinor;
    json[r'entryDate'] = this.entryDate;
    json[r'splitKind'] = this.splitKind;
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
    if (this.fxAt != null) {
      json[r'fxAt'] = this.fxAt!.toUtc().toIso8601String();
    } else {
      json[r'fxAt'] = null;
    }
    if (this.notes != null) {
      json[r'notes'] = this.notes;
    } else {
      json[r'notes'] = null;
    }
    json[r'createdBy'] = this.createdBy;
    if (this.clientKey != null) {
      json[r'clientKey'] = this.clientKey;
    } else {
      json[r'clientKey'] = null;
    }
    json[r'createdAt'] = this.createdAt.toUtc().toIso8601String();
    json[r'updatedAt'] = this.updatedAt.toUtc().toIso8601String();
    if (this.deletedAt != null) {
      json[r'deletedAt'] = this.deletedAt!.toUtc().toIso8601String();
    } else {
      json[r'deletedAt'] = null;
    }
    json[r'payers'] = this.payers;
    json[r'shares'] = this.shares;
    json[r'seq'] = this.seq;
    return json;
  }

  /// Returns a new [Entry] instance and imports its values from
  /// [value] if it's a [Map], null otherwise.
  // ignore: prefer_constructors_over_static_methods
  static Entry? fromJson(dynamic value) {
    if (value is Map) {
      final json = value.cast<String, dynamic>();

      // Ensure that the map contains the required keys.
      // Note 1: the values aren't checked for validity beyond being non-null.
      // Note 2: this code is stripped in release mode!
      assert(() {
        assert(json.containsKey(r'id'),
            'Required key "Entry[id]" is missing from JSON.');
        assert(json[r'id'] != null,
            'Required key "Entry[id]" has a null value in JSON.');
        assert(json.containsKey(r'kind'),
            'Required key "Entry[kind]" is missing from JSON.');
        assert(json[r'kind'] != null,
            'Required key "Entry[kind]" has a null value in JSON.');
        assert(json.containsKey(r'description'),
            'Required key "Entry[description]" is missing from JSON.');
        assert(json[r'description'] != null,
            'Required key "Entry[description]" has a null value in JSON.');
        assert(json.containsKey(r'categoryId'),
            'Required key "Entry[categoryId]" is missing from JSON.');
        assert(json.containsKey(r'currency'),
            'Required key "Entry[currency]" is missing from JSON.');
        assert(json[r'currency'] != null,
            'Required key "Entry[currency]" has a null value in JSON.');
        assert(json.containsKey(r'amountMinor'),
            'Required key "Entry[amountMinor]" is missing from JSON.');
        assert(json[r'amountMinor'] != null,
            'Required key "Entry[amountMinor]" has a null value in JSON.');
        assert(json.containsKey(r'entryDate'),
            'Required key "Entry[entryDate]" is missing from JSON.');
        assert(json[r'entryDate'] != null,
            'Required key "Entry[entryDate]" has a null value in JSON.');
        assert(json.containsKey(r'splitKind'),
            'Required key "Entry[splitKind]" is missing from JSON.');
        assert(json[r'splitKind'] != null,
            'Required key "Entry[splitKind]" has a null value in JSON.');
        assert(json.containsKey(r'fxRate'),
            'Required key "Entry[fxRate]" is missing from JSON.');
        assert(json.containsKey(r'fxSource'),
            'Required key "Entry[fxSource]" is missing from JSON.');
        assert(json.containsKey(r'fxAt'),
            'Required key "Entry[fxAt]" is missing from JSON.');
        assert(json.containsKey(r'notes'),
            'Required key "Entry[notes]" is missing from JSON.');
        assert(json.containsKey(r'createdBy'),
            'Required key "Entry[createdBy]" is missing from JSON.');
        assert(json[r'createdBy'] != null,
            'Required key "Entry[createdBy]" has a null value in JSON.');
        assert(json.containsKey(r'clientKey'),
            'Required key "Entry[clientKey]" is missing from JSON.');
        assert(json.containsKey(r'createdAt'),
            'Required key "Entry[createdAt]" is missing from JSON.');
        assert(json[r'createdAt'] != null,
            'Required key "Entry[createdAt]" has a null value in JSON.');
        assert(json.containsKey(r'updatedAt'),
            'Required key "Entry[updatedAt]" is missing from JSON.');
        assert(json[r'updatedAt'] != null,
            'Required key "Entry[updatedAt]" has a null value in JSON.');
        assert(json.containsKey(r'deletedAt'),
            'Required key "Entry[deletedAt]" is missing from JSON.');
        assert(json.containsKey(r'payers'),
            'Required key "Entry[payers]" is missing from JSON.');
        assert(json[r'payers'] != null,
            'Required key "Entry[payers]" has a null value in JSON.');
        assert(json.containsKey(r'shares'),
            'Required key "Entry[shares]" is missing from JSON.');
        assert(json[r'shares'] != null,
            'Required key "Entry[shares]" has a null value in JSON.');
        assert(json.containsKey(r'seq'),
            'Required key "Entry[seq]" is missing from JSON.');
        assert(json[r'seq'] != null,
            'Required key "Entry[seq]" has a null value in JSON.');
        return true;
      }());

      return Entry(
        id: mapValueOfType<String>(json, r'id')!,
        kind: EntryKind.fromJson(json[r'kind'])!,
        description: mapValueOfType<String>(json, r'description')!,
        categoryId: mapValueOfType<String>(json, r'categoryId'),
        currency: mapValueOfType<String>(json, r'currency')!,
        amountMinor: mapValueOfType<int>(json, r'amountMinor')!,
        entryDate: mapValueOfType<String>(json, r'entryDate')!,
        splitKind: SplitKind.fromJson(json[r'splitKind'])!,
        fxRate:
            json[r'fxRate'] == null ? null : num.parse('${json[r'fxRate']}'),
        fxSource: mapValueOfType<String>(json, r'fxSource'),
        fxAt: mapDateTime(json, r'fxAt', r''),
        notes: mapValueOfType<String>(json, r'notes'),
        createdBy: mapValueOfType<String>(json, r'createdBy')!,
        clientKey: mapValueOfType<String>(json, r'clientKey'),
        createdAt: mapDateTime(json, r'createdAt', r'')!,
        updatedAt: mapDateTime(json, r'updatedAt', r'')!,
        deletedAt: mapDateTime(json, r'deletedAt', r''),
        payers: Payer.listFromJson(json[r'payers']),
        shares: Share.listFromJson(json[r'shares']),
        seq: mapValueOfType<int>(json, r'seq')!,
      );
    }
    return null;
  }

  static List<Entry> listFromJson(
    dynamic json, {
    bool growable = false,
  }) {
    final result = <Entry>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = Entry.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }

  static Map<String, Entry> mapFromJson(dynamic json) {
    final map = <String, Entry>{};
    if (json is Map && json.isNotEmpty) {
      json = json.cast<String, dynamic>(); // ignore: parameter_assignments
      for (final entry in json.entries) {
        final value = Entry.fromJson(entry.value);
        if (value != null) {
          map[entry.key] = value;
        }
      }
    }
    return map;
  }

  // maps a json object with a list of Entry-objects as value to a dart map
  static Map<String, List<Entry>> mapListFromJson(
    dynamic json, {
    bool growable = false,
  }) {
    final map = <String, List<Entry>>{};
    if (json is Map && json.isNotEmpty) {
      // ignore: parameter_assignments
      json = json.cast<String, dynamic>();
      for (final entry in json.entries) {
        map[entry.key] = Entry.listFromJson(
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
    'kind',
    'description',
    'categoryId',
    'currency',
    'amountMinor',
    'entryDate',
    'splitKind',
    'fxRate',
    'fxSource',
    'fxAt',
    'notes',
    'createdBy',
    'clientKey',
    'createdAt',
    'updatedAt',
    'deletedAt',
    'payers',
    'shares',
    'seq',
  };
}
