import 'package:freezed_annotation/freezed_annotation.dart';

import '../split/splitter.dart';

part 'entry.freezed.dart';

/// An editor tried to replace an entry that changed after the form opened.
class StaleEntryException implements Exception {
  const StaleEntryException();

  @override
  String toString() =>
      'This entry changed while you were editing. Your draft '
      'has not been saved. Reopen the entry to review its latest version.';
}

/// What kind of fact an entry records.
///
/// A settlement is one payer and one share, in the same table as expenses,
/// because it participates in the identical balance fold. It is excluded from
/// spend analytics — paying a friend back is not spending.
enum EntryKind { expense, settlement }

/// Money actually put down by one member for an entry.
///
/// This is a list rather than a `paid_by` column because "I got the food, you
/// got the drinks" is an ordinary bill, and it is where simpler models fall
/// over.
@freezed
abstract class EntryPayer with _$EntryPayer {
  const factory EntryPayer({
    required String memberId,
    required int amountMinor,
  }) = _EntryPayer;
}

/// What one member owes for an entry.
///
/// Carries both the resolved [amountMinor] and the [weightMicros] rule that
/// produced it. See [ResolvedShare] for why both are kept.
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
/// two members.
///
/// Entries are independent of one another — there is no cross-entry ordering
/// requirement — which is what lets sync be a cursor over `updated_at` rather
/// than a CRDT.
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
    required SplitKind splitKind,
    required List<EntryPayer> payers,
    required List<EntryShare> shares,

    /// Rate from [currency] to the group's default currency, snapshotted when
    /// the entry was created.
    ///
    /// Display only. It never enters the balance fold, which is why a double is
    /// acceptable here and nowhere else in this file. Never re-fetched for a
    /// historical entry — the rate on the day is a fact about the transaction.
    double? fxRate,
    String? fxSource,
    DateTime? fxAt,
    String? notes,

    /// The member who recorded this, which is not necessarily a payer.
    required String createdBy,
    required DateTime createdAt,
    required DateTime updatedAt,

    /// Soft delete. Financial rows are never physically removed, so that a
    /// balance that changed can always be explained.
    DateTime? deletedAt,

    /// Client-generated, making a retried sync idempotent.
    String? clientKey,

    /// Version of the split algorithm that produced [shares]. Historical
    /// entries are never recomputed under a newer version.
  }) = _Entry;

  const Entry._();

  bool get isDeleted => deletedAt != null;

  /// Whether this entry counts toward spend analytics.
  bool get isSpend => kind == EntryKind.expense && !isDeleted;

  /// The invariant, checked locally: payers and shares each sum to the total.
  ///
  /// The server enforces this too, via a deferred constraint trigger. Checking
  /// it here as well is not redundant — it fails at the point the bug happened,
  /// with the entry in hand, instead of as a Postgres exception one sync later.
  bool get isBalanced {
    final paid = payers.fold(0, (sum, p) => sum + p.amountMinor);
    final owed = shares.fold(0, (sum, s) => sum + s.amountMinor);
    return paid == amountMinor && owed == amountMinor;
  }
}
