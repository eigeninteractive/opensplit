import '../../domain/models/entry.dart';
import '../../domain/split/splitter.dart';

/// An expense, as this device stores one it needs to keep whole.
///
/// Used by the conflict store, which parks the edit the server refused so a
/// person can look at both versions and decide. That row can sit there for
/// days, across app updates, and possibly across a change to the wire format.
///
/// So this is deliberately **not** the wire codec, which is what it used to be.
/// A conflict is a local fact about something this device tried to do; binding
/// its storage to the shape of a request would mean a server-side rename could
/// make an old parked edit unreadable, in the one place whose entire job is to
/// still be readable later.
///
/// Whole rather than a diff, for the same reason the column holding it is: a
/// diff needs a base to be read against, and the base is precisely what moved.
Map<String, Object?> entryToJson(Entry entry) => {
  'id': entry.id,
  'groupId': entry.groupId,
  'kind': entry.kind.name,
  'description': entry.description,
  'categoryId': entry.categoryId,
  'currency': entry.currency,
  'amountMinor': entry.amountMinor,
  'entryDate': entry.entryDate.toIso8601String(),
  'splitKind': entry.splitKind.name,
  'fxRate': entry.fxRate,
  'fxSource': entry.fxSource,
  'fxAt': entry.fxAt?.toIso8601String(),
  'notes': entry.notes,
  'createdBy': entry.createdBy,
  'createdAt': entry.createdAt.toIso8601String(),
  'deletedAt': entry.deletedAt?.toIso8601String(),
  'clientKey': entry.clientKey,
  'seq': entry.seq,
  'payers': [
    for (final payer in entry.payers)
      {'memberId': payer.memberId, 'amountMinor': payer.amountMinor},
  ],
  'shares': [
    for (final share in entry.shares)
      {
        'memberId': share.memberId,
        'amountMinor': share.amountMinor,
        'weightMicros': share.weightMicros,
      },
  ],
};

Entry entryFromJson(Map<String, Object?> json) => Entry(
  id: json['id'] as String,
  groupId: json['groupId'] as String,
  kind: _enumByName(EntryKind.values, json['kind'], EntryKind.expense),
  description: json['description'] as String? ?? '',
  categoryId: json['categoryId'] as String?,
  currency: json['currency'] as String,
  amountMinor: json['amountMinor'] as int,
  entryDate: DateTime.parse(json['entryDate'] as String),
  splitKind: _enumByName(SplitKind.values, json['splitKind'], SplitKind.equal),
  fxRate: (json['fxRate'] as num?)?.toDouble(),
  fxSource: json['fxSource'] as String?,
  fxAt: _parseOrNull(json['fxAt']),
  notes: json['notes'] as String?,
  createdBy: json['createdBy'] as String,
  createdAt: DateTime.parse(json['createdAt'] as String),
  deletedAt: _parseOrNull(json['deletedAt']),
  clientKey: json['clientKey'] as String?,
  seq: json['seq'] as int?,
  payers: [
    for (final payer
        in (json['payers'] as List? ?? const []).cast<Map<String, Object?>>())
      EntryPayer(
        memberId: payer['memberId'] as String,
        amountMinor: payer['amountMinor'] as int,
      ),
  ],
  shares: [
    for (final share
        in (json['shares'] as List? ?? const []).cast<Map<String, Object?>>())
      EntryShare(
        memberId: share['memberId'] as String,
        amountMinor: share['amountMinor'] as int,
        weightMicros: share['weightMicros'] as int?,
      ),
  ],
);

/// Falls back rather than throwing, because a value this build has never heard
/// of must not make a parked conflict unopenable.
T _enumByName<T extends Enum>(List<T> values, Object? name, T fallback) {
  for (final value in values) {
    if (value.name == name) return value;
  }
  return fallback;
}

DateTime? _parseOrNull(Object? value) =>
    value is String ? DateTime.parse(value) : null;
