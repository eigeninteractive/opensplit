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
/// two members, with its payers and shares.
///
/// A settlement is one payer and one share and folds through the same balance
/// path; it is excluded from spend analytics.
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
  ///
  /// The server enforces this too, in the group's Durable Object. Checking it
  /// here as well is not redundant — it fails at the point the bug happened,
  /// with the entry in hand, instead of as a refusal one sync later.
  bool get isBalanced {
    final paid = payers.fold(0, (sum, p) => sum + p.amountMinor);
    final owed = shares.fold(0, (sum, s) => sum + s.amountMinor);
    return paid == amountMinor && owed == amountMinor;
  }
}
