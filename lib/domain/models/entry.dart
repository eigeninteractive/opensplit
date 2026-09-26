import 'package:freezed_annotation/freezed_annotation.dart';

import 'kinds.dart';

export 'kinds.dart' show EntryKind, SplitKind;

part 'entry.freezed.dart';

/// An editor tried to replace an entry that changed after the form opened.
class StaleEntryException implements Exception {
  const StaleEntryException();

  @override
  String toString() =>
      'This entry changed while you were editing. Your draft '
      'has not been saved. Reopen the entry to review its latest version.';
}

/// Money actually put down by one member for an entry.
@freezed
abstract class EntryPayer with _$EntryPayer {
  const factory EntryPayer({
    required String memberId,
    required int amountMinor,
  }) = _EntryPayer;
}

/// What one member owes for an entry.
@freezed
abstract class EntryShare with _$EntryShare {
  const factory EntryShare({
    required String memberId,
    required int amountMinor,

    /// The original weight scaled by 10^6, or null for an exact split.
    int? weightMicros,
  }) = _EntryShare;
}

/// A single financial fact: an expense someone paid, or a settlement between
/// two members, with its payers and shares.
@freezed
abstract class Entry with _$Entry {
  const factory Entry({
    required String id,
    required String groupId,
    required EntryKind kind,
    required String description,
    String? categoryId,

    /// ISO 4217 code. Never converted on write: the amount is stored in the
    /// currency it was actually incurred in, forever.
    required String currency,
    required int amountMinor,
    required DateTime entryDate,

    /// When it happened, from the recording device's clock, and the IANA zone
    /// it happened in. Both or neither: a back-dated expense may have only a
    /// day. When set, [entryDate] is that moment's day in that zone.
    DateTime? occurredAt,
    String? timeZone,
    required SplitKind splitKind,
    required List<EntryPayer> payers,
    required List<EntryShare> shares,

    /// Rate from [currency] to the group's default currency, snapshotted when
    /// the entry was created.
    double? fxRate,
    String? fxSource,
    DateTime? fxAt,
    String? notes,

    /// The member who recorded this, which is not necessarily a payer.
    required String createdBy,
    required DateTime createdAt,

    /// The server's sequence number for this version, and the base the next
    /// edit is judged against. Null for a row the server has not seen.
    int? seq,

    /// Soft delete. Financial rows are never physically removed, so that a
    /// balance that changed can always be explained.
    DateTime? deletedAt,

    /// Client-generated, making a retried sync idempotent.
    String? clientKey,
  }) = _Entry;

  const Entry._();

  bool get isDeleted => deletedAt != null;

  /// Whether this entry counts toward spend analytics.
  bool get isSpend => kind == EntryKind.expense && !isDeleted;

  /// The invariant, checked locally: payers and shares each sum to the total.
  bool get isBalanced {
    final paid = payers.fold(0, (sum, p) => sum + p.amountMinor);
    final owed = shares.fold(0, (sum, s) => sum + s.amountMinor);
    return paid == amountMinor && owed == amountMinor;
  }
}
