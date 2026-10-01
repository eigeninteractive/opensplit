import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:opensplit_api/opensplit_api.dart' show EntryKind, Payer, Share;

import '../../data/local/database.dart' show EntryRow;

part 'entry.freezed.dart';

/// An editor tried to replace an entry that changed after the form opened.
class StaleEntryException implements Exception {
  const StaleEntryException();

  @override
  String toString() =>
      'This entry changed while you were editing. Your draft '
      'has not been saved. Reopen the entry to review its latest version.';
}

/// A single financial fact: an expense someone paid, or a settlement between
/// two members.
///
/// Its columns are the stored [row], and its payers and shares are the wire's
/// own types, so nothing here restates a field the table already declares.
@freezed
abstract class Entry with _$Entry {
  const factory Entry(
    EntryRow row, {
    required List<Payer> payers,
    required List<Share> shares,
  }) = _Entry;

  const Entry._();

  String get id => row.id;

  bool get isDeleted => row.deletedAt != null;

  /// Whether this entry counts toward spend analytics.
  bool get isSpend => row.kind == EntryKind.expense && !isDeleted;

  /// The invariant, checked locally: payers and shares each sum to the total.
  bool get isBalanced {
    final paid = payers.fold(0, (sum, p) => sum + p.amountMinor);
    final owed = shares.fold(0, (sum, s) => sum + s.amountMinor);
    return paid == row.amountMinor && owed == row.amountMinor;
  }
}
