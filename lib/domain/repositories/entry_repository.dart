import '../entry_draft.dart';
import '../models/entry.dart';

/// Reads and writes entries with their payers and shares.
///
/// An entry, its payers and its shares are one atomic fact. They are never
/// written separately — a torn write would leave a row that violates the
/// balance invariant, which is exactly what the server's deferred trigger
/// exists to make impossible.
abstract interface class EntryRepository {
  /// Every entry in a group, most recent first.
  ///
  /// Returns the whole journal rather than a page: balances are a fold over all
  /// of it, and the fold runs locally on every read. For the group sizes this
  /// app targets that is microseconds, and it is what removes the spinner from
  /// every screen.
  ///
  /// Soft-deleted entries are excluded unless [includeDeleted] is set. The
  /// balance fold ignores them either way; history screens want them.
  Stream<List<Entry>> watchEntries(String groupId, {bool includeDeleted = false});

  Stream<Entry?> watchEntry(String entryId);

  Future<List<Entry>> getEntries(String groupId, {bool includeDeleted = false});

  Future<Entry?> getEntry(String entryId);

  /// Resolves [draft] into a balanced entry and stores it.
  ///
  /// Throws [SplitException] if the draft does not describe a valid entry, in
  /// which case nothing is written.
  Future<Entry> create(
    EntryDraft draft, {
    required String createdBy,
    DateTime? now,
  });

  /// Replaces an existing entry's contents, keeping its id and creation
  /// metadata.
  Future<Entry> update(
    String entryId,
    EntryDraft draft, {
    DateTime? now,
  });

  /// Soft delete. The row stays so that a balance which changed can always be
  /// explained, and so the deletion itself can be synced to other devices.
  Future<void> delete(String entryId, {DateTime? now});
}
